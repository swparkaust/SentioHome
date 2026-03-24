import XCTest

@MainActor
final class CompanionSnapshotTests: XCTestCase {

    let app = XCUIApplication()

    private func saveSnapshot(_ name: String) {
        app.activate()
        sleep(2)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Companion Home

    func testSnapshotCompanionHome() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        // Dismiss system permission dialogs
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Don't Allow", "Allow While Using App"] {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 2) { btn.tap() }
        }

        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10))
        saveSnapshot("iOS_01_CompanionHome")
    }

    func testSnapshotCompanionHomeScrolled() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Don't Allow", "Allow While Using App"] {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 2) { btn.tap() }
        }

        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10))

        app.swipeUp()
        sleep(1)
        saveSnapshot("iOS_02_CompanionHome_Scrolled")
    }

    // MARK: - Remote Chat

    func testSnapshotRemoteChatEmpty() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Don't Allow", "Allow While Using App"] {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 2) { btn.tap() }
        }

        let chatLink = app.buttons["companionHome.toolbar.remoteChatLink"]
        XCTAssertTrue(chatLink.waitForExistence(timeout: 10), "Chat toolbar button should exist")
        chatLink.tap()

        let input = app.textFields["remoteChat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Chat input field should exist")
        saveSnapshot("iOS_03_RemoteChat_Empty")
    }

    func testSnapshotRemoteChatWithInput() {
        app.launchArguments = ["--uitesting", "--skipOnboarding"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Don't Allow", "Allow While Using App"] {
            let btn = springboard.buttons[label]
            if btn.waitForExistence(timeout: 2) { btn.tap() }
        }

        let chatLink = app.buttons["companionHome.toolbar.remoteChatLink"]
        XCTAssertTrue(chatLink.waitForExistence(timeout: 10), "Chat toolbar button should exist")
        chatLink.tap()

        let input = app.textFields["remoteChat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Chat input field should exist")
        input.tap()
        input.typeText("What's the temperature inside?")
        saveSnapshot("iOS_04_RemoteChat_WithInput")
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
            ("iOS_05_Onboarding_Welcome", "onboarding.step.welcome"),
            ("iOS_06_Onboarding_Role", "onboarding.step.role"),
            ("iOS_07_Onboarding_Location", "onboarding.step.location"),
            ("iOS_08_Onboarding_Sensors", "onboarding.step.sensors"),
            ("iOS_09_Onboarding_Voice", "onboarding.step.voice"),
            ("iOS_10_Onboarding_Siri", "onboarding.step.siri"),
        ]

        for (snapshotName, stepID) in steps {
            let step = app.descendants(matching: .any)
                .matching(identifier: stepID).firstMatch
            XCTAssertTrue(step.waitForExistence(timeout: 5), "\(stepID) should be visible")
            saveSnapshot(snapshotName)
            continueBtn.tap()
            sleep(1)
            _ = continueBtn.waitForExistence(timeout: 5)
        }

        // Final "Ready" step with Get Started button
        let getStarted = app.buttons["onboarding.getStartedButton"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        saveSnapshot("iOS_11_Onboarding_Ready")
    }
}
