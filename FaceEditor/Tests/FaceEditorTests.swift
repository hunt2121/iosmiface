// SPDX-License-Identifier: MIT
// Логіка редактора на симуляторі: створення, усі типи елементів, рендер, збирання й відкриття .bin.
import XCTest
@testable import FaceEditor

@MainActor
final class FaceEditorTests: XCTestCase {
    func testCreateAddRenderCompile() throws {
        let store = ProjectStore()
        let p = store.create(name: "Test", device: .band10)
        defer { store.delete(p) }
        let c = (106, 260)
        p.edit { ElementFactory.addPointer($0, source: "timeMinute", gen: Generator(kind: .pointer, color: "#FFFFFF", width: 6, length: 80), theme: 0, center: c) }
        p.edit { ElementFactory.addArc($0, source: "systemStatusBattery", gen: Generator(kind: .arc, color: "#30B455", bgColor: "#3A3A3C", radius: 60, width: 10), theme: 0, center: c) }
        p.edit { ElementFactory.addLine($0, source: "healthStepProgress", gen: Generator(kind: .line, color: "#0A6CF0", bgColor: "#3A3A3C", width: 8, length: 140), theme: 0, center: c) }
        let img = AssetFactory.ring(radius: 20, width: 4, color: "#FF0000")
        p.edit { ElementFactory.addImage($0, img, theme: 0, center: c) }
        p.edit { ElementFactory.addAnimation($0, [img, img], interval: 100, theme: 0, center: c) }
        XCTAssertEqual(p.layouts(0).count, 8)
        let (ui, boxes) = FaceRenderer(p).render(theme: 0)
        XCTAssertEqual(boxes.count, 8)
        XCTAssertEqual(ui.size.width, 212)
        let (bin, warnings) = try p.compile()
        XCTAssertTrue(warnings.isEmpty, "\(warnings)")
        // відкриваємо зібране як новий проєкт і збираємо знову — те саме (порядок ресурсів збігається з порядком компілятора)
        let q = try store.importBin(bin, name: "back")
        defer { store.delete(q) }
        let bin2 = try q.compile().0
        XCTAssertEqual(bin2, bin)
        // друге коло розпакування/збирання стабільне завжди
        let q2 = try store.importBin(bin2, name: "back2")
        defer { store.delete(q2) }
        XCTAssertEqual(try q2.compile().0, bin2)
        // перегенерація, дублювання, видалення, відкат
        let digits = p.layouts(0)[0]
        let name = p.resource(ref: digits.string("ref"))!.string("name")!
        var g = p.meta.generators[name]!; g.fontSize = 30; g.style = "condensed"
        p.edit { ElementFactory.regenerate($0, element: name, gen: g) }
        p.edit { ElementFactory.duplicate($0, layout: digits, theme: 0) }
        XCTAssertEqual(p.layouts(0).count, 9)
        p.edit { ElementFactory.delete($0, layout: p.layouts(0).last!, theme: 0) }
        XCTAssertEqual(p.layouts(0).count, 8)
        p.undo()
        XCTAssertEqual(p.layouts(0).count, 9)
        _ = try p.compile()
        // збережений на диск проєкт відкривається знову
        let r = FaceProject.load(folder: p.folder)!
        XCTAssertEqual(r.manifestBytes, p.manifestBytes)
    }

    func testOpenBundledFaces() throws {
        let store = ProjectStore()
        let urls = Bundle(for: FaceEditorTests.self).urls(forResourcesWithExtension: "bin", subdirectory: nil) ?? []
        XCTAssertFalse(urls.isEmpty)
        for u in urls {
            let data = try Data(contentsOf: u)
            let p = try store.importBin(data, name: u.lastPathComponent)
            let (_, boxes) = FaceRenderer(p).render(theme: 0)
            XCTAssertFalse(boxes.isEmpty, u.lastPathComponent)
            XCTAssertEqual(try p.compile().0.count > 0, true)
            store.delete(p)
        }
    }
}
