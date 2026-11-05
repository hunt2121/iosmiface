// SPDX-License-Identifier: MIT
// Проєкт циферблата для редактора: manifest.xml (дерево XNode без втрат) + файли ресурсів + налаштування редактора.
// Будь-який розпакований .bin стає проєктом, і після редагування збирається назад тим самим компілятором.

import Foundation
import FaceCompiler

/// Параметри, з яких редактор створив ресурс (щоб перегенерувати картинки після зміни шрифту, кольору тощо).
struct Generator: Codable, Equatable {
    enum Kind: String, Codable { case digits, arc, line, pointer, image, frames }
    var kind: Kind
    var color: String = "#FFFFFF"
    var bgColor: String = "#3A3A3C"
    var fontSize: Double = 48
    var weight: Int = 700
    var style: String = "rounded"        // rounded | default | condensed | mono
    var radius: Double = 60
    var width: Double = 10
    var length: Double = 120
}

/// Пристрій: розмір екрана для полотна й нового циферблата.
struct DeviceProfile: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var width: Int
    var height: Int
    var corner: Double

    static let band10 = DeviceProfile(id: "band10", title: "Smart Band 10", width: 212, height: 520, corner: 106)
    static let band9 = DeviceProfile(id: "band9", title: "Smart Band 9", width: 192, height: 490, corner: 96)
    static let all = [band10, band9]
}

struct ProjectMeta: Codable {
    var device = DeviceProfile.band10
    var generators: [String: Generator] = [:]
    var modified = Date()
}

final class FaceProject: ObservableObject, Identifiable {
    let id: String
    let folder: URL
    /// Дерево manifest.xml
    @Published private(set) var root: XNode
    /// Усі файли проєкту, крім manifest.xml і editor.json (шлях -> вміст)
    @Published private(set) var files: [String: Data]
    @Published var meta: ProjectMeta
    /// Лічильник змін — перерисовує полотно
    @Published private(set) var revision = 0

    private var undoStack: [(Data, [String: Data], ProjectMeta)] = []
    var canUndo: Bool { !undoStack.isEmpty }

    init(id: String, folder: URL, root: XNode, files: [String: Data], meta: ProjectMeta) {
        self.id = id; self.folder = folder; self.root = root; self.files = files; self.meta = meta
    }

    // MARK: Доступ до маніфесту

    var resources: XNode {
        if let r = root.first("Resources") { return r }
        let r = XNode("Resources"); root.kids.insert(r, at: 0); return r
    }
    var themes: [XNode] { root.all("Theme") }
    func theme(_ i: Int) -> XNode? { let t = themes; return t.indices.contains(i) ? t[i] : nil }
    func layouts(_ theme: Int) -> [XNode] { self.theme(theme)?.all("Layout") ?? [] }

    var name: String {
        get { root.string("name") ?? "" }
    }

    func resource(named n: String) -> XNode? {
        resources.elements.first { $0.string("name") == n }
    }
    /// Ресурс за посиланням «@ім'я».
    func resource(ref: String?) -> XNode? {
        guard let ref, ref.count > 1 else { return nil }
        return resource(named: String(ref.dropFirst()))
    }

    func uniqueName(_ base: String) -> String {
        let used = Set(resources.elements.compactMap { $0.string("name") })
        if !used.contains(base) { return base }
        var i = 2
        while used.contains("\(base)\(i)") { i += 1 }
        return "\(base)\(i)"
    }

    func file(_ path: String) -> Data? { files[MemoryStorage.normalizedPath(path)] }

    // MARK: Зміни (з відкатом)

    /// Будь-яка зміна проходить тут: знімок для «Скасувати», потім зміна, потім збереження.
    func edit(_ change: (FaceProject) -> Void) {
        undoStack.append((Data(XML.print(root)), files, meta))
        if undoStack.count > 40 { undoStack.removeFirst() }
        change(self)
        meta.modified = Date()
        revision += 1
        objectWillChange.send()
        save()
    }

    func undo() {
        guard let snap = undoStack.popLast(), let r = try? XML.parse([UInt8](snap.0)) else { return }
        root = r; files = snap.1; meta = snap.2
        revision += 1
        save()
    }

    func setFile(_ path: String, _ data: Data) { files[MemoryStorage.normalizedPath(path)] = data }
    func removeFile(_ path: String) { files[MemoryStorage.normalizedPath(path)] = nil }

    // MARK: Збереження

    func save() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var xml: [UInt8] = []
        for c in XML.print(root) { if c == 0x0A { xml.append(0x0D) }; xml.append(c) }
        try? Data(xml).write(to: folder.appendingPathComponent("manifest.xml"))
        if let m = try? JSONEncoder().encode(meta) { try? m.write(to: folder.appendingPathComponent("editor.json")) }
        let filesDir = folder.appendingPathComponent("files")
        try? fm.removeItem(at: filesDir)
        for (p, d) in files {
            let u = filesDir.appendingPathComponent(p)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: u)
        }
    }

    static func load(folder: URL) -> FaceProject? {
        guard let xml = try? Data(contentsOf: folder.appendingPathComponent("manifest.xml")),
              let root = try? XML.parse([UInt8](xml)) else { return nil }
        let meta = (try? Data(contentsOf: folder.appendingPathComponent("editor.json")))
            .flatMap { try? JSONDecoder().decode(ProjectMeta.self, from: $0) } ?? ProjectMeta()
        var files: [String: Data] = [:]
        let filesDir = folder.appendingPathComponent("files")
        if let en = FileManager.default.enumerator(at: filesDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let u as URL in en where (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let rel = u.path.replacingOccurrences(of: filesDir.path + "/", with: "")
                files[rel] = try? Data(contentsOf: u)
            }
        }
        return FaceProject(id: folder.lastPathComponent, folder: folder, root: root, files: files, meta: meta)
    }

    // MARK: Збирання

    var manifestBytes: [UInt8] { XML.print(root) }

    /// Сховище для компілятора: файли + manifest.xml.
    func storage() -> MemoryStorage {
        var all = files
        all["manifest.xml"] = Data(XML.print(root))
        return MemoryStorage(all)
    }

    /// Збирає .bin. Повертає дані й попередження компілятора.
    func compile() throws -> (Data, [String]) {
        let log = FaceCompilerLog()
        let data = try WatchfaceCompiler.build(from: storage(), log: log)
        return (data, log.warnings)
    }
}

extension MemoryStorage {
    static func normalizedPath(_ p: String) -> String {
        var parts: [Substring] = []
        for c in p.replacingOccurrences(of: "\\", with: "/").split(separator: "/") {
            if c == "." { continue }
            if c == "..", !parts.isEmpty { parts.removeLast(); continue }
            parts.append(c)
        }
        return parts.joined(separator: "/")
    }
}
