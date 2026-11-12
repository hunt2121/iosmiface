// SPDX-License-Identifier: MIT
// Список проєктів у Documents/FaceProjects: створення, відкриття .bin, копія, видалення.

import Foundation
import UIKit
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

    /// Новий ID циферблата (9 цифр, як у Mi Fitness): копія не замінює оригінал на браслеті.
    static func newFaceID() -> String { String(Int.random(in: 100_000_000...999_999_999)) }

    /// Новий циферблат: великі години й хвилини (з BigWatch).
    func create(name: String) -> FaceProject {
        let root = XNode("Watchface")
        root.set("id", Self.newFaceID())
        root.set("name", name)
        root.add("Resources")
        let theme = root.add("Theme")
        theme.set("type", "normal").set("name", "").set("bgColor", "#000000")
        let meta = ProjectMeta()
        let folder = newFolder()
        // id = ім'я теки, як у FaceProject.load: інакше після reload() id змінюється і прогрес встановлення губиться
        let p = FaceProject(id: folder.lastPathComponent, folder: folder, root: root, files: [:], meta: meta)
        // старт — великі години й хвилини з BigWatch на тих самих місцях
        let imgs = StarterDigits.png.compactMap { Data(base64Encoded: $0).flatMap(UIImage.init(data:)) }
            .map { AssetFactory.fromUIImage($0, maxSide: 10_000) }
        if let f0 = imgs.first {
            // addDigitImages ставить число за центром: лівий край = x − ширина цифри
            let (hx, hy) = StarterDigits.hourOrigin, (mx, my) = StarterDigits.minuteOrigin
            // хвилини беруть ті самі 10 картинок, що й години (як у BigWatch)
            let digits = ElementFactory.addDigitImages(p, source: "timeHour", images: imgs, theme: 0, center: (hx + f0.w, hy + f0.h / 2))
            ElementFactory.addDigitImages(p, source: "timeMinute", images: imgs, theme: 0, center: (mx + f0.w, my + f0.h / 2), sharedArray: digits)
        }
        p.save()
        projects.insert(p, at: 0)
        return p
    }

    /// Відкрити готовий .bin: розпакування тим самим компілятором.
    /// `asCopy` — копія чужого циферблата (з магазину): новий ID і «(копія)» в назві.
    func importBin(_ data: Data, name: String, asCopy: Bool = false) throws -> FaceProject {
        let (root, files) = try FaceProject.unpack(data)
        var meta = ProjectMeta()
        meta.sourceKey = FacePreviews.dataKey(data)
        let folder = newFolder()
        // id = ім'я теки, як у FaceProject.load: інакше після reload() id змінюється і прогрес встановлення губиться
        let p = FaceProject(id: folder.lastPathComponent, folder: folder, root: root, files: files, meta: meta)
        if (root.string("name") ?? "").isEmpty { root.set("name", name) }
        if asCopy {
            root.set("id", Self.newFaceID())
            root.set("name", (root.string("name") ?? name) + loc(" (копія)"))
        }
        p.save()
        projects.insert(p, at: 0)
        return p
    }

    func duplicate(_ p: FaceProject) {
        let folder = newFolder()
        try? FileManager.default.copyItem(at: p.folder, to: folder)
        if let c = FaceProject.load(folder: folder) {
            // власний ID: інакше копія на браслеті замінила б оригінал
            c.edit { $0.root.set("name", ($0.root.string("name") ?? "") + loc(" (копія)")).set("id", Self.newFaceID()) }
            projects.insert(c, at: 0)
        }
    }

    func delete(_ p: FaceProject) {
        try? FileManager.default.removeItem(at: p.folder)
        projects.removeAll { $0.id == p.id }
    }
}
