import XCTest

@MainActor
final class MacOnboardingUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--showOnboarding"]
        app.launch()
    }

    private func element(id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    // MARK: - Onboarding Structure

    func testOnboardingShowsWelcome() {
        let welcome = element(id: "onboarding.step.welcome")
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))
        // In Mac Catalyst, the parent's accessibilityIdentifier propagates to
        // all children, so stepView.title/description are overridden by the
        // step identifier. Verify content via the title text label instead.
        XCTAssertTrue(app.staticTexts["Welcome to Sentio"].exists)
    }

    func testProgressIndicatorExists() {
        let progress = element(id: "onboarding.progressIndicator")
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
    }

    func testContinueButtonExists() {
        let btn = app.buttons["onboarding.continueButton"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    func testBackButtonHiddenOnFirstStep() {
        let welcome = element(id: "onboarding.step.welcome")
        guard welcome.waitForExistence(timeout: 5) else {
            XCTFail("Welcome step not found")
            return
        }
        XCTAssertFalse(app.buttons["onboarding.backButton"].exists)
    }

    func testFullMacOnboardingFlow() {
        let continueBtn = app.buttons["onboarding.continueButton"]
        guard continueBtn.waitForExistence(timeout: 5) else {
            XCTFail("Continue button not found")
            return
        }

        let steps = [
            "onboarding.step.welcome",
            "onboarding.step.architecture",
            "onboarding.step.homeKit",
            "onboarding.step.calendarMusic",
            "onboarding.step.notifications",
            "onboarding.step.networkBluetooth"
        ]

        for step in steps {
            let stepElement = element(id: step)
            XCTAssertTrue(stepElement.waitForExistence(timeout: 5), "Step \(step) should be visible")
            continueBtn.click()
            sleep(1) // Mac Catalyst needs time to animate step transition
            _ = continueBtn.waitForExistence(timeout: 5)
        }

        let getStarted = app.buttons["onboarding.getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        XCTAssertTrue(element(id: "onboarding.step.ready").waitForExistence(timeout: 3))
    }

    func testBackButtonNavigatesBack() {
        let continueBtn = app.buttons["onboarding.continueButton"]
        guard continueBtn.waitForExistence(timeout: 5) else {
            XCTFail("Continue button not found")
            return
        }

        // Advance to step 1 (architecture)
        continueBtn.click()
        sleep(1)
        let architectureStep = element(id: "onboarding.step.architecture")
        XCTAssertTrue(architectureStep.waitForExistence(timeout: 5), "Architecture step should appear after tapping continue")

        // Go back to step 0 (welcome)
        let backBtn = app.buttons["onboarding.backButton"]
        XCTAssertTrue(backBtn.waitForExistence(timeout: 5))
        backBtn.click()
        sleep(1)

        let welcomeStep = element(id: "onboarding.step.welcome")
        XCTAssertTrue(welcomeStep.waitForExistence(timeout: 5), "Welcome step should reappear after tapping back")
    }
}
