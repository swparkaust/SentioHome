import XCTest

@MainActor
final class SnapshotTests: XCTestCase {

    let app = XCUIApplication()
    static let outputDir = "/tmp/SentioSnapshots"

    override class func setUp() {
        super.setUp()
        // Create output directory once before all tests
        try? FileManager.default.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true
        )
    }

    private func saveSnapshot(_ name: String) {
        app.activate() // Ensure the app window is frontmost
        sleep(2) // Let UI settle after activation
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 5) else {
            XCTFail("No window found for snapshot \(name)")
            return
        }
        let screenshot = window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Menu Bar Main View

    func testSnapshotMenuBarDefault() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()
        let status = app.staticTexts["menuBar.header.statusText"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        saveSnapshot("01_MenuBar_Default")
    }

    func testSnapshotMenuBarWithTypedQuery() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()
        let input = app.textFields["menuBar.quickAsk.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        sleep(1)
        input.typeText("Turn on the living room lights")
        saveSnapshot("02_MenuBar_WithQuery")
    }

    // MARK: - Settings View

    func testSnapshotSettingsTop() {
        app.launchArguments = ["--uitesting", "--skipOnboarding", "--showSettings"]
        app.launch()
        let el = app.descendants(matching: .any)
            .matching(identifier: "settings.automation.interval").firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 5))
        saveSnapshot("03_Settings_Top")
    }

    func testSnapshotSettingsMiddle() {
        app.launchArguments = ["--uitesting", "--skipOnboarding", "--showSettings"]
        app.launch()
        let el = app.descendants(matching: .any)
            .matching(identifier: "settings.automation.interval").firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 5))
        scrollDown()
        saveSnapshot("04_Settings_Middle")
    }

    func testSnapshotSettingsBottom() {
        app.launchArguments = ["--uitesting", "--skipOnboarding", "--showSettings"]
        app.launch()
        let el = app.descendants(matching: .any)
            .matching(identifier: "settings.automation.interval").firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 5))
        scrollDown()
        scrollDown()
        scrollDown()
        saveSnapshot("05_Settings_Bottom")
    }

    // MARK: - Onboarding Flow

    func testSnapshotOnboardingAllSteps() {
        app.launchArguments = ["--uitesting", "--showOnboarding"]
        app.launch()

        let continueBtn = app.buttons["onboarding.continueButton"]
        guard continueBtn.waitForExistence(timeout: 5) else {
            XCTFail("Continue button not found")
            return
        }

        let steps = [
            ("06_Onboarding_Welcome", "onboarding.step.welcome"),
            ("07_Onboarding_Architecture", "onboarding.step.architecture"),
            ("08_Onboarding_HomeKit", "onboarding.step.homeKit"),
            ("09_Onboarding_CalendarMusic", "onboarding.step.calendarMusic"),
            ("10_Onboarding_Notifications", "onboarding.step.notifications"),
            ("11_Onboarding_NetworkBluetooth", "onboarding.step.networkBluetooth")
        ]

        for (snapshotName, stepID) in steps {
            let step = app.descendants(matching: .any)
                .matching(identifier: stepID).firstMatch
            XCTAssertTrue(step.waitForExistence(timeout: 5), "\(stepID) should be visible")
            saveSnapshot(snapshotName)
            continueBtn.click()
            sleep(1)
            _ = continueBtn.waitForExistence(timeout: 5)
        }

        // Final "Ready" step with Get Started button
        let getStarted = app.buttons["onboarding.getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        saveSnapshot("12_Onboarding_Ready")
    }

    // MARK: - Helpers

    private func scrollDown() {
        if let table = [app.tables.firstMatch, app.scrollViews.firstMatch,
                        app.otherElements.firstMatch].first(where: { $0.exists }) {
            table.swipeUp()
        } else {
            app.swipeUp()
        }
        sleep(1)
    }
}
