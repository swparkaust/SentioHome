import XCTest

@MainActor
final class RemoteChatUITests: XCTestCase {

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

        // Navigate to chat
        let navBar = app.navigationBars.firstMatch
        if navBar.waitForExistence(timeout: 10) {
            let chatBtn = app.navigationBars.buttons.element(boundBy: 0)
            if chatBtn.waitForExistence(timeout: 3) { chatBtn.tap() }
        }
    }

    // MARK: - Chat Screen

    func testChatScreenExists() {
        let textField = app.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
    }

    func testCanTypeInTextField() {
        let textField = app.textFields.firstMatch
        guard textField.waitForExistence(timeout: 5) else {
            XCTFail("Text field not found")
            return
        }
        textField.tap()
        textField.typeText("Hello Sentio")
        XCTAssertEqual(textField.value as? String, "Hello Sentio")
    }
}
