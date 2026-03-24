import XCTest

@MainActor
final class CompanionHomeUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        // Dismiss any system permission dialogs
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Don't Allow", "Allow While Using App"] {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 2) { btn.tap() }
        }
    }

    // MARK: - Home Screen Structure

    func testHomeScreenLaunches() {
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10))
    }

    func testToolbarHasButtons() {
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10))
        let buttons = app.navigationBars.buttons
        XCTAssertTrue(buttons.count > 0)
    }

    func testScrollableContent() {
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10))
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists)
    }
}
