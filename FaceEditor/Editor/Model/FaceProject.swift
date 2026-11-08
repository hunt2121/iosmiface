// SPDX-License-Identifier: MIT
// Проєкт циферблата для редактора: manifest.xml (дерево XNode без втрат) + файли ресурсів + налаштування редактора.
// Будь-який розпакований .bin стає проєктом, і після редагування збирається назад тим самим компілятором.

import Foundation
import UIKit
import FaceCompiler

/// Параметри, з яких редактор створив ресурс (щоб перегенерувати картинки після зміни шрифту, кольору тощо).
struct Generator: Codable, Equatable {
    enum Kind: String, Codable { case digits, arc, line, pointer, image, frames, label, texts }
    var kind: Kind
    var color: String = "#FFFFFF"
    var bgColor: String = "#3A3A3C"
    var fontSize: Double = 48
    var weight: Int = 700
    var style: String = "rounded"        // rounded | default | condensed | mono
    var radius: Double = 60
    var width: Double = 10
    var length: Double = 120
    /// Одиниця біля числа («%», «°», «км»), малюється тим самим шрифтом
    var unit: String = ""
    /// Рядок напису (kind == .label): малюється шрифтом у картинку
    var text: String = ""
    /// Шрифт користувача (назва з бібліотеки шрифтів); порожньо — за стилем
    var font: String = ""
    /// Дуга: початок і довжина (0° — угорі, за годинниковою); трек і заповнення лише в цих межах
    var start: Double = 40 // розріз угорі: 0° + 180° − 280°/2
    var range: Double = 280
    /// Лінія: напрямок (0° — праворуч, 90° — донизу)
    var angle: Double = 0
    /// Кінці дуги й лінії: круглі (типово) або прямі
    var round: Bool = true
    /// Набір цифр: обвідка, тінь, градієнт згори донизу, ширина літер
    var outline: Double = 0
    var outlineColor: String = "#000000"
    var shadowX: Double = 0
    var shadowY: Double = 0
    var shadowColor: String = "#000000"
    var color2: String = ""
    var widthPct: Double = 100
    /// kind == .texts: рядок для кожної картинки масиву (дні тижня, місяці, AM/PM…)
    var texts: [String] = []

    /// Картинки намальовані редактором з цих параметрів (а не свої картинки користувача)
    /// Фігури, намальовані редактором (дуга, лінія, стрілка) — перемальовуються з параметрів.
    /// Цифри й написи шрифтом редактор більше не малює: вони, як і решта, лише картинки.
    var drawn: Bool { kind == .arc || kind == .line || kind == .pointer }

    var styled: Bool { outline > 0 || shadowX != 0 || shadowY != 0 || !color2.isEmpty || abs(widthPct - 100) > 0.01 }

    /// Скопіювати вигляд (шрифт, колір, ефекти) з набору, не чіпаючи розміру й тексту
    mutating func applyStyle(_ s: Generator) {
        font = s.font; style = s.style; weight = s.weight; color = s.color; color2 = s.color2
        outline = s.outline; outlineColor = s.outlineColor; shadowX = s.shadowX; shadowY = s.shadowY; shadowColor = s.shadowColor; widthPct = s.widthPct
    }

    init(kind: Kind, color: String = "#FFFFFF", bgColor: String = "#3A3A3C", fontSize: Double = 48, weight: Int = 700,
         style: String = "rounded", radius: Double = 60, width: Double = 10, length: Double = 120, unit: String = "", text: String = "") {
        self.kind = kind; self.color = color; self.bgColor = bgColor; self.fontSize = fontSize; self.weight = weight
        self.style = style; self.radius = radius; self.width = width; self.length = length; self.unit = unit; self.text = text
    }

