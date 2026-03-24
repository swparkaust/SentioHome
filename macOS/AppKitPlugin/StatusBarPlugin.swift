import AppKit
import AudioToolbox
import CoreAudio
import CoreMediaIO
import IOKit
import SwiftUI

/// AppKit bundle plugin that creates an NSStatusItem for the Mac Catalyst app.
/// Loaded at runtime by the Catalyst app to provide a native menu bar experience.
///
/// Usage from Catalyst:
///   Bundle(url: builtInPlugInsURL.appendingPathComponent("StatusBarPlugin.bundle"))?.load()
///   let cls = NSClassFromString("StatusBarPlugin.StatusBarPlugin") as? NSObject.Type
///   let plugin = cls?.init()
///   plugin?.perform(NSSelectorFromString("showStatusItem:"), with: view)
@MainActor
@objc public class StatusBarPlugin: NSObject {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var contentVC: PopoverContentVC?

    @objc public func showStatusItem(_ contentProvider: Any?) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "house.and.flag.fill", accessibilityDescription: "Sentio Home")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.animates = true

        if let nsView = contentProvider as? NSView {
            let vc = NSViewController()
            vc.view = nsView
            popover.contentViewController = vc
        } else {
            let vc = PopoverContentVC()
            contentVC = vc
            popover.contentViewController = vc
        }

        self.statusItem = statusItem
        self.popover = popover
    }

    @objc public func updateState(_ dict: NSDictionary) {
        contentVC?.update(from: dict)
    }

    /// Uses NSWorkspace — only available in native AppKit, not Catalyst.
    @objc public func frontmostAppBundleID() -> NSString? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier as NSString?
    }

    @objc public func frontmostAppName() -> NSString? {
        NSWorkspace.shared.frontmostApplication?.localizedName as NSString?
    }

    // MARK: - Screen Activity (CoreGraphics)

    @objc public func isDisplayAsleep() -> NSNumber {
        NSNumber(value: CGDisplayIsAsleep(CGMainDisplayID()) != 0)
    }

    @objc public func systemIdleTime() -> NSNumber {
        let mouseIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let keyboardIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let cgIdle = min(mouseIdle, keyboardIdle)

        if cgIdle > 0 && cgIdle < 86400 {
            return NSNumber(value: cgIdle)
        }

        // IOKit fallback
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return NSNumber(value: cgIdle) }
        defer { IOObjectRelease(service) }

        if let property = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
           let nanoseconds = property as? UInt64 {
            return NSNumber(value: TimeInterval(nanoseconds) / 1_000_000_000)
        }

        return NSNumber(value: cgIdle)
    }

    // MARK: - Camera Detection

    @objc public func isCameraActive() -> NSNumber {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return NSNumber(value: false) }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: deviceCount)
        let getStatus = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0, nil,
            dataSize,
            &dataSize,
            &devices
        )
        guard getStatus == noErr else { return NSNumber(value: false) }

        for device in devices {
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )

            let runStatus = CMIOObjectGetPropertyData(
                device,
                &runningAddress,
                0, nil,
                runningSize,
                &runningSize,
                &isRunning
            )

            if runStatus == noErr && isRunning != 0 {
                return NSNumber(value: true)
            }
        }

        return NSNumber(value: false)
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure the popover becomes key so it can receive keyboard events
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - Popover Content (Pure AppKit)

@MainActor
private class PopoverContentVC: NSViewController {

