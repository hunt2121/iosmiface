// SPDX-License-Identifier: MIT
// Прохід екранами BandFace зі знімками (для перевірки вигляду в CI): магазин із превʼю з ресурсів,
// сторінка циферблата, копія в редакторі, встановлення з редактора, вкладка «Редактор»; те саме англійською.
import XCTest

final class BandFaceUITests: XCTestCase {
    var dir: URL!
    var n = 0

    override func setUp() {
        continueAfterFailure = true
        dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOTS"] ?? NSTemporaryDirectory()).appendingPathComponent("bandface")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func shot(_ name: String) {
        n += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent(String(format: "%02d-%@.png", n, name)))
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png"); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// Системні запити (Bluetooth тощо) закриваємо, щоб не заважали
    func closeSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { return }
            for title in ["Allow", "OK", "Дозволити", "Гаразд", "Разрешить"] where alert.buttons[title].exists {
                alert.buttons[title].tap(); break
            }
        }
    }

    func launch(_ lang: String, _ locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
        app.launch()
        closeSystemAlerts()
        return app
    }

    func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testStoreAndEditorUkrainian() {
        let app = launch("uk", "uk_UA")
        sleep(2); shot("faces")
        app.tabBars.buttons["Магазин"].tap()
        sleep(4); shot("store")
        app.staticTexts["BigWatch"].firstMatch.tap()
        sleep(2); shot("store-detail")
        app.swipeUp()
        sleep(1); shot("store-detail-bottom")
        let edit = button(app, containing: "Змінити в редакторі")
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        sleep(3); shot("editor-copy")
        // кроки: x=106 (середина), y≈474 з 520
        let canvas = app.descendants(matching: .any)["canvas"].firstMatch
        if canvas.waitForExistence(timeout: 3) {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 470.0 / 520.0)).tap()
            sleep(1); shot("steps-selected")
        }
        let done = app.buttons["Готово"].firstMatch
        done.press(forDuration: 1.2)
        sleep(1); shot("done-menu")
        let install = app.buttons["Встановити на пристрій"].firstMatch
        if install.waitForExistence(timeout: 2) {
            install.tap()
            sleep(2); shot("install-from-editor")
            if app.alerts.firstMatch.waitForExistence(timeout: 2) { app.alerts.firstMatch.buttons.firstMatch.tap() }
            sleep(1)
            app.tabBars.buttons["Циферблати"].tap()
            sleep(2); shot("faces-with-editor-face")
        }
        app.tabBars.buttons["Редактор"].tap()
        sleep(2); shot("editor-tab")
    }

    func testEditorEnglish() {
        let app = launch("en", "en_US")
        app.tabBars.buttons["Editor"].tap()
        sleep(1); shot("en-editor-empty")
        app.buttons["New watch face"].firstMatch.tap()
        sleep(1)
        app.buttons["Create"].tap()
        sleep(2); shot("en-editor")
        let canvas = app.descendants(matching: .any)["canvas"].firstMatch
        if canvas.waitForExistence(timeout: 3) {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 120.0 / 520.0)).tap()
            sleep(1); shot("en-selected")
        }
        app.buttons["Element"].firstMatch.tap()
        sleep(1); shot("en-add-element")
        app.buttons["Arc"].firstMatch.tap()
        sleep(1); shot("en-data-source")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 2) { search.tap(); search.typeText("Battery") }
        sleep(1)
        app.buttons["Battery"].firstMatch.tap()
        sleep(2); shot("en-arc-added")
        app.buttons["Close"].firstMatch.tap()
        sleep(1)
        if app.buttons["Save and close"].waitForExistence(timeout: 2) { app.buttons["Save and close"].tap() }
        sleep(2); shot("en-editor-list")
    }
}