    // старі editor.json не мають нових полів — беремо типові
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? "#FFFFFF"
        bgColor = (try? c.decodeIfPresent(String.self, forKey: .bgColor)) ?? "#3A3A3C"
        fontSize = (try? c.decodeIfPresent(Double.self, forKey: .fontSize)) ?? 48
        weight = (try? c.decodeIfPresent(Int.self, forKey: .weight)) ?? 700
        style = (try? c.decodeIfPresent(String.self, forKey: .style)) ?? "rounded"
        radius = (try? c.decodeIfPresent(Double.self, forKey: .radius)) ?? 60
        width = (try? c.decodeIfPresent(Double.self, forKey: .width)) ?? 10
        length = (try? c.decodeIfPresent(Double.self, forKey: .length)) ?? 120
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        font = (try? c.decodeIfPresent(String.self, forKey: .font)) ?? ""
        // старі проєкти: дуга була повним кільцем, лінія — горизонтальною (справжні кути беруться з маніфесту)
        start = (try? c.decodeIfPresent(Double.self, forKey: .start)) ?? 0
        range = (try? c.decodeIfPresent(Double.self, forKey: .range)) ?? 360
        angle = (try? c.decodeIfPresent(Double.self, forKey: .angle)) ?? 0
        round = (try? c.decodeIfPresent(Bool.self, forKey: .round)) ?? true
        outline = (try? c.decodeIfPresent(Double.self, forKey: .outline)) ?? 0
        outlineColor = (try? c.decodeIfPresent(String.self, forKey: .outlineColor)) ?? "#000000"
        shadowX = (try? c.decodeIfPresent(Double.self, forKey: .shadowX)) ?? 0
        shadowY = (try? c.decodeIfPresent(Double.self, forKey: .shadowY)) ?? 0
        shadowColor = (try? c.decodeIfPresent(String.self, forKey: .shadowColor)) ?? "#000000"
        color2 = (try? c.decodeIfPresent(String.self, forKey: .color2)) ?? ""
        widthPct = (try? c.decodeIfPresent(Double.self, forKey: .widthPct)) ?? 100
        texts = (try? c.decodeIfPresent([String].self, forKey: .texts)) ?? []
    }
}

/// Пристрій: розмір екрана для полотна й нового циферблата. Лише Smart Band 10.
struct DeviceProfile: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var width: Int
    var height: Int
    var corner: Double

    static let band10 = DeviceProfile(id: "band10", title: "Smart Band 10", width: 212, height: 520, corner: 106)
}

struct ProjectMeta: Codable {
    var device = DeviceProfile.band10
    var generators: [String: Generator] = [:]
    var modified = Date()
    /// Циферблат змінювали в редакторі: при збиранні превʼю для браслета малюється заново
    var edited = false
    /// Ключ превʼю .bin, з якого відкрито проєкт: поки проєкт не змінювали, превʼю й анімація ті самі,
    /// що в магазині чи для вибраного файла, — не малюються вдруге
    var sourceKey: String?
    /// Елементи з галочкою «Змінюється з кольором циферблата» (діє, щойно в циферблата з'являться кольори)
    var colorFollow: Set<String> = []
    /// Значення для перегляду в редакторі (на браслет не записуються)
    var demo = DemoValues()

    init() {}

    // editor.json старіших версій не має нових полів — читаємо те, що є
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = (try? c.decodeIfPresent(DeviceProfile.self, forKey: .device)) ?? .band10
        generators = (try? c.decodeIfPresent([String: Generator].self, forKey: .generators)) ?? [:]
        modified = (try? c.decodeIfPresent(Date.self, forKey: .modified)) ?? Date()
        edited = (try? c.decodeIfPresent(Bool.self, forKey: .edited)) ?? false
        sourceKey = try? c.decodeIfPresent(String.self, forKey: .sourceKey)
        colorFollow = (try? c.decodeIfPresent(Set<String>.self, forKey: .colorFollow)) ?? []
        demo = (try? c.decodeIfPresent(DemoValues.self, forKey: .demo)) ?? DemoValues()
    }
}

