import Foundation
import MusicKit
import Observation
import os

private let logger = Logger(subsystem: "com.sentio.home", category: "Music")

/// Handles ambient music playback via MusicKit.
/// Uses the system's Apple Music subscription for catalog access.
@Observable
@MainActor
final class MusicService {

    private(set) var isPlaying = false
    private(set) var currentTrackName: String?
    private(set) var currentArtistName: String?
    private(set) var currentMood: String?

    /// When false, music actions are skipped and the AI prompt omits music capability.
    private(set) var hasSubscription = false

    private nonisolated(unsafe) let player = ApplicationMusicPlayer.shared
    private var subscriptionTask: Task<Void, Never>?
    private var playbackObserver: Task<Void, Never>?
    private var pendingTransition: MusicResult?

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        logger.info("MusicKit authorization: \(String(describing: status))")

        subscriptionTask = Task {
            for await subscription in MusicSubscription.subscriptionUpdates {
                await MainActor.run {
                    self.hasSubscription = subscription.canPlayCatalogContent
                    logger.info("Apple Music subscription active: \(self.hasSubscription)")
                }
            }
        }

        let subscription = try? await MusicSubscription.current
        self.hasSubscription = subscription?.canPlayCatalogContent ?? false
        logger.info("Apple Music subscription active: \(self.hasSubscription)")

        playbackObserver = Task {
            for await _ in player.state.objectWillChange.values {
                await MainActor.run {
                    let playing = player.state.playbackStatus == .playing
                    if isPlaying && !playing {
                        if let transition = pendingTransition {
                            pendingTransition = nil
                            applyQueueItem(transition)
                            Task { try? await player.play() }
                            logger.info("DJ transition applied")
                        } else {
                            isPlaying = false
                            currentTrackName = nil
                            currentArtistName = nil
                            currentMood = nil
                            logger.info("Playback ended naturally")
                        }
                    }
                    if let nowPlaying = player.queue.currentEntry {
                        currentTrackName = nowPlaying.title
                        currentArtistName = nowPlaying.subtitle
                    }
                }
            }
        }
    }

    // MARK: - Execution

    func execute(_ action: MusicAction) async {
        if action.stop {
            await stop()
            return
        }

        guard hasSubscription else {
            logger.info("No Apple Music subscription, skipping music action")
            return
        }

        guard !action.query.isEmpty else {
            logger.info("Empty music query, skipping")
            return
        }

        if isPlaying && currentMood?.lowercased() == action.query.lowercased() {
            logger.info("Same mood \"\(action.query)\" already playing — letting it continue")
            return
        }

        do {
            guard let item = try await search(query: action.query) else {
                logger.warning("No results for query: \"\(action.query)\"")
                return
            }

            if isPlaying {
                pendingTransition = item
                currentMood = action.query
                logger.info("DJ: \"\(action.query)\" queued — will start after current track")
                return
            }

            applyQueueItem(item)
            try await player.play()

            currentMood = action.query
            isPlaying = true
            logger.info("Playing \"\(action.query)\" at volume \(action.volume)")

        } catch let error as NSError where error.domain == NSOSStatusErrorDomain {
            logger.error("Music playback failed (OSStatus \(error.code)). Ensure the MusicKit capability is enabled for this bundle ID in the Apple Developer portal.")
        } catch {
            logger.error("Music playback failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        player.pause()
        isPlaying = false
        currentTrackName = nil
        currentArtistName = nil
        currentMood = nil
        pendingTransition = nil

        logger.info("Music stopped")
    }

    private func applyQueueItem(_ item: MusicResult) {
        switch item {
        case .playlist(let playlist):
            player.queue = [playlist]
            currentTrackName = playlist.name
            currentArtistName = nil
        case .station(let station):
            player.queue = [station]
            currentTrackName = station.name
            currentArtistName = nil
        case .song(let song):
            player.queue = [song]
            currentTrackName = song.title
            currentArtistName = song.artistName
        case .album(let album):
            player.queue = [album]
            currentTrackName = album.title
            currentArtistName = album.artistName
        }
    }

    // MARK: - Search

    private enum MusicResult {
        case playlist(Playlist)
        case station(Station)
        case song(Song)
        case album(Album)
    }

    /// Prefers playlists/stations for ambient listening, falls back to songs/albums.
    private func search(query: String) async throws -> MusicResult? {
        var playlistRequest = MusicCatalogSearchRequest(term: query, types: [Playlist.self])
        playlistRequest.limit = 3
        let playlistResponse = try await playlistRequest.response()

        if let playlist = playlistResponse.playlists.first(where: { $0.curatorName == "Apple Music" })
            ?? playlistResponse.playlists.first {
            return .playlist(playlist)
        }

        var stationRequest = MusicCatalogSearchRequest(term: query, types: [Station.self])
        stationRequest.limit = 1
        let stationResponse = try await stationRequest.response()

        if let station = stationResponse.stations.first {
            return .station(station)
        }

        var albumRequest = MusicCatalogSearchRequest(term: query, types: [Album.self])
        albumRequest.limit = 1
        let albumResponse = try await albumRequest.response()

        if let album = albumResponse.albums.first {
            return .album(album)
        }

        var songRequest = MusicCatalogSearchRequest(term: query, types: [Song.self])
        songRequest.limit = 1
        let songResponse = try await songRequest.response()

        if let song = songResponse.songs.first {
            return .song(song)
        }

        return nil
    }

}

// MARK: - Comparable Clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
