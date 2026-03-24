import XCTest

@MainActor
final class CompanionOnboardingUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--showOnboarding"]
        app.launch()
    }

    // MARK: - Onboarding Flow

    func testOnboardingShowsContinueButton() {
        let continueBtn = app.buttons["onboarding.continueButton"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5))
    }

    func testContinueButtonAdvancesStep() {
        let continueBtn = app.buttons["onboarding.continueButton"]
        guard continueBtn.waitForExistence(timeout: 5) else {
            XCTFail("Continue button not found")
            return
        }
        continueBtn.tap()

        // Back button should now appear (not visible on first step)
        let backBtn = app.buttons["onboarding.backButton"]
        XCTAssertTrue(backBtn.waitForExistence(timeout: 3))
    }

    func testBackButtonGoesToPreviousStep() {
        let continueBtn = app.buttons["onboarding.continueButton"]
        guard continueBtn.waitForExistence(timeout: 5) else { return }

        // Advance one step
        continueBtn.tap()

        let backBtn = app.buttons["onboarding.backButton"]
        guard backBtn.waitForExistence(timeout: 3) else {
            XCTFail("Back button not found")
            return
        }
        backBtn.tap()

        // Back button should disappear (first step)
        XCTAssertFalse(backBtn.waitForExistence(timeout: 2))
    }

    func testFullOnboardingReachesGetStarted() {
        let continueBtn = app.buttons["onboarding.continueButton"]
        guard continueBtn.waitForExistence(timeout: 5) else {
            XCTFail("Continue button not found")
            return
        }

        // Tap continue through all steps (7 steps, need 6 taps to reach final)
        for _ in 0..<6 {
            if continueBtn.exists {
                continueBtn.tap()
                // Brief wait for animation
                _ = continueBtn.waitForExistence(timeout: 1)
            }
        }

        let getStarted = app.buttons["onboarding.getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 3))
    }
}