/// Значення для перегляду: свої для кожного джерела; час і дата — свої або справжні (з телефона).
/// Формат editor.json спільний з Windows.
struct DemoValues: Codable, Equatable {
    var values: [String: Int] = [:]
    /// "HH:mm"; nil — типовий 10:24
    var time: String?
    /// "yyyy-MM-dd"; nil — типова 30.05.2026
    var date: String?
    var realTime = false
    var realDate = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        values = (try? c.decodeIfPresent([String: Int].self, forKey: .values)) ?? [:]
        time = try? c.decodeIfPresent(String.self, forKey: .time)
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        realTime = (try? c.decodeIfPresent(Bool.self, forKey: .realTime)) ?? false
        realDate = (try? c.decodeIfPresent(Bool.self, forKey: .realDate)) ?? false
    }

    /// Години й хвилини, якщо задано свій час
    var hm: (Int, Int)? {
        guard let t = time else { return nil }
        let p = t.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }
    /// День, місяць, рік, якщо задано свою дату
    var dmy: (Int, Int, Int)? {
        guard let d = date else { return nil }
        let p = d.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[2], p[1], p[0]) : nil
    }
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
    private var redoStack: [(Data, [String: Data], ProjectMeta)] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    /// Розпаковані картинки проєкту, спільні для всіх рендерів
    let images = ImageCache()
    /// Що записати на диск при наступному збереженні (а не всі файли щоразу)
    private var dirty = Set<String>()
    private var removed = Set<String>()
    private var fullSave = true

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
    /// Назва для показу: «Без назви», якщо порожня
    var displayName: String { name.isEmpty ? loc("Без назви") : name }

    func resource(named n: String) -> XNode? {
        resources.elements.first { $0.string("name") == n }
    }
    /// Ресурс за посиланням «@ім'я».
    func resource(ref: String?) -> XNode? {
        guard let ref, ref.count > 1 else { return nil }
        return resource(named: String(ref.dropFirst()))
    }

    /// Елемент шару: для обгортки «дія при натисканні» — те, що всередині
    func element(of layout: XNode) -> XNode? {
        guard let r = resource(ref: layout.string("ref")) else { return nil }
        if let inner = ElementFactory.tapInner(self, r) { return inner }
        return r
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
        redoStack.removeAll()
        change(self)
        meta.modified = Date()
        meta.edited = true
        revision += 1
        objectWillChange.send()
        save()
    }

    func undo() {
        guard let snap = undoStack.popLast(), let r = try? XML.parse([UInt8](snap.0)) else { return }
        redoStack.append((Data(XML.print(root)), files, meta))
        restore(r, snap.1, snap.2)
    }

    func redo() {
        guard let snap = redoStack.popLast(), let r = try? XML.parse([UInt8](snap.0)) else { return }
        undoStack.append((Data(XML.print(root)), files, meta))
        restore(r, snap.1, snap.2)
    }

    private func restore(_ r: XNode, _ f: [String: Data], _ m: ProjectMeta) {
        root = r; files = f; meta = m
        images.removeAll()
        fullSave = true
        revision += 1
        save()
    }

    /// Файли вже на диску (щойно прочитаний проєкт)
    func markSaved() { fullSave = false; dirty.removeAll(); removed.removeAll() }

    func setFile(_ path: String, _ data: Data) {
        let k = MemoryStorage.normalizedPath(path)
        files[k] = data; images.remove(k); dirty.insert(k); removed.remove(k)
    }
    func removeFile(_ path: String) {
        let k = MemoryStorage.normalizedPath(path)
        files[k] = nil; images.remove(k); dirty.remove(k); removed.insert(k)
    }

    // MARK: Збереження

    func save() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var xml: [UInt8] = []
        for c in XML.print(root) { if c == 0x0A { xml.append(0x0D) }; xml.append(c) }
        try? Data(xml).write(to: folder.appendingPathComponent("manifest.xml"))
        // параметри редактора — у прихованому файлі (як у Windows-версії); старий editor.json прибираємо
        if let m = try? JSONEncoder().encode(meta) { try? m.write(to: folder.appendingPathComponent(Self.metaFile)) }
        try? fm.removeItem(at: folder.appendingPathComponent(Self.oldMetaFile))
        let filesDir = folder.appendingPathComponent("files")
        // лише змінені файли; повністю — після відкату й при першому збереженні
        if fullSave { try? fm.removeItem(at: filesDir) }
        for p in removed { try? fm.removeItem(at: filesDir.appendingPathComponent(p)) }
        for (p, d) in files where fullSave || dirty.contains(p) {
            let u = filesDir.appendingPathComponent(p)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: u)
        }
        fullSave = false; dirty.removeAll(); removed.removeAll()
    }

    /// Прихований файл налаштувань редактора в теці проєкту (спільний формат з Windows-версією)
    static let metaFile = ".bandface.json"
    static let oldMetaFile = "editor.json"

    static func readMeta(_ folder: URL) -> ProjectMeta {
        var meta = [metaFile, oldMetaFile].lazy.compactMap { try? Data(contentsOf: folder.appendingPathComponent($0)) }.first
            .flatMap { try? JSONDecoder().decode(ProjectMeta.self, from: $0) } ?? ProjectMeta()
        meta.device = .band10
        return meta
    }

    /// Новий маніфест цілком (режим XML) — лише всередині edit, щоб можна було скасувати
    func setRoot(_ r: XNode) { root = r; images.removeAll() }

    /// Файли теки змінили ззовні (застосунок «Файли», інший редактор): перечитати. Як звичайна зміна — її можна скасувати.
    @discardableResult func reloadFromDisk() -> Bool {
        guard let xml = try? Data(contentsOf: folder.appendingPathComponent("manifest.xml")) else { return false }
        let fresh = FaceProject.readFiles(folder)
        var mine: [UInt8] = []
        for c in XML.print(root) { if c == 0x0A { mine.append(0x0D) }; mine.append(c) }
        let sameXml = [UInt8](xml) == mine || [UInt8](xml) == XML.print(root)
        let sameFiles = fresh == files
        if sameXml && sameFiles { return false }
        let parsed: XNode? = sameXml ? root : ((try? XML.parse([UInt8](xml))) ?? nil)
        guard let r = parsed else { return false }
        undoStack.append((Data(XML.print(root)), files, meta))
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        root = r; files = fresh
        images.removeAll()
        markSaved()
        revision += 1
        return true
    }

    static func readFiles(_ folder: URL) -> [String: Data] {
        var files: [String: Data] = [:]
        let filesDir = folder.appendingPathComponent("files")
        let fm = FileManager.default
        if let en = fm.enumerator(atPath: filesDir.path) {
            for case let rel as String in en {
                var isDir: ObjCBool = false
                let full = filesDir.appendingPathComponent(rel)
                guard fm.fileExists(atPath: full.path, isDirectory: &isDir), !isDir.boolValue,
                      let d = try? Data(contentsOf: full) else { continue }
                files[MemoryStorage.normalizedPath(rel)] = d
            }
        }
        return files
    }

    static func load(folder: URL) -> FaceProject? {
        guard let xml = try? Data(contentsOf: folder.appendingPathComponent("manifest.xml")),
              let root = try? XML.parse([UInt8](xml)) else { return nil }
        let meta = readMeta(folder)
        var files: [String: Data] = [:]
        let filesDir = folder.appendingPathComponent("files")
        // Відносні шляхи беремо прямо з перелічувача: на iOS /var і /private/var — той самий каталог,
        // тож відрізання префікса від абсолютного шляху ненадійне (раніше всі картинки губилися).
        let fm = FileManager.default
        if let en = fm.enumerator(atPath: filesDir.path) {
            for case let rel as String in en {
                var isDir: ObjCBool = false
                let full = filesDir.appendingPathComponent(rel)
                guard fm.fileExists(atPath: full.path, isDirectory: &isDir), !isDir.boolValue,
                      let d = try? Data(contentsOf: full) else { continue }
                files[MemoryStorage.normalizedPath(rel)] = d
            }
        }
        let project = FaceProject(id: folder.lastPathComponent, folder: folder, root: root, files: files, meta: meta)
        project.markSaved()
        return project
    }

    /// Розпаковує .bin у дерево маніфесту й файли (без запису на диск).
    static func unpack(_ data: Data) throws -> (XNode, [String: Data]) {
        let mem = MemoryStorage()
        try WatchfaceCompiler.unpack(data, to: mem)
        guard let xml = mem.files.removeValue(forKey: "manifest.xml"), let root = try XML.parse([UInt8](xml)) else {
            throw FaceCompilerError("manifest.xml не створено")
        }
        return (root, mem.files)
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
    /// Після змін у редакторі (або коли превʼю немає) превʼю для браслета малюється заново.
    func compile() throws -> (Data, [String]) {
        let log = FaceCompilerLog()
        ColorVariants.syncThemes(self)
        let needsPreview = meta.edited || themes.contains { !$0.has("preview") }
        // кольорові варіанти — з копіями незмінних картинок, як у exe: без них браслет перезавантажується
        // при виборі кольору (перевірено на Smart Band 10, збірка 235)
        let st = needsPreview ? storageWithFreshPreviews() : storage()
        if ColorVariants.isEnabled(self) { addBackgroundFill(st) }
        // Band 10/11 знає лише indexed8: картинки інших форматів (фото, циферблати від інших браслетів) — у 256 кольорів (Б-1)
        Band10.fixImages(st)
        let data = try WatchfaceCompiler.build(from: st, log: log)
        return (data, log.warnings)
    }

    /// Циферблат із вибором кольору: браслет злегка підфарбовує фон теми вибраним кольором, тож найнижчим
    /// шаром кладемо непрозору картинку кольору фону (якщо такого шару ще немає). Проєкт не змінюється.
    private func addBackgroundFill(_ st: MemoryStorage) {
        guard let xml = st.files["manifest.xml"], let root = try? XML.parse([UInt8](xml)) else { return }
        let res: XNode
        if let r = root.first("Resources") { res = r } else { res = XNode("Resources"); root.kids.insert(res, at: 0) }
        let dev = meta.device
        var used = Set(res.elements.compactMap { $0.string("name") })
        for (t, theme) in root.all("Theme").enumerated() {
            if let first = theme.all("Layout").first, coversScreen(first, res, st) { continue }
            let color = theme.string("bgColor") ?? "#000000"
            let fill = AssetFactory.render(dev.width, dev.height) { ctx in
                ctx.setFillColor(AssetFactory.color(color).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: dev.width, height: dev.height))
            }
            var name = "bgfill_\(t)"
            var i = 2
            while used.contains(name) { name = "bgfill_\(t)_\(i)"; i += 1 }
            used.insert(name)
            st.files["\(name).png"] = fill.png
            let e = XNode("Image")
            e.set("name", name).set("src", "\(name).png").set("compressMethod", "RLEReversed")
                .set("format", fill.bestFormat).set("recolorEnable", bool: false)
            res.kids.append(e)
            let l = XNode("Layout")
            l.set("ref", "@" + name).set("x", int: 0).set("y", int: 0)
            let idx = theme.kids.firstIndex { $0.tag == "Layout" } ?? theme.kids.count
            theme.kids.insert(l, at: idx)
        }
        st.files["manifest.xml"] = Data(XML.print(root))
    }

    /// Шар — непрозора картинка на весь екран у точці 0,0
    private func coversScreen(_ layout: XNode, _ res: XNode, _ st: MemoryStorage) -> Bool {
        guard layout.int("x") == 0, layout.int("y") == 0, let ref = layout.string("ref"), ref.count > 1 else { return false }
        let name = String(ref.dropFirst())
        guard let img = res.elements.first(where: { $0.tag == "Image" && $0.string("name") == name }),
              let src = img.string("src"), let d = st.files[MemoryStorage.normalizedPath(src)],
              let png = PNG.decode([UInt8](d)) else { return false }
        guard png.w >= meta.device.width, png.h >= meta.device.height else { return false }
        var i = 3
        while i < png.rgba.count { if png.rgba[i] < 255 { return false }; i += 4 }
        return true
    }

    /// Розмір превʼю, яке браслет показує у списку циферблатів (як в офіційних циферблатах Smart Band 10)
    static let previewSize = (w: 134, h: 328)

    /// Сховище для збирання, де в кожної теми нове превʼю — зменшений кадр цієї теми.
    /// Сам проєкт не змінюється. Старе превʼю прибирається, якщо більше ніде не використовується.
    func storageWithFreshPreviews() -> MemoryStorage {
        let root = self.root.copy()
        var all = files
        let res: XNode
        if let r = root.first("Resources") { res = r } else { res = XNode("Resources"); root.kids.insert(res, at: 0) }
        var used = Set(res.elements.compactMap { $0.string("name") })
        let renderer = FaceRenderer(self)
        let themes = root.all("Theme")
        var inserted = 0
        for (t, theme) in themes.enumerated() {
            let old = theme.string("preview").flatMap { $0.count > 1 ? String($0.dropFirst()) : nil }
            let (frame, _) = renderer.render(theme: t, scale: 1)
            let size = Self.previewSize
            let small = AssetFactory.render(size.w, size.h) { ctx in
                ctx.interpolationQuality = .high
                frame.draw(in: CGRect(x: 0, y: 0, width: size.w, height: size.h))
            }.quantized()   // indexed8, як в офіційних превʼю: без втрат при повторному збиранні
            var name = "preview_\(t)"
            var i = 2
            while used.contains(name) { name = "preview_\(t)_\(i)"; i += 1 }
            used.insert(name)
            all["\(name).png"] = small.png
            let e = XNode("Image")
            e.set("name", name).set("src", "\(name).png").set("compressMethod", "RLEReversed")
                .set("format", small.bestFormat).set("recolorEnable", bool: false)
            res.kids.insert(e, at: inserted)
            inserted += 1
            theme.set("preview", "@" + name)
            // старе превʼю більше не потрібне, якщо на нього не посилається ні шар, ні інша тема
            if let old, Self.references(to: old, in: root) == 0,
               let idx = res.kids.firstIndex(where: { !$0.isComment && $0.string("name") == old }) {
                if let src = res.kids[idx].string("src") { all[MemoryStorage.normalizedPath(src)] = nil }
                for img in res.kids[idx].all("Image") { if let s = img.string("src") { all[MemoryStorage.normalizedPath(s)] = nil } }
                res.kids.remove(at: idx)
                if idx < inserted { inserted -= 1 }
            }
        }
        all["manifest.xml"] = Data(XML.print(root))
        return MemoryStorage(all)
    }

    /// Скільки разів десь у маніфесті є «@name».
    private static func references(to name: String, in node: XNode) -> Int {
        let ref = Array(("@" + name).utf8)
        var n = node.attrs.filter { $0.1 == ref }.count
        for k in node.kids where !k.isComment { n += references(to: name, in: k) }
        return n
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

/// Розпаковані картинки проєкту (потокобезпечно: мініатюри малюються у фоні)
final class ImageCache {
    private var map: [String: CGImage] = [:]
    private let lock = NSLock()

    func get(_ key: String, make: () -> CGImage?) -> CGImage? {
        lock.lock()
        if let c = map[key] { lock.unlock(); return c }
        lock.unlock()
        guard let img = make() else { return nil }
        lock.lock(); map[key] = img; lock.unlock()
        return img
    }
    func remove(_ key: String) { lock.lock(); map[key] = nil; lock.unlock() }
    func removeAll() { lock.lock(); map.removeAll(); lock.unlock() }
}
