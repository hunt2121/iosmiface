// SPDX-License-Identifier: MIT
// Прохід екранами редактора зі знімками (для перевірки вигляду в CI).
import XCTest

final class FaceEditorUITests: XCTestCase {
    var dir: URL!
    var n = 0

    override func setUp() {
        continueAfterFailure = true
        dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOTS"] ?? NSTemporaryDirectory()).appendingPathComponent("shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func shot(_ name: String) {
        n += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent(String(format: "%02d-%@.png", n, name)))
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png"); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testWalkthrough() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        sleep(1); shot("empty")
        app.buttons["Новий циферблат"].firstMatch.tap()
        sleep(1); shot("new-sheet")
        app.buttons["Створити"].tap()
        sleep(2); shot("editor")
        // перший шар — години по центру зверху
        // години: центр по горизонталі, y≈120 з 520
        let canvas = app.descendants(matching: .any)["canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 120.0 / 520.0)).tap()
        sleep(1); shot("selected-look")
        app.buttons["Колір"].firstMatch.tap(); sleep(1); shot("selected-color")
        app.buttons["Позиція"].firstMatch.tap(); sleep(1); shot("selected-position")
        app.buttons["Елемент"].firstMatch.tap()
        sleep(1); shot("add-element")
        app.buttons["Дуга"].firstMatch.tap()
        sleep(1); shot("data-source")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 2) { search.tap(); search.typeText("Батарея") }
        sleep(1); shot("data-source-search")
        app.buttons["Батарея"].firstMatch.tap()
        sleep(2); shot("arc-added")
        app.buttons["Шари"].firstMatch.tap()
        sleep(1); shot("layers")
        app.buttons["Готово"].firstMatch.tap()
        sleep(1)
        app.buttons["Фон"].firstMatch.tap()
        sleep(1); shot("background")
        app.buttons["Готово"].firstMatch.tap()
        sleep(1)
        app.buttons["Попередній перегляд"].firstMatch.tap()
        sleep(2); shot("preview")
        app.tap()
        sleep(1)
        app.buttons["Закрити"].firstMatch.tap()
        sleep(1); shot("close-dialog")
        app.buttons["Зберегти й закрити"].firstMatch.tap()
        sleep(2); shot("projects")
    }
}
