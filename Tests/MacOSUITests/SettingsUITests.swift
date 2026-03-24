import XCTest

@MainActor
final class SettingsUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--skipOnboarding", "--showSettings"]
        app.launch()
    }

    private func element(id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    // MARK: - Automation Section

    func testAutomationIntervalPickerExists() {
        let el = element(id: "settings.automation.interval")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    // MARK: - Preferences Section

    func testPreferencesShowOverridesCount() {
        let el = element(id: "settings.preferences.overridesCount")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    func testResetPreferencesButtonExists() {
        let el = element(id: "settings.preferences.resetButton")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    // MARK: - Guest Detection Section

    func testApartmentModeToggleExists() {
        let el = element(id: "settings.guestDetection.apartmentMode")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    func testLearnNetworkButtonExists() {
        let el = element(id: "settings.guestDetection.learnNetworkButton")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    // MARK: - Voice Section

    func testVoiceMaxPerHourExists() {
        let el = element(id: "settings.voice.maxPerHourLabel")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    func testQuietHoursToggleExists() {
        let el = element(id: "settings.voice.quietHoursToggle")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    // MARK: - Notifications

    func testNotificationsToggleExists() {
        scrollDown()
        let el = element(id: "settings.notifications.enableToggle")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    // MARK: - Companion

    func testCompanionToggleExists() {
        scrollDown()
        let el = element(id: "settings.companion.enableToggle")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    // MARK: - About

    func testAboutShowsVersion() {
        scrollDown()
        scrollDown()
        let el = element(id: "settings.about.version")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    func testAboutShowsEngine() {
        scrollDown()
        scrollDown()
        scrollDown()
        let el = element(id: "settings.about.engine")
        XCTAssertTrue(el.waitForExistence(timeout: 5))
    }

    private func scrollDown() {
        // Mac Catalyst Form renders as UITableView. Try tables first, then
        // other scrollable containers. Use sleep to let Catalyst settle between
        // swipe gestures.
        if let table = [app.tables.firstMatch, app.scrollViews.firstMatch, app.otherElements.firstMatch].first(where: { $0.exists }) {
            table.swipeUp()
        } else {
            app.swipeUp()
        }
        sleep(1)
    }
}
