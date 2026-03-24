import XCTest

@MainActor
final class WatchSnapshotTests: XCTestCase {

    let app = XCUIApplication()

    private func saveSnapshot(_ name: String) {
        sleep(3)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Watch Home

    func testSnapshotWatchHome() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        let askButton = app.buttons["Ask Sentio"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 10), "Home screen should show Ask Sentio button")
        saveSnapshot("Watch_01_Home")
    }

    func testSnapshotWatchHomeScrolled() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        let askButton = app.buttons["Ask Sentio"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 10), "Home screen should show Ask Sentio button")

        app.swipeUp()
        sleep(1)
        saveSnapshot("Watch_02_Home_Scrolled")
    }

    // MARK: - Ask Sentio

    func testSnapshotAskSentio() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        let askButton = app.buttons["Ask Sentio"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 10), "Home screen should show Ask Sentio button")
        askButton.tap()

        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Ask screen should show text input")
        saveSnapshot("Watch_03_AskSentio")
    }

    // MARK: - Onboarding

    func testSnapshotOnboardingWelcome() {
        app.launchArguments = ["--uitesting", "--showOnboarding", "--onboardingStep", "0"]
        app.launch()

        let title = app.staticTexts["Sentio Watch"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Welcome step should show 'Sentio Watch' title")
        saveSnapshot("Watch_04_Onboarding_Welcome")
    }

    func testSnapshotOnboardingHealth() {
        app.launchArguments = ["--uitesting", "--showOnboarding", "--onboardingStep", "1"]
        app.launch()

        let healthTitle = app.staticTexts["Health & Location"]
        XCTAssertTrue(healthTitle.waitForExistence(timeout: 10), "Health step should show 'Health & Location' title")
        saveSnapshot("Watch_05_Onboarding_Health")
    }

    func testSnapshotOnboardingReady() {
        app.launchArguments = ["--uitesting", "--showOnboarding", "--onboardingStep", "2"]
        app.launch()

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10), "Ready step should show 'Get Started' button")
        saveSnapshot("Watch_06_Onboarding_Ready")
    }
}
