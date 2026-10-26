import XCTest

final class ExposureAssistantUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset"]
        app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func setSwitch(_ element: XCUIElement, on: Bool) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let desired = on ? "1" : "0"
        if element.value as? String != desired {
            // SwiftUI Form exposes the whole labeled row; hit the actual trailing switch.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(element.value as? String, desired)
    }
    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
        if app.buttons["完成"].exists { app.buttons["完成"].tap() }
    }
    func testExampleAndInvalidInput() {
        XCTAssertTrue(app.textFields["reference_aperture"].waitForExistence(timeout: 5))
        app.buttons["load_example"].tap()
        let result = app.staticTexts["exact_result"]
        reveal(result)
        XCTAssertEqual(result.label, "32 秒")
        for _ in 0..<8 { app.swipeDown() }
        replace(app.textFields["reference_aperture"], with: "0")
        let error = app.staticTexts["input_error"]
        reveal(error)
        XCTAssertTrue(error.exists)
        XCTAssertFalse(app.staticTexts["exact_result"].exists)
    }
    func testSettingsPersistAndSeparateAstroForm() {
        app.buttons["load_example"].tap()
        app.buttons["settings"].tap()
        setSwitch(app.switches["red_toggle"], on: true)
        app.buttons["settings_done"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertEqual(app.textFields["reference_aperture"].value as? String, "2")
        app.buttons["settings"].tap()
        XCTAssertEqual(app.switches["red_toggle"].value as? String, "1")
        app.buttons["settings_done"].tap()
        app.segmentedControls["page_picker"].buttons["星空攝影"].tap()
        XCTAssertTrue(app.buttons["stars_dismiss"].waitForExistence(timeout: 3))
        app.buttons["stars_dismiss"].tap()
        XCTAssertNotEqual(app.textFields["reference_aperture"].value as? String, "2")
        app.segmentedControls["page_picker"].buttons["曝光換算"].tap()
        XCTAssertEqual(app.textFields["reference_aperture"].value as? String, "2")
    }
    func testForegroundTimerCancelAndComplete() {
        app.buttons["load_example"].tap()
        reveal(app.buttons["open_timer"])
        app.buttons["open_timer"].tap()
        setSwitch(app.switches["background_toggle"], on: false)
        replace(app.textFields["timer_seconds"], with: "2")
        app.buttons["timer_start"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 6))
        app.alerts.buttons["好"].tap()
        for _ in 0..<8 { app.swipeDown() }
        app.buttons["cancel_timer"].tap()
        reveal(app.buttons["open_timer"])
        app.buttons["open_timer"].tap()
        replace(app.textFields["timer_seconds"], with: "60")
        app.buttons["timer_start"].tap()
        for _ in 0..<8 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["countdown"].exists)
        app.buttons["cancel_timer"].tap()
        XCTAssertFalse(app.staticTexts["countdown"].exists)
    }
    func testFilmModeAndRotation() {
        app.buttons["load_example"].tap()
        reveal(app.switches["film_toggle"])
        setSwitch(app.switches["film_toggle"], on: true)
        reveal(app.staticTexts["corrected_result"])
        XCTAssertTrue(app.staticTexts["corrected_result"].label.contains("HP5 Plus"))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["corrected_result"].exists)
        XCUIDevice.shared.orientation = .portrait
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iOS exposure film result"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
