// SPDX-License-Identifier: MIT
// Логіка редактора на симуляторі: створення, усі типи елементів, рендер, збирання й відкриття .bin.
import XCTest
@testable import FaceEditor

@MainActor
final class FaceEditorTests: XCTestCase {
    func testCreateAddRenderCompile() throws {
        let store = ProjectStore()
        let p = store.create(name: "Test")
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
        XCTAssertEqual(r.files, p.files)
        XCTAssertEqual(try r.compile().0, try p.compile().0)
        // і через шлях із символьним посиланням (на iOS /var -> /private/var)
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: p.folder)
        defer { try? FileManager.default.removeItem(at: link) }
        let viaLink = FaceProject.load(folder: link)!
        XCTAssertEqual(Set(viaLink.files.keys), Set(p.files.keys))
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
            // кроки в BigWatch/WhatTime: align="center", x=106 — число має стояти по центру екрана
            for b in boxes where p.resource(ref: b.layout.string("ref"))?.string("source") == "healthStepCount" {
                XCTAssertEqual(b.rect.midX, 106, accuracy: 0.5, u.lastPathComponent)
            }
            let bin = try p.compile().0
            XCTAssertTrue(bin.count > 0)
            // після перезапуску застосунку (читання з диска) картинки на місці й збирається те саме
            let r = FaceProject.load(folder: p.folder)!
            XCTAssertEqual(Set(r.files.keys), Set(p.files.keys), u.lastPathComponent)
            XCTAssertEqual(try r.compile().0, bin, u.lastPathComponent)
            store.delete(p)
        }
    }

    /// Превʼю з ресурсів (для BandFace) і превʼю для браслета, яке редактор малює при збиранні.
    func testPreviews() throws {
        let store = ProjectStore()
        let u = try XCTUnwrap(Bundle(for: FaceEditorTests.self).url(forResource: "BigWatch_UA", withExtension: "bin"))
        let data = try Data(contentsOf: u)
        let shots = FacePreviews.render(data)
        XCTAssertEqual(shots.count, 2)
        XCTAssertEqual(shots.first?.alwaysOn, false)
        XCTAssertEqual(shots.last?.alwaysOn, true)
        XCTAssertEqual(shots.first?.image.cgImage?.width, 318)
        XCTAssertEqual(shots.first?.image.cgImage?.height, 780)
        // кеш на диску віддає те саме
        _ = FacePreviews.shots(for: data)
        XCTAssertEqual(FacePreviews.cached(for: data)?.count, 2)

        // новий циферблат: превʼю 134×328 з'являється при збиранні
        let p = store.create(name: "Preview")
        defer { store.delete(p) }
        let (root, files) = try FaceProject.unpack(try p.compile().0)
        let ref = try XCTUnwrap(root.first("Theme")?.string("preview"))
        let img = try XCTUnwrap(root.first("Resources")?.elements.first { "@" + ($0.string("name") ?? "") == ref })
        let png = try XCTUnwrap(files[img.string("src") ?? ""].flatMap { UIImage(data: $0)?.cgImage })
        XCTAssertEqual(png.width, 134)
        XCTAssertEqual(png.height, 328)

        // копія з магазину: новий ID; після зміни старе превʼю замінюється, кількість ресурсів та сама
        let c = try store.importBin(data, name: "BigWatch", asCopy: true)
        defer { store.delete(c) }
        XCTAssertNotEqual(c.root.string("id"), try FaceProject.unpack(data).0.string("id"))
        XCTAssertEqual(try c.compile().0.count > 0, true)
        let before = c.resources.elements.count
        let withoutPreview = c.themes.filter { !$0.has("preview") }.count
        c.edit { $0.theme(0)?.set("bgColor", "#102030") }
        let (root2, files2) = try FaceProject.unpack(try c.compile().0)
        // старе превʼю замінено (не додано поруч); темам без превʼю воно з'явилося
        XCTAssertEqual(root2.first("Resources")?.elements.count, before + withoutPreview)
        for t in root2.all("Theme") {
            let r = try XCTUnwrap(t.string("preview"))
            let e = try XCTUnwrap(root2.first("Resources")?.elements.first { "@" + ($0.string("name") ?? "") == r })
            XCTAssertEqual(e.string("format"), "indexed8")
            XCTAssertEqual(files2[e.string("src") ?? ""].flatMap { UIImage(data: $0)?.cgImage?.width }, 134)
        }
    }
}
