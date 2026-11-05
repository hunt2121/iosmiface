// SPDX-License-Identifier: MIT
// Список проєктів у Documents/FaceProjects: створення, відкриття .bin, копія, видалення.

import Foundation
import FaceCompiler

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [FaceProject] = []

    let base: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FaceProjects")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() { reload() }

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { FaceProject.load(folder: $0) }.sorted { $0.meta.modified > $1.meta.modified }
    }

    private func newFolder() -> URL { base.appendingPathComponent(UUID().uuidString) }

    /// Порожній циферблат: фон, час цифрами, дата.
    func create(name: String) -> FaceProject {
        let root = XNode("Watchface")
        root.set("id", String(format: "%09d", Int.random(in: 100_000_000...999_999_999)))
        root.set("name", name)
        root.add("Resources")
        let theme = root.add("Theme")
        theme.set("type", "normal").set("name", "").set("bgColor", "#000000")
        let meta = ProjectMeta()
        let p = FaceProject(id: UUID().uuidString, folder: newFolder(), root: root, files: [:], meta: meta)
        // стартові елементи — щоб одразу було що редагувати
        let w = meta.device.width
        let digits = Generator(kind: .digits, color: "#FFFFFF", fontSize: 66, weight: 800, style: "rounded")
        ElementFactory.addDigits(p, source: "timeHour", gen: digits, theme: 0, center: (w / 2, 120))
        ElementFactory.addDigits(p, source: "timeMinute", gen: digits, theme: 0, center: (w / 2, 200))
        ElementFactory.addText(p, string: "%s", sources: ["dateDay"], theme: 0, center: (w / 2, 280), color: "#4DE1FF")
        p.save()
        projects.insert(p, at: 0)
        return p
    }

    /// Відкрити готовий .bin: розпакування тим самим компілятором.
    func importBin(_ data: Data, name: String) throws -> FaceProject {
        let mem = MemoryStorage()
        try WatchfaceCompiler.unpack(data, to: mem)
        guard let xml = mem.files.removeValue(forKey: "manifest.xml"), let root = try XML.parse([UInt8](xml)) else {
            throw FaceCompilerError("manifest.xml не створено")
        }
        let meta = ProjectMeta()
        let p = FaceProject(id: UUID().uuidString, folder: newFolder(), root: root, files: mem.files, meta: meta)
        if (root.string("name") ?? "").isEmpty { root.set("name", name) }
        p.save()
        projects.insert(p, at: 0)
        return p
    }

    func duplicate(_ p: FaceProject) {
        let folder = newFolder()
        try? FileManager.default.copyItem(at: p.folder, to: folder)
        if let c = FaceProject.load(folder: folder) {
            c.edit { $0.root.set("name", ($0.root.string("name") ?? "") + " (копія)") }
            projects.insert(c, at: 0)
        }
    }

    func delete(_ p: FaceProject) {
        try? FileManager.default.removeItem(at: p.folder)
        projects.removeAll { $0.id == p.id }
    }
}
