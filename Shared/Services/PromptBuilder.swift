import Foundation

/// Pure prompt-construction logic extracted from IntelligenceEngine
/// for testability. Takes a HomeContext and returns a formatted markdown
/// prompt string with no external dependencies.
enum PromptBuilder {

    /// - Parameter automationGuidance: Include proactive automation rules (voice, music,
    ///   departure sweeps, vacuum timing). False for dialogue sessions.
    static func buildPrompt(
        from context: HomeContext,
        preferenceHistory: String? = nil,
        activeOverrides: String? = nil,
        automationGuidance: Bool = false
    ) -> String {
        var sections: [String] = []

        // Temporal
        sections.append("""
        ## Time
        - Date/Time: \(formatted(context.timestamp))
        - Period: \(context.timeOfDay.rawValue)
        - Day: \(dayName(context.dayOfWeek)) \(context.isWeekend ? "(weekend)" : "(weekday)")
        """)

        // Sun
        if let sunrise = context.sunriseTime, let sunset = context.sunsetTime {
            sections.append("""
            ## Sun
            - Sunrise: \(timeOnly(sunrise))
            - Sunset: \(timeOnly(sunset))
            """)
        }

        // Weather
        if let weather = context.weatherCondition {
            var weatherSection = "## Weather\n- Condition: \(sanitizeForPrompt(weather))"
            if let temp = context.outsideTemperatureCelsius {
                weatherSection += "\n- Temperature: \(String(format: "%.1f", temp))°C"
            }
            if let hum = context.humidity {
                weatherSection += "\n- Humidity: \(Int(hum * 100))%"
            }
            sections.append(weatherSection)
        }

        // Forecast
        if let forecast = context.forecast, !forecast.isEmpty {
            let forecastLines = forecast.map { hour in
                let precip = hour.precipitationChance > 0.1
                    ? ", \(Int(hour.precipitationChance * 100))% precip"
                    : ""
                let uv = hour.uvIndex >= 6 ? ", UV \(hour.uvIndex)" : ""
                return "- \(String(format: "%02d", hour.hour)):00 — " +
                       "\(String(format: "%.0f", hour.temperatureCelsius))°C, " +
                       "\(sanitizeForPrompt(hour.condition))\(precip)\(uv)"
            }
            var forecastSection = "## Forecast (next \(forecast.count)h)\n" + forecastLines.joined(separator: "\n")
            forecastSection += "\n- Act anticipatorily: pre-cool/warm before 5°C+ swings, " +
                "mention open windows if rain >30%. UV 6+ → close sun-facing blinds. " +
                "Don't cite forecast numbers in reasons."
            sections.append(forecastSection)
        }

        // Presence
        let othersPresent = (context.otherOccupantsHome ?? false) || (context.guestsLikelyPresent ?? false)
        var presenceLines = ["- User is \(context.userIsHome ? "home" : "away")"]
        if !context.userIsHome && othersPresent {
            presenceLines.append("- ⚠️ HOUSE IS STILL OCCUPIED — do NOT perform departure shutdown. " +
                "Keep comfortable and welcoming for remaining occupants.")
        }
        if let approaching = context.approachingHome, approaching {
            presenceLines.append("- APPROACHING HOME (within ~1km) — prepare now: entry lights, thermostat, welcome music")
        }
        if let room = context.currentRoom {
            presenceLines.append("- Current room: \(sanitizeForPrompt(room))")
        }
        if let rooms = context.activeMotionRooms, !rooms.isEmpty {
            presenceLines.append("- Motion detected in: \(rooms.map(sanitizeForPrompt).joined(separator: ", ")) " +
                "— brighten occupied rooms, dim empty ones to save energy")
        }
        if let occupants = context.occupantCount, occupants > 1 {
            presenceLines.append("- \(occupants) people home (app users) — be conservative: " +
                "don't dim shared spaces, no vacuum, say \"home\" not \"you\" in reasons")
        } else if let others = context.otherOccupantsHome, others {
            presenceLines.append("- Other household members are home — be conservative: " +
                "don't dim shared spaces, no vacuum, say \"home\" not \"you\" in reasons")
        }
        if let guestsPresent = context.guestsLikelyPresent, guestsPresent {
            let conf = context.guestConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "?"
            let reason = sanitizeForPrompt(context.guestInferenceReason ?? "multiple signals")
            presenceLines.append("- GUESTS LIKELY PRESENT (confidence: \(conf), reason: \(reason))")
            presenceLines.append("- Guest mode: keep shared spaces well-lit and welcoming, comfortable temp, " +
                "no vacuum/locks, prefer AirPods for voice, no personal announcements, " +
                "avoid mentioning health/sleep/routines. " +
                "At low confidence (50-60%) be conservative; at high (80%+) fully commit. " +
                "When guests leave, return to normal gradually.")
        }
        sections.append("## Presence\n" + presenceLines.joined(separator: "\n"))

        // Companion sensors
        var sensorLines: [String] = []
        if let lux = context.ambientLightLux {
            sensorLines.append("- Ambient light: \(Int(lux)) lux")
        }
        if let activity = context.deviceMotionActivity {
            sensorLines.append("- Activity: \(sanitizeForPrompt(activity))")
        }
        if let brightness = context.screenBrightness {
            sensorLines.append("- iPhone screen brightness: \(Int(brightness * 100))%")
        }
        if !sensorLines.isEmpty {
            sections.append("## iPhone Sensors\n" + sensorLines.joined(separator: "\n"))
        }

        // AirPods
        if let connected = context.airPodsConnected, connected {
            let inEar = context.airPodsInEar ?? false
            var airPodsLines = [
                "- Connected: yes",
                "- In ear: \(inEar ? "yes" : "no (on table/in case — do NOT route voice to AirPods)")",
            ]
            if let posture = context.headPosture, inEar {
                airPodsLines.append("- Head posture: \(sanitizeForPrompt(posture))")
                airPodsLines.append("- Posture guide: upright=normal, reclined=relaxing (dim/warm light), " +
                    "lookingDown=reading/phone (task light), nodding=drowsy (begin sleep mode)")
            }
            airPodsLines.append("- Don't mention AirPods in reasons.")
            sections.append("## AirPods\n" + airPodsLines.joined(separator: "\n"))
        }

        // Watch health data
        var watchLines: [String] = []
        if let hr = context.heartRate {
            watchLines.append("- Heart rate: \(Int(hr)) bpm")
        }
        if let hrv = context.heartRateVariability {
            watchLines.append("- Heart rate variability (HRV): \(Int(hrv)) ms")
        }
        if let sleep = context.sleepState {
            watchLines.append("- Sleep state: \(sleep)")
        }
        if let workout = context.isWorkingOut, workout {
            watchLines.append("- Currently working out")
        }
        if let tempDelta = context.wristTemperatureDelta {
            let sign = tempDelta >= 0 ? "+" : ""
            watchLines.append("- Wrist temperature: \(sign)\(String(format: "%.1f", tempDelta))°C from baseline")
        }
        if let spo2 = context.bloodOxygen {
            watchLines.append("- Blood oxygen: \(Int(spo2 * 100))%")
        }
        if !watchLines.isEmpty {
            watchLines.append("- Interpretation: asleep states → lights off, comfortable sleep temp. " +
                "inBed → very dim warm light only. Positive wrist temp delta → user is warm, consider cooling. " +
                "Negative → cold, consider warming. Elevated resting HR → stress, prefer calm lighting. " +
                "Low HRV → fatigue. Workout → good visibility, don't change thermostat, no vacuum. " +
                "Don't mention health data in reasons.")
            sections.append("## Apple Watch Health\n" + watchLines.joined(separator: "\n"))
        }

        // Audio routes
        var audioLines: [String] = []
        if let airpods = context.airPodsAvailable, airpods {
            audioLines.append("- AirPods: connected (bidirectional)")
        }
        if audioLines.isEmpty {
            audioLines.append("- No audio routes available (do not include communication)")
        }
        sections.append("## Audio Routes\n" + audioLines.joined(separator: "\n"))

        // Music
        if let available = context.musicAvailable {
            var musicLines: [String] = []
            if !available {
                musicLines.append("- Apple Music not available (do NOT include music actions)")
            } else if let playing = context.currentlyPlayingMusic, playing, let track = context.currentMusicTrack {
                musicLines.append("- Currently playing: \"\(sanitizeForPrompt(track))\"")
                if let mood = context.currentMusicMood {
                    musicLines.append("- Current mood/query: \"\(sanitizeForPrompt(mood))\" — use the same query to let it continue, or a different query to transition")
                }
            } else {
                musicLines.append("- No music playing")
            }
            sections.append("## Music\n" + musicLines.joined(separator: "\n"))
        }

        // Calendar
        if let events = context.upcomingEvents, !events.isEmpty {
            var calendarLines = events.map(\.promptDescription)
            if let inEvent = context.isInEvent, inEvent {
                calendarLines.insert("- CURRENTLY IN AN EVENT — minimize disruptions: no voice, no vacuum, stable lights", at: 0)
            }
            calendarLines.append("- Meeting in 5-10 min → stop music, good lighting, suppress voice. " +
                "Don't mention event titles in reasons — say \"your next event\" instead.")
            sections.append("## Upcoming Schedule\n" + calendarLines.joined(separator: "\n"))
        }

        // Focus mode
        if let focus = context.focusMode {
            sections.append("## Focus Mode\n- Active: \(sanitizeForPrompt(focus)) — this is the user's strongest signal. " +
                "Reduce all disruptions: no voice, no vacuum, no non-essential changes.")
        }

        // Occupancy sensors
        if let occupied = context.occupiedRooms, !occupied.isEmpty {
            var occupiedLines = occupied.map { "- \(sanitizeForPrompt($0))" }
            occupiedLines.append("- Occupancy = sustained presence (more reliable than motion for stationary people)")
            sections.append("## Occupied Rooms\n" + occupiedLines.joined(separator: "\n"))
        }

        // Contact sensors
        if let openContacts = context.openContacts, !openContacts.isEmpty {
            var contactLines = openContacts.map { "- \(sanitizeForPrompt($0))" }
            contactLines.append("- Open exterior doors at night = safety concern. Open windows affect thermostat efficiency.")
            sections.append("## Open Doors/Windows\n" + contactLines.joined(separator: "\n"))
        }

        // Energy
        if let totalPower = context.totalPowerWatts {
            var energyLines = ["- Total consumption: \(Int(totalPower))W"]
            if let highPower = context.highPowerDevices, !highPower.isEmpty {
                energyLines.append(contentsOf: highPower.map { "- \(sanitizeForPrompt($0))" })
            }
            energyLines.append("- Device dropping to 0W may have finished its cycle (mention via voice). " +
                "Flag high-power devices left running when user is away.")
            sections.append("## Energy\n" + energyLines.joined(separator: "\n"))
        }

        // Mac state
        var macLines: [String] = []
        if let displayOn = context.macDisplayOn {
            macLines.append("- Display: \(displayOn ? "on" : "off/asleep")")
        }
        if let idle = context.macIsIdle, idle {
            macLines.append("- Mac idle for 5+ minutes")
        }
        if let activity = context.macInferredActivity {
            macLines.append("- Activity: \(sanitizeForPrompt(activity))")
        }
        if let camera = context.macCameraInUse, camera {
            macLines.append("- CAMERA IN USE — suppress ALL voice and stop music, ensure good lighting")
        }
        if let app = context.macFrontmostApp, context.macInferredActivity == nil {
            macLines.append("- Frontmost app: \(sanitizeForPrompt(app))")
        }
        if !macLines.isEmpty {
            macLines.append("- Watching media → dim lights, theater ambiance. " +
                "Coding/writing → good task lighting. Idle 5+ min → user likely stepped away.")
            sections.append("## Mac State\n" + macLines.joined(separator: "\n"))
        }

        // Active overrides
        if let activeOverrides {
            sections.append(activeOverrides +
                "\nDo NOT change any characteristic listed above — the user set it manually. " +
                "This applies per-characteristic only: if brightness is overridden, " +
                "you can still change hue or color temperature on the same device. " +
                "Only an explicit user request overrides a locked characteristic.")
        }

        // Automation-specific behavioral rules (proactive loop only)
        if automationGuidance {
            sections.append("""
            ## Automation Rules
            Voice: Only speak when it adds value — most cycles should be SILENT. \
            Good reasons: welcome home, goodnight, door left open, unusual situation. \
            Never speak when asleep or during focus/workout/call. \
            Route: "airpods" for private (through connected AirPods), "auto" to let the system decide. \
            Set expectsReply=true only when asking a yes/no question. \
            Tone: warm, one sentence, like a thoughtful roommate.
            Music: Think like a DJ — let good music play, transition smoothly, don't interrupt mid-song. \
            Most cycles should leave music unchanged (nil). \
            To keep the current vibe, use the SAME query — the system will let it continue without interruption. \
            To transition, use a DIFFERENT query — the system will queue it after the current track and crossfade. \
            Start for: arrival, evening transition, workout. Stop for: sleep, leaving, call. \
            Use mood queries ("calm acoustic evening", "focus lo-fi beats", "jazz dinner party"). \
            Volume: 0.1–0.2 sleep, 0.2–0.3 background, 0.4–0.5 active, 0.6+ workout. \
            Neutral/crowd-friendly music when guests present.
            Devices: Vacuums — run when away, stop on return, never during sleep/workout/call/guests. \
            Purifiers — activate when air quality may be poor (cooking, high pollen), fine to leave running. \
            Prefer gradual adjustments over abrupt changes.
            Departure (user away + house empty): lights off, thermostat setback (15°C winter / 28°C summer), \
            stop music, note appliances left running via voice. Do NOT lock doors or open garage doors.
            Lighting: Follow circadian rhythm — cool/bright morning, warm/dim evening. \
            Use sunrise/sunset times to time transitions.
            """)
        }

        // Devices
        let deviceLines = context.devices
            .filter { $0.isReachable && !$0.characteristics.isEmpty }
            .map(\.promptDescription)
        if deviceLines.isEmpty {
            sections.append("## Devices\nNo reachable devices.")
        } else {
            sections.append("## Devices\nEach device is listed as [accessoryID] Name — characteristic=value. Use the accessoryID from square brackets and only the exact characteristic names shown (e.g. 'on', 'brightness') when creating actions.\n" + deviceLines.joined(separator: "\n"))
        }

        // Learned preferences
        if let preferenceHistory {
            sections.append(preferenceHistory +
                "\nApply patterns silently — don't mention learning in reasons. " +
                "Weight recent overrides above older ones. Context matters: " +
                "a weekday evening correction may not apply to weekend mornings.")
        }

        return sections.joined(separator: "\n\n")
    }

    static func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func timeOnly(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayName(_ day: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard day >= 1, day < names.count else { return "Unknown" }
        return names[day]
    }
}