    private let statusLabel = NSTextField(labelWithString: "Automating")
    private let deviceLabel = NSTextField(labelWithString: "0 devices")
    private let homeLabel = NSTextField(labelWithString: "0 home(s)")
    private let nextCheckLabel = NSTextField(labelWithString: "Next check: —")
    private let activityLabel = NSTextField(labelWithString: "No actions taken yet.")
    private let quickAskField = NSTextField()
    private let quickAskResponseLabel = NSTextField(labelWithString: "")
    private let pauseResumeButton = NSButton()
    private var isRunning = true
    private var extraLabels: [NSTextField] = []
    private var extraStack = NSStackView()

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 480))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Header
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        let icon = NSImageView(image: NSImage(systemSymbolName: "house.and.flag.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        let title = NSTextField(labelWithString: "Sentio Home")
        title.font = .boldSystemFont(ofSize: 14)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, statusLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        headerStack.addArrangedSubview(icon)
        headerStack.addArrangedSubview(titleStack)

        // Quick Ask
        quickAskField.placeholderString = "Ask or command…"
        quickAskField.font = .systemFont(ofSize: 11)
        quickAskField.bezelStyle = .roundedBezel
        quickAskField.target = self
        quickAskField.action = #selector(submitQuickAsk)
        quickAskResponseLabel.font = .systemFont(ofSize: 11)
        quickAskResponseLabel.textColor = .secondaryLabelColor
        quickAskResponseLabel.lineBreakMode = .byWordWrapping
        quickAskResponseLabel.maximumNumberOfLines = 3
        quickAskResponseLabel.isHidden = true

        // Status
        for label in [deviceLabel, homeLabel, nextCheckLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }

        extraStack.orientation = .vertical
        extraStack.alignment = .leading
        extraStack.spacing = 3

        // Activity
        let activityHeader = NSTextField(labelWithString: "RECENT ACTIVITY")
        activityHeader.font = .systemFont(ofSize: 9, weight: .medium)
        activityHeader.textColor = .tertiaryLabelColor
        activityLabel.font = .systemFont(ofSize: 11)
        activityLabel.textColor = .secondaryLabelColor

        // Controls
        func makeSeparator() -> NSBox {
            let sep = NSBox(); sep.boxType = .separator; return sep
        }
        let seps = (0..<6).map { _ in makeSeparator() }

        pauseResumeButton.title = "Pause Automation"
        pauseResumeButton.bezelStyle = .accessoryBarAction
        pauseResumeButton.isBordered = false
        pauseResumeButton.alignment = .left
        pauseResumeButton.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        pauseResumeButton.imagePosition = .imageLeading
        pauseResumeButton.target = self
        pauseResumeButton.action = #selector(toggleAutomation)

        let runNowButton = NSButton(title: "Run Now", target: self, action: #selector(runNow))
        runNowButton.bezelStyle = .accessoryBarAction
        runNowButton.isBordered = false
        runNowButton.alignment = .left
        runNowButton.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: nil)
        runNowButton.imagePosition = .imageLeading

        let settingsButton = NSButton(title: "Settings…", target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.isBordered = false
        settingsButton.alignment = .left
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsButton.imagePosition = .imageLeading

        let quitButton = NSButton(title: "Quit Sentio Home", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .accessoryBarAction
        quitButton.isBordered = false
        quitButton.alignment = .left
        quitButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        quitButton.imagePosition = .imageLeading

        stack.addArrangedSubview(headerStack)
        stack.addArrangedSubview(seps[0])
        stack.addArrangedSubview(quickAskField)
        stack.addArrangedSubview(quickAskResponseLabel)
        stack.addArrangedSubview(seps[1])
        stack.addArrangedSubview(deviceLabel)
        stack.addArrangedSubview(homeLabel)
        stack.addArrangedSubview(extraStack)
        stack.addArrangedSubview(nextCheckLabel)
        stack.addArrangedSubview(seps[2])
        stack.addArrangedSubview(activityHeader)
        stack.addArrangedSubview(activityLabel)
        stack.addArrangedSubview(seps[3])
        stack.addArrangedSubview(pauseResumeButton)
        stack.addArrangedSubview(seps[4])
        stack.addArrangedSubview(runNowButton)
        stack.addArrangedSubview(settingsButton)
        stack.addArrangedSubview(seps[5])
        stack.addArrangedSubview(quitButton)

        for sep in seps {
            sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        quickAskField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        quickAskResponseLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])

        self.view = container
    }

    private var pendingUpdate: NSDictionary?

    func update(from dict: NSDictionary) {
        guard isViewLoaded else { return }
        pendingUpdate = dict
        DispatchQueue.main.async { [weak self] in
            guard let self, let pending = self.pendingUpdate else { return }
            self.pendingUpdate = nil
            self.applyUpdate(from: pending)
        }
    }

    private func applyUpdate(from dict: NSDictionary) {
        let deviceCount = (dict["deviceCount"] as? Int) ?? 0
        let homeCount = (dict["homeCount"] as? Int) ?? 0
        isRunning = (dict["isRunning"] as? Bool) ?? true

        statusLabel.stringValue = isRunning ? "Automating" : "Paused"
        pauseResumeButton.title = isRunning ? "Pause Automation" : "Resume Automation"
        pauseResumeButton.image = NSImage(
            systemSymbolName: isRunning ? "pause.circle" : "play.circle",
            accessibilityDescription: nil
        )

        if let response = dict["quickAskResponse"] as? String {
            quickAskResponseLabel.stringValue = response
            quickAskResponseLabel.isHidden = false
        }
        deviceLabel.stringValue = "\(deviceCount) devices"
        homeLabel.stringValue = "\(homeCount) home(s)"

        // Build extra lines
        for label in extraLabels { label.removeFromSuperview() }
        extraLabels.removeAll()

        func addExtra(_ text: String) {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            extraStack.addArrangedSubview(label)
            extraLabels.append(label)
        }

        if let prefs = dict["preferencesLearned"] as? Int, prefs > 0 {
            addExtra("🧠 \(prefs) preferences learned")
        }
        if let np = dict["nowPlaying"] as? String { addExtra("♫ \(np)") }
        if (dict["inMeeting"] as? Bool) == true { addExtra("📅 In a meeting") }
        else if let ne = dict["nextEvent"] as? String { addExtra("📅 Next: \(ne)") }
        if let sa = dict["screenActivity"] as? String { addExtra("🖥 \(sa.capitalized(with: nil))") }
        if let mr = dict["motionRooms"] as? String { addExtra("🚶 Motion: \(mr)") }
        if let oc = dict["openContacts"] as? String { addExtra("🚪 Open: \(oc)") }
        if let gd = dict["guestsDetected"] as? String { addExtra("👥 \(gd)") }

        if let next = dict["nextCheckDate"] as? Date {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            nextCheckLabel.stringValue = "Next check: \(formatter.localizedString(for: next, relativeTo: Date()))"
        } else {
            nextCheckLabel.stringValue = "Next check: —"
        }

        if let actions = dict["recentActions"] as? [[String: Any]], !actions.isEmpty {
            let lines = actions.prefix(3).compactMap { $0["summary"] as? String }
            activityLabel.stringValue = lines.joined(separator: "\n")
        } else {
            activityLabel.stringValue = "No actions taken yet."
        }
    }

    @objc private func submitQuickAsk() {
        let text = quickAskField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        quickAskField.stringValue = ""
        NotificationCenter.default.post(
            name: Notification.Name("com.sentio.home.quickAsk"),
            object: nil,
            userInfo: ["message": text]
        )
    }

    @objc private func toggleAutomation() {
        NotificationCenter.default.post(name: Notification.Name("com.sentio.home.toggleAutomation"), object: nil)
    }

    @objc private func runNow() {
        NotificationCenter.default.post(name: Notification.Name("com.sentio.home.runNow"), object: nil)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: Notification.Name("com.sentio.home.openSettings"), object: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}


