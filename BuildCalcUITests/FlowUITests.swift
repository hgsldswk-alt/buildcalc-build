import XCTest

final class FlowUITests: XCTestCase {
    private let floor: [String: String] = ["LENGTH": "4", "WIDTH": "3", "COVERAGE": "2.20"]

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(language: String = "zh-Hans", flags: [String] = ["-reset"], fields: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language == "zh-Hant" ? "zh_TW" : "zh_CN"] + flags
        app.launchEnvironment = ["BUILDCALC_SYSTEM": "metric"]
        for (key, value) in fields { app.launchEnvironment["BUILDCALC_" + key] = value }
        app.launch()
        return app
    }

    private func calculate(_ app: XCUIApplication) {
        let button = app.buttons["home.calculate"]
        XCTAssertTrue(button.waitForExistence(timeout: 6))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 6), .completed)
        button.tap()
    }

    private func verify(_ app: XCUIApplication, quantity: String) {
        let result = app.staticTexts["result.quantity"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.hasPrefix(quantity + " "), result.label)
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCalculateAndShareThenInvalidateWithKeyboardUp() {
        let app = launch(fields: floor)
        calculate(app)
        verify(app, quantity: "6")
        app.buttons["result.share"].tap()
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["完成", "Done", "完成 ", "關閉", "关闭", "Close", "取消", "Cancel"])).firstMatch
        if close.waitForExistence(timeout: 4) { close.tap() }
        else { app.swipeDown() }
        let scroll = app.scrollViews.firstMatch
        scroll.swipeDown()
        let coverage = app.textFields["field.coverage"]
        let deadline = Date().addingTimeInterval(8)
        while !coverage.isHittable && Date() < deadline { usleep(300_000) }
        coverage.tap()
        coverage.typeText("1")
        XCTAssertFalse(app.buttons["result.share"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        calculate(app)
        verify(app, quantity: "6")
    }

    func testInitialInputMissingAndReuseDimensions() {
        let app = launch()
        let length = app.textFields["field.length"]
        XCTAssertTrue(length.waitForExistence(timeout: 6))
        length.tap()
        length.typeText("4")
        let width = app.textFields["field.width"]
        width.tap()
        width.typeText("3")
        calculate(app)
        XCTAssertTrue(app.staticTexts["error.coverage"].waitForExistence(timeout: 4))
        let coverage = app.textFields["field.coverage"]
        let deadline = Date().addingTimeInterval(8)
        while !coverage.isHittable && Date() < deadline { usleep(300_000) }
        coverage.tap()
        coverage.typeText("2.20")
        calculate(app)
        verify(app, quantity: "6")
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["mode.panel"].tap()
        XCTAssertEqual(app.textFields["field.length"].value as? String, "4")
        XCTAssertEqual(app.textFields["field.width"].value as? String, "3")
        XCTAssertEqual(app.textFields["field.waste"].value as? String, "10")
        calculate(app)
        XCTAssertTrue(app.staticTexts["error.coverage"].waitForExistence(timeout: 4))
    }

    func testUnitToggleAndLiveConversion() {
        let app = launch(fields: floor.merging(["CONVERSION": "12′ 7 1/2″"], uniquingKeysWith: { _, new in new }))
        app.buttons["unit.imperial"].tap()
        app.buttons["unit.metric"].tap()
        XCTAssertEqual(app.textFields["field.coverage"].value as? String, "2.20")
        calculate(app)
        verify(app, quantity: "6")
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["mode.convert"].tap()
        XCTAssertTrue(app.staticTexts["conversion.metric"].label.contains("3.8481"))
        XCTAssertTrue(app.staticTexts["conversion.area"].label.contains("12.00"))
    }

    func testExpiredHistoryAndImportStayAvailable() {
        let app = launch(fields: floor)
        calculate(app)
        verify(app, quantity: "6")
        app.buttons["home.recent"].tap()
        XCTAssertTrue(app.buttons["history.record"].firstMatch.waitForExistence(timeout: 6))
        app.terminate()
        let expired = launch(flags: ["-expired"])
        calculate(expired)
        XCTAssertTrue(expired.staticTexts["paywall.title"].waitForExistence(timeout: 6))
        expired.buttons["paywall.done"].tap()
        expired.buttons["home.recent"].tap()
        expired.buttons["history.record"].firstMatch.tap()
        verify(expired, quantity: "6")
        XCTAssertFalse(expired.buttons["history.recalculate"].exists)
        let detail = expired.scrollViews.firstMatch
        detail.swipeUp()
        XCTAssertTrue(expired.buttons["history.share"].exists)
        expired.buttons["history.share"].tap()
        XCTAssertFalse(expired.staticTexts["paywall.title"].exists)
        expired.terminate()

        let transfer = launch(flags: ["-expired"], fields: ["IMPORT": fixtureCode() + "\n"])
        transfer.buttons["home.import"].tap()
        transfer.buttons["import.open"].tap()
        verify(transfer, quantity: "6")
        XCTAssertFalse(transfer.buttons["history.recalculate"].exists)
        transfer.terminate()
        let duplicate = launch(flags: ["-expired"], fields: ["IMPORT": fixtureCode()])
        duplicate.buttons["home.import"].tap()
        duplicate.buttons["import.open"].tap()
        verify(duplicate, quantity: "6")
        duplicate.terminate()
        let history = launch(flags: ["-expired"])
        history.buttons["home.recent"].tap()
        XCTAssertTrue(history.buttons["history.record"].firstMatch.waitForExistence(timeout: 6))
        XCTAssertEqual(history.buttons.matching(identifier: "history.record").count, 2)
    }

    func testInvalidCodeLeavesImportOpen() {
        let app = launch(fields: ["IMPORT": "MAT1:bad\ncode"])
        app.buttons["home.import"].tap()
        app.buttons["import.open"].tap()
        XCTAssertTrue(app.staticTexts["import.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["result.quantity"].exists)
    }

    func testPaintVolumeSwitchDoesNotChangeStoredInputs() {
        let app = launch(fields: ["MODE": "paint", "MATERIAL": "paint", "LENGTH": "4", "WIDTH": "3", "COVERAGE": "10", "CAPACITY": "2.5"])
        let metric = app.buttons["unit.metric"]
        XCTAssertTrue(metric.waitForExistence(timeout: 6))
        app.buttons["unit.imperial"].tap()
        XCTAssertNotEqual(app.textFields["field.capacity"].value as? String, "2.5")
        metric.tap()
        XCTAssertEqual(app.textFields["field.capacity"].value as? String, "2.5")
        XCTAssertEqual(app.textFields["field.coverage"].value as? String, "10")
        calculate(app)
        verify(app, quantity: "2")
    }

    func testPurchasedAndLargeText() {
        let app = launch(flags: ["-reset", "-expired", "-purchased", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"], fields: floor)
        calculate(app)
        verify(app, quantity: "6")
        XCTAssertTrue(app.buttons["result.share"].exists)
    }

    func testStoreEnglish() { storeShots("en") }
    func testStoreSimplifiedChinese() { storeShots("zh-Hans") }
    func testStoreTraditionalChinese() { storeShots("zh-Hant") }

    private func storeShots(_ language: String) {
        let prefix = "store-" + language + "-"
        let app = launch(language: language)
        XCTAssertTrue(app.textFields["field.length"].waitForExistence(timeout: 6))
        screenshot(app, prefix + "01-home")
        app.terminate()

        let estimate = launch(language: language, flags: ["-reset", "-share-shot"], fields: floor)
        calculate(estimate)
        verify(estimate, quantity: "6")
        screenshot(estimate, prefix + "02-floor")
        estimate.buttons["result.share"].tap()
        XCTAssertTrue(estimate.images["share.previewCard"].waitForExistence(timeout: 6))
        screenshot(estimate, prefix + "05-share")
        estimate.terminate()

        let convert = launch(language: language, fields: ["MODE": "conversion", "CONVERSION": "12′ 7 1/2″", "LENGTH": "4", "WIDTH": "3"])
        XCTAssertTrue(convert.staticTexts["conversion.metric"].waitForExistence(timeout: 6))
        screenshot(convert, prefix + "03-convert")
        convert.terminate()

        let paint = launch(language: language, fields: ["MODE": "paint", "MATERIAL": "paint", "LENGTH": "4", "WIDTH": "3", "COVERAGE": "10", "CAPACITY": "2.5"])
        XCTAssertTrue(paint.textFields["field.coats"].waitForExistence(timeout: 6))
        screenshot(paint, prefix + "04-paint")
        calculate(paint)
        verify(paint, quantity: "2")
    }

    func testPaidScreenshot() {
        let app = launch(flags: ["-reset", "-paywall", "-paid-mode"])
        XCTAssertTrue(app.buttons["paywall.restore"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["paywall.buy"].exists)
        XCTAssertTrue(app.buttons["paywall.trial"].exists)
        screenshot(app, "paid-01-paywall")
    }

    private func fixtureCode() -> String {
        let source = #"{"formulaVersion":1,"input":{"coverage":{"system":"metric","text":"2.20","volume":"liter"},"length":{"system":"metric","text":"4","volume":"liter"},"material":"floor","waste":{"system":"metric","text":"8","volume":"liter"},"width":{"system":"metric","text":"3","volume":"liter"}},"version":1}"#
        return "MAT1:" + Data(source.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
