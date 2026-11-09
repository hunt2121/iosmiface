// SPDX-License-Identifier: MIT
// Створення, копіювання й видалення елементів циферблата (ресурс у <Resources> + <Layout> у темі),
// а також перегенерація картинок згенерованих елементів.

import Foundation
import UIKit
import FaceCompiler

enum ElementKind: String, CaseIterable, Identifiable {
    case text, label, digits, image, animation, pointer, arc, line, values, widget, slot, other
    var id: String { rawValue }

    static func of(_ res: XNode?) -> ElementKind {
        switch res?.tag {
        case "DataItemText": return .text
        case "DataItemImageNumber": return .digits
        case "Image", "ImageArray": return .image
        case "Sprite": return .animation
        case "DataItemPointer": return .pointer
        case "DataItemArcProgressBar": return .arc
        case "DataItemLineProgressBar": return .line
        case "DataItemImageValues": return .values
        case "Widget": return .widget
        case "Slot": return .slot
        default: return .other
        }
    }

    /// Тип із урахуванням редактора: картинка-напис показується як «Напис»
    static func of(_ res: XNode?, in p: FaceProject) -> ElementKind {
        let k = of(res)
        if k == .image, let n = res?.string("name"), p.meta.generators[n]?.kind == .label { return .label }
        return k
    }

    var title: String {
        switch self {
        case .text: return loc("Текст браслета")
        case .label: return loc("Напис")
        case .digits: return loc("Цифри")
        case .image: return loc("Зображення")
        case .animation: return loc("Анімація")
        case .pointer: return loc("Стрілка")
        case .arc: return loc("Дуга")
        case .line: return loc("Лінія")
        case .values: return loc("Значки за значенням")
        case .widget: return loc("Віджет")
        case .slot: return loc("Слот")
        case .other: return loc("Елемент")
        }
    }
}

enum ElementFactory {
    // MARK: Допоміжне

    /// Додає зображення як ресурс Image, повертає його ім'я.
    @discardableResult
    static func addImageResource(_ p: FaceProject, _ img: RGBAImage, base: String, compress: Bool = true) -> String {
        let name = p.uniqueName(base)
        let src = "\(name).png"
        p.setFile(src, img.png)
        let e = XNode("Image")
        e.set("name", name).set("src", src).set("compressMethod", compress ? "RLEReversed" : "none")
            .set("format", img.bestFormat).set("recolorEnable", bool: false)
        p.resources.kids.append(e)
        return name
    }

    /// Кадри як ImageArray.
    @discardableResult
    static func addFrames(_ p: FaceProject, _ frames: [RGBAImage], base: String) -> String {
        let name = p.uniqueName(base)
        let e = XNode("ImageArray")
        let fmt = frames.contains { $0.bestFormat == "RGB565A8" } ? "RGB565A8" : "indexed8"
        e.set("name", name).set("compressMethod", "RLEReversed").set("format", fmt).set("recolorEnable", bool: false)
        for (i, f) in frames.enumerated() {
            let src = "\(name)/\(i).png"
            p.setFile(src, f.png)
            e.add("Image").set("src", src)
        }
        p.resources.kids.append(e)
        return name
    }

    static func addLayout(_ p: FaceProject, ref: String, theme: Int, x: Int, y: Int) {
        guard let th = p.theme(theme) else { return }
        let l = XNode("Layout")
        l.set("ref", "@" + ref).set("x", int: x).set("y", int: y)
        th.kids.append(l)
    }

    // MARK: Елементи

    /// Перша картинка набору (розмір для розміщення нового шару)
    static func firstOf(_ p: FaceProject, _ arr: XNode?) -> RGBAImage? {
        guard let src = arr?.first("Image")?.string("src"), let d = p.file(src), let png = PNG.decode([UInt8](d)) else { return nil }
        return RGBAImage(w: png.w, h: png.h, px: png.rgba)
    }

    /// Новий елемент бере вже наявний набір: параметри шрифту — як у сусіда з тим самим набором
    static func copyGenFromSet(_ p: FaceProject, _ arr: String) {
        guard let a = p.resource(named: arr) else { return }
        let users = ImageSets.users(p, a)
        guard let donor = users.compactMap({ $0.string("name") }).first(where: { p.meta.generators[$0] != nil }),
              let dg = p.meta.generators[donor] else { return }
        for u in users {
            let n = u.string("name") ?? ""
            if p.meta.generators[n] == nil { var g = dg; g.unit = ""; p.meta.generators[n] = g }
        }
    }

    static func addDigits(_ p: FaceProject, source: String, gen: Generator, theme: Int, center: (Int, Int)) {
        let frames = AssetFactory.digitFrames(gen)
        let arr = addFrames(p, frames, base: "digits")
        let name = p.uniqueName(source)
        let e = XNode("DataItemImageNumber")
        e.set("name", name).set("source", source).set("ref", "@" + arr).set("totalDigits", int: 2).set("decimalDigits", int: 0)
            .set("align", "left").set("leadingZero", bool: true).set("trailingZero", bool: false).set("renderRule", "alwaysShow")
            .set("rotation", int: 0).set("decimalOffsetX", int: 0).set("space", int: 0)
        p.resources.kids.append(e)
        p.meta.generators[name] = gen
        let w = (frames.first?.w ?? 0) * 2, h = frames.first?.h ?? 0
        addLayout(p, ref: name, theme: theme, x: center.0 - w / 2, y: center.1 - h / 2)
    }

    /// Число картинками цифр. sharedArray — назва вже доданого набору цифр: тоді нові файли не створюються
    /// (години й хвилини одного шрифту беруть ті самі 10 картинок). Повертає назву набору.
    @discardableResult
    static func addDigitImages(_ p: FaceProject, source: String, images: [RGBAImage], theme: Int, center: (Int, Int), sharedArray: String? = nil) -> String? {
        guard let f0 = images.first else { return nil }
        let frames: [RGBAImage] = sharedArray != nil ? [] : images.map { img -> RGBAImage in
            guard img.w != f0.w || img.h != f0.h, let cg = img.cgImage else { return img }
            return AssetFactory.render(f0.w, f0.h) { _ in
                let u = UIImage(cgImage: cg)
                let s = min(CGFloat(f0.w) / u.size.width, CGFloat(f0.h) / u.size.height)
                let sz = CGSize(width: u.size.width * s, height: u.size.height * s)
                u.draw(in: CGRect(x: (CGFloat(f0.w) - sz.width) / 2, y: (CGFloat(f0.h) - sz.height) / 2, width: sz.width, height: sz.height))
            }
        }
        let arr = sharedArray ?? addFrames(p, frames, base: "digits")
        let name = p.uniqueName(source)
        let e = XNode("DataItemImageNumber")
        e.set("name", name).set("source", source).set("ref", "@" + arr).set("totalDigits", int: 2).set("decimalDigits", int: 0)
            .set("align", "left").set("leadingZero", bool: true).set("trailingZero", bool: false).set("renderRule", "alwaysShow")
            .set("rotation", int: 0).set("decimalOffsetX", int: 0).set("space", int: 0)
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - f0.w, y: center.1 - f0.h / 2)
        return arr
    }

    static func addImage(_ p: FaceProject, _ img: RGBAImage, theme: Int, center: (Int, Int)) {
        let name = addImageResource(p, img, base: "image")
        p.meta.generators[name] = Generator(kind: .image)
        addLayout(p, ref: name, theme: theme, x: center.0 - img.w / 2, y: center.1 - img.h / 2)
    }

    /// Напис картинкою (рядок вибраним шрифтом)
    static func addLabel(_ p: FaceProject, gen: Generator, theme: Int, center: (Int, Int)) {
        guard let img = AssetFactory.labelImage(gen) else { return }
        let name = addImageResource(p, img, base: "label")
        p.meta.generators[name] = gen
        addLayout(p, ref: name, theme: theme, x: center.0 - img.w / 2, y: center.1 - img.h / 2)
    }

    static func addAnimation(_ p: FaceProject, _ frames: [RGBAImage], interval: Int, theme: Int, center: (Int, Int)) {
        guard let f0 = frames.first else { return }
        let arr = addFrames(p, frames, base: "frames")
        let name = p.uniqueName("animation")
        let e = XNode("Sprite")
        e.set("name", name).set("ref", "@" + arr).set("interval", int: interval).set("repeatCount", int: 0)
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - f0.w / 2, y: center.1 - f0.h / 2)
    }

    static func addPointer(_ p: FaceProject, source: String, gen: Generator, theme: Int, center: (Int, Int)) {
        let img = AssetFactory.hand(length: gen.length, width: gen.width, color: gen.color)
        let ref = addImageResource(p, img, base: "hand")
        let name = p.uniqueName("pointer")
        p.meta.generators[name] = gen
        let range = PointerDefaults.range(source)
        let e = XNode("DataItemPointer")
        e.set("name", name).set("source", source).set("ref", "@" + ref).set("param", int: 1000).set("renderRule", "alwaysShow")
            .set("valueStart", int: 0).set("valueRange", int: range.0)
            .set("pivotX", int: img.w / 2).set("pivotY", int: img.h - img.w / 2)
            .set("angleStart", int: 0).set("angleRange", int: range.1)
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - img.w / 2, y: center.1 - (img.h - img.w / 2))
    }

    static func arcImage(_ g: Generator, _ c: String) -> RGBAImage {
        AssetFactory.arcSegment(radius: g.radius, width: g.width, color: c, start: g.start, range: g.range, round: g.round)
    }

    static func lineImage(_ g: Generator, _ c: String) -> (RGBAImage, CGPoint, CGPoint) {
        AssetFactory.lineSegment(length: g.length, width: g.width, color: c, angle: g.angle, round: g.round)
    }

    /// Параметри дуги/лінії з самого маніфесту (кут, кінці) — для старих проєктів і після правки XML
    static func synced(_ res: XNode, _ gen: Generator) -> Generator {
        var g = gen
        g.round = res.string("endingStyle") != "normal"
        if gen.kind == .arc { g.start = Double(res.int("angleStart")); g.range = Double(res.int("angleRange")) }
        if gen.kind == .line {
            let dx = Double(res.int("endX") - res.int("startX")), dy = Double(res.int("endY") - res.int("startY"))
            if dx != 0 || dy != 0 { g.angle = (atan2(dy, dx) * 1800 / .pi).rounded() / 10; g.length = sqrt(dx * dx + dy * dy).rounded() }
        }
        return g
    }

    /// Основні картинки елемента: те, на що посилається ref (масив чи одна картинка), або сам ресурс-картинка
    static func mainImages(_ p: FaceProject, _ res: XNode?) -> XNode? {
        guard let res else { return nil }
        if res.tag == "Image" || res.tag == "ImageArray" { return res }
        guard let r = p.resource(ref: res.string("ref")), r.tag == "Image" || r.tag == "ImageArray" else { return nil }
        return r
    }

    /// Скільки картинок намалювати шрифтом
    static func slotCount(_ p: FaceProject, _ res: XNode?) -> Int {
        guard let t = mainImages(p, res) else { return 0 }
        return t.tag == "Image" ? 1 : t.all("Image").count
    }

    static func setEnds(_ res: XNode, _ s: CGPoint, _ e: CGPoint, _ width: Double) {
        res.set("startX", int: Int(s.x.rounded())).set("startY", int: Int(s.y.rounded()))
            .set("endX", int: Int(e.x.rounded())).set("endY", int: Int(e.y.rounded())).set("barWidth", int: Int(width.rounded()))
    }

    /// Усі шари (на всіх екранах), що показують цей ресурс
    static func layouts(of res: XNode, in p: FaceProject) -> [XNode] {
        (0..<p.themes.count).flatMap { t in p.layouts(t).filter { p.element(of: $0) === res } }
    }

    /// Точка прив'язки в координатах циферблата: центр дуги або початок лінії — лишається на місці після перемальовування
    private static func anchors(_ p: FaceProject, _ res: XNode, arc: Bool) -> [(XNode, Int, Int)] {
        layouts(of: res, in: p).map { l in
            (l, Int(l.int("x")) + Int(res.int(arc ? "pivotX" : "startX")), Int(l.int("y")) + Int(res.int(arc ? "pivotY" : "startY")))
        }
    }

    private static func restore(_ keep: [(XNode, Int, Int)], _ res: XNode, arc: Bool) {
        for k in keep {
            k.0.set("x", int: k.1 - Int(res.int(arc ? "pivotX" : "startX"))).set("y", int: k.2 - Int(res.int(arc ? "pivotY" : "startY")))
        }
    }

    /// Лінія за двома кінцями в координатах циферблата (перетягування ручок, поля X1 Y1 X2 Y2)
    static func placeLine(_ p: FaceProject, res: XNode, layout: XNode, gen: Generator, from a: CGPoint, to b: CGPoint) {
        var g = gen
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        g.length = max(1, sqrt(dx * dx + dy * dy).rounded())
        g.angle = (atan2(dy, dx) * 1800 / .pi).rounded() / 10
        regenerate(p, element: res.string("name") ?? "", gen: g)
        layout.set("x", int: Int(a.x.rounded()) - Int(res.int("startX"))).set("y", int: Int(a.y.rounded()) - Int(res.int("startY")))
    }

    static func addArc(_ p: FaceProject, source: String, gen: Generator, theme: Int, center: (Int, Int)) {
        let fg = arcImage(gen, gen.color)
        let bg = arcImage(gen, gen.bgColor)
        // фон перед основною — так само, як їх упорядковує компілятор (стабільні id після розпакування)
        let bgName = addImageResource(p, bg, base: "arcBg")
        let fgName = addImageResource(p, fg, base: "arc")
        let name = p.uniqueName("arc")
        p.meta.generators[name] = gen
        let e = XNode("DataItemArcProgressBar")
        e.set("name", name).set("source", source).set("ref", "@" + fgName).set("bg", "@" + bgName)
            .set("endingStyle", gen.round ? "round" : "normal").set("renderRule", "alwaysShow").set("valueStart", int: 0).set("valueRange", int: 100)
            .set("angleStart", int: Int(gen.start.rounded())).set("angleRange", int: Int(gen.range.rounded())).set("pivotX", int: fg.w / 2).set("pivotY", int: fg.h / 2)
            .set("barRadius", int: Int(gen.radius)).set("barWidth", int: Int(gen.width))
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - fg.w / 2, y: center.1 - fg.h / 2)
    }

    static func addLine(_ p: FaceProject, source: String, gen: Generator, theme: Int, center: (Int, Int)) {
        let (fg, s, en) = lineImage(gen, gen.color)
        let bg = lineImage(gen, gen.bgColor).0
        let bgName = addImageResource(p, bg, base: "barBg")
        let fgName = addImageResource(p, fg, base: "bar")
        let name = p.uniqueName("line")
        p.meta.generators[name] = gen
        let e = XNode("DataItemLineProgressBar")
        e.set("name", name).set("source", source).set("ref", "@" + fgName).set("bg", "@" + bgName)
            .set("endingStyle", gen.round ? "round" : "normal").set("renderRule", "alwaysShow").set("valueStart", int: 0).set("valueRange", int: 100)
        setEnds(e, s, en, gen.width)
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - fg.w / 2, y: center.1 - fg.h / 2)
    }

    // MARK: Шари

    static func duplicate(_ p: FaceProject, layout: XNode, theme: Int) {
        guard let th = p.theme(theme), let res = p.resource(ref: layout.string("ref")) else { return }
        let copy = res.copy()
        let name = p.uniqueName(res.string("name") ?? "copy")
        copy.set("name", name)
        p.resources.kids.append(copy)
        let l = layout.copy()
        l.set("ref", "@" + name)
        l.set("x", int: Int(layout.int("x")) + 8).set("y", int: Int(layout.int("y")) + 8)
        th.kids.append(l)
    }

    /// Видаляє шар; ресурс прибирається, якщо більше ніде не використовується.
    static func delete(_ p: FaceProject, layout: XNode, theme: Int) {
        guard let th = p.theme(theme) else { return }
        th.kids.removeAll { $0 === layout }
        if let ref = layout.string("ref") { collect(p, ref: ref) }
    }

    /// Прибирає ресурс і все, на що лише він посилався.
    static func collect(_ p: FaceProject, ref: String) {
        guard ref.count > 1, let res = p.resource(ref: ref), !isReferenced(p, ref: ref) else { return }
        ColorVariants.removeAll(p, of: res)
        p.resources.kids.removeAll { $0 === res }
        let name = res.string("name") ?? ""
        p.meta.generators[name] = nil
        if let src = res.string("src") { p.removeFile(src) }
        for c in res.all("Image") { if let s = c.string("src") { p.removeFile(s) } }
        var refs: [String] = []
        for (k, v) in res.attrs where k != "name" && v.first == 0x40 { refs.append(String(decoding: v, as: UTF8.self)) }
        for c in res.elements { if let r = c.string("ref") { refs.append(r) } }
        for r in refs { collect(p, ref: r) }
    }

    static func isReferenced(_ p: FaceProject, ref: String) -> Bool {
        let target = Array(ref.utf8)
        func scan(_ n: XNode) -> Bool {
            for (k, v) in n.attrs where k != "name" && v == target { return true }
            return n.kids.contains { scan($0) }
        }
        return scan(p.root)
    }

    static func move(_ p: FaceProject, layout: XNode, theme: Int, to index: Int) {
        guard let th = p.theme(theme), let i = th.kids.firstIndex(where: { $0 === layout }) else { return }
        let ls = th.kids.filter { $0.tag == "Layout" }
        th.kids.remove(at: i)
        let target = max(0, min(index, ls.count - 1))
        let after = th.kids.filter { $0.tag == "Layout" }
        if target >= after.count { th.kids.append(layout) }
        else if let j = th.kids.firstIndex(where: { $0 === after[target] }) { th.kids.insert(layout, at: j) }
    }

    // MARK: Перегенерація

    /// Перегенерація картинок елемента (ім'я — ресурс, на який посилається шар) з новими параметрами.
    static func regenerate(_ p: FaceProject, element name: String, gen: Generator) {
        guard let res = p.resource(named: name) else { return }
        p.meta.generators[name] = gen
        switch gen.kind {
        case .digits:
            guard let arr = p.resource(ref: res.string("ref")) else { return }
            let frames = AssetFactory.digitFrames(gen)
            for c in arr.all("Image") { if let s = c.string("src") { p.removeFile(s) } }
            arr.kids.removeAll()
            arr.set("format", frames.contains { $0.bestFormat == "RGB565A8" } ? "RGB565A8" : "indexed8")
            let base = arr.string("name") ?? name
            for (i, f) in frames.enumerated() {
                let src = "\(base)/\(i).png"
                p.setFile(src, f.png)
                arr.add("Image").set("src", src)
            }
            // одиниця — тим самим шрифтом
            if !gen.unit.isEmpty || res.has("unitIcon") { setUnit(p, element: res, gen: gen) }
        case .texts:
            // кожна картинка елемента — свій рядок шрифтом (дні тижня, місяці, значки…); шляхи файлів лишаються
            guard let target = mainImages(p, res) else { return }
            let slots = target.tag == "Image" ? [target] : target.all("Image")
            let frames = AssetFactory.textFrames(gen, gen.texts)
            let n = min(slots.count, frames.count)
            for i in 0..<n { if let s = slots[i].string("src") { p.setFile(s, frames[i].png) } }
            if n > 0 { target.set("format", frames.prefix(n).contains { $0.bestFormat == "RGB565A8" } ? "RGB565A8" : "indexed8") }
        case .arc:
            // центр дуги лишається на місці, хоч би як змінився розмір картинки
            let keep = anchors(p, res, arc: true)
            let fg = arcImage(gen, gen.color)
            if let r = p.resource(ref: res.string("ref")) { replaceImage(p, r, fg) }
            if let b = p.resource(ref: res.string("bg")) { replaceImage(p, b, arcImage(gen, gen.bgColor)) }
            res.set("pivotX", int: fg.w / 2).set("pivotY", int: fg.h / 2).set("barRadius", int: Int(gen.radius)).set("barWidth", int: Int(gen.width))
                .set("angleStart", int: Int(gen.start.rounded())).set("angleRange", int: Int(gen.range.rounded()))
                .set("endingStyle", gen.round ? "round" : "normal")
            if res.has("indicatorRadius") { res.set("indicatorRadius", int: Int(gen.radius)) }
            restore(keep, res, arc: true)
        case .line:
            // початок лінії лишається на місці
            let keep = anchors(p, res, arc: false)
            let (fg, s, en) = lineImage(gen, gen.color)
            if let r = p.resource(ref: res.string("ref")) { replaceImage(p, r, fg) }
            if let b = p.resource(ref: res.string("bg")) { replaceImage(p, b, lineImage(gen, gen.bgColor).0) }
            setEnds(res, s, en, gen.width)
            res.set("endingStyle", gen.round ? "round" : "normal")
            restore(keep, res, arc: false)
        case .pointer:
            let img = AssetFactory.hand(length: gen.length, width: gen.width, color: gen.color)
            if let r = p.resource(ref: res.string("ref")) { replaceImage(p, r, img) }
            res.set("pivotX", int: img.w / 2).set("pivotY", int: img.h - img.w / 2)
        case .label:
            if let img = AssetFactory.labelImage(gen) { replaceImage(p, res, img) }
        default: break
        }
        // кольорові варіанти елемента — тим самим шрифтом і розміром
        ColorVariants.refresh(p, element: res)
    }

    // MARK: Одиниця біля числа

    /// Значок одиниці для числа з параметрами малювання (порожній текст — прибрати)
    static func setUnit(_ p: FaceProject, element res: XNode, gen: Generator) {
        let old = res.string("unitIcon")
        res.remove("unitIcon")
        if let old { collect(p, ref: old) }
        guard let img = AssetFactory.unitImage(gen.unit, gen) else { return }
        let name = addImageResource(p, img, base: (res.string("name") ?? "number") + "_unit")
        res.set("unitIcon", "@" + name)
    }

    // MARK: Аналоговий годинник

    /// Три стрілки (години, хвилини, секунди) і центральна крапка
    static func addAnalogClock(_ p: FaceProject, theme: Int, center: (Int, Int)) {
        addPointer(p, source: "timeHour", gen: Generator(kind: .pointer, color: "#FFFFFF", width: 9, length: 58), theme: theme, center: center)
        addPointer(p, source: "timeMinute", gen: Generator(kind: .pointer, color: "#FFFFFF", width: 6, length: 86), theme: theme, center: center)
        addPointer(p, source: "timeSecond", gen: Generator(kind: .pointer, color: "#FF9500", width: 3, length: 92), theme: theme, center: center)
        let dot = AssetFactory.render(14, 14) { ctx in
            ctx.setFillColor(AssetFactory.color("#FF9500").cgColor)
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 14, height: 14))
        }
        let name = addImageResource(p, dot, base: "clockCenter")
        addLayout(p, ref: name, theme: theme, x: center.0 - 7, y: center.1 - 7)
    }

    // MARK: Значки за значенням

    /// Картинка залежно від значення: пороги рівномірно по діапазону джерела
    static func addValues(_ p: FaceProject, source: String, images: [RGBAImage], theme: Int, center: (Int, Int), sharedArray: String? = nil) {
        guard let f0 = images.first else { return }
        let arr = sharedArray ?? addFrames(p, images.map { fit($0, w: f0.w, h: f0.h) }, base: "icons")
        let n = sharedArray.map { ImageSets.count(p.resource(named: $0)) } ?? images.count
        let name = p.uniqueName(source + "Icons")
        let e = XNode("DataItemImageValues")
        e.set("name", name).set("source", source).set("ref", "@" + arr).set("renderRule", "alwaysShow").set("rotation", int: 0)
        let (lo, hi) = valueRange(source)
        for i in 0..<n { e.add("Param").set("value", int: lo + (hi - lo) * i / max(1, n)) }
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - f0.w / 2, y: center.1 - f0.h / 2)
    }

    /// Діапазон значень джерела для порогів
    static func valueRange(_ source: String) -> (Int, Int) {
        let l = source.lowercased()
        if l.contains("heart") { return (40, 180) }
        if l.contains("hour") { return (0, 24) }
        if l.contains("minute") || l.contains("second") { return (0, 60) }
        if l.contains("week") { return (0, 7) }
        if l.contains("temperature") { return (-20, 40) }
        return (0, 100)
    }

    /// Кадр під розмір першого (кадри в наборі мають бути однакового розміру)
    static func fit(_ img: RGBAImage, w: Int, h: Int) -> RGBAImage {
        guard img.w != w || img.h != h, let cg = img.cgImage else { return img }
        let s = min(CGFloat(w) / CGFloat(img.w), CGFloat(h) / CGFloat(img.h))
        let dw = CGFloat(img.w) * s, dh = CGFloat(img.h) * s
        return AssetFactory.render(w, h) { _ in
            UIImage(cgImage: cg).draw(in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2, width: dw, height: dh))
        }
    }

    /// Нові картинки значків: пороги рівномірно по діапазону (кількість може змінитися)
    static func replaceValueImages(_ p: FaceProject, element res: XNode, images: [RGBAImage]) {
        guard let f0 = images.first else { return }
        if let old = res.string("ref") {
            res.remove("ref")
            collect(p, ref: old)
        }
        let arr = addFrames(p, images.map { fit($0, w: f0.w, h: f0.h) }, base: "icons")
        res.set("ref", "@" + arr)
        let (lo, hi) = valueRange(res.string("source") ?? "")
        res.kids.removeAll { $0.tag == "Param" }
        for i in 0..<images.count { res.add("Param").set("value", int: lo + (hi - lo) * i / max(1, images.count)) }
    }

    /// Крапка на кінці заповнення дуги (кружечок трохи ширший за шкалу)
    static func setIndicator(_ p: FaceProject, element res: XNode, on: Bool, size: Double) {
        if let old = res.string("indicatorImage") {
            res.remove("indicatorImage"); res.remove("indicatorRadius")
            collect(p, ref: old)
        }
        guard on else { return }
        let d = Swift.max(6, Int((size * 1.5).rounded()))
        let dot = AssetFactory.render(d, d) { ctx in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        }
        let name = addImageResource(p, dot, base: (res.string("name") ?? "arc") + "_dot")
        res.set("indicatorImage", "@" + name).set("indicatorRadius", int: Int(res.int("barRadius")))
    }

    /// Видаляє тему (екран) з її шарами; ресурси, що більше ніде не потрібні, прибираються
    static func deleteTheme(_ p: FaceProject, index: Int) {
        guard let th = p.theme(index), p.themes.count > 1 else { return }
        let refs = th.all("Layout").compactMap { $0.string("ref") } + [th.string("preview")].compactMap { $0 }
        p.root.kids.removeAll { $0 === th }
        for r in refs { collect(p, ref: r) }
    }

    // MARK: Дія при натисканні

    /// Обгортка «натиснув — відкрився застосунок»: Widget з одним елементом і jumpApp. Ім'я починається з tap_
    static func tapInner(_ p: FaceProject, _ r: XNode) -> XNode? {
        guard r.tag == "Widget", (r.string("name") ?? "").hasPrefix("tap_"), r.has("jumpApp"),
              let item = r.all("Item").first, r.all("Item").count == 1 else { return nil }
        return p.resource(ref: item.string("ref"))
    }

    /// Який застосунок відкривається натисканням (nil — нічого)
    static func tapApp(_ p: FaceProject, layout: XNode) -> String? {
        guard let r = p.resource(ref: layout.string("ref")), tapInner(p, r) != nil else { return nil }
        return r.string("jumpApp")
    }

    /// Задати дію натискання: елемент загортається у віджет розміру його рамки (або розгортається назад)
    static func setTapApp(_ p: FaceProject, layout: XNode, theme: Int, app: String?) {
        guard let r = p.resource(ref: layout.string("ref")) else { return }
        let lx = Int(layout.int("x")), ly = Int(layout.int("y"))
        if let inner = tapInner(p, r) {
            // розгорнути: шар знову посилається на сам елемент
            let item = r.all("Item")[0]
            layout.set("ref", "@" + (inner.string("name") ?? ""))
                .set("x", int: lx + Int(item.int("x"))).set("y", int: ly + Int(item.int("y")))
            p.resources.kids.removeAll { $0 === r }
        }
        guard let app, let el = p.resource(ref: layout.string("ref")) else { return }
        let box = FaceRenderer(p).boxes(theme: theme).first { $0.layout === layout }?.rect
            ?? CGRect(x: CGFloat(layout.int("x")), y: CGFloat(layout.int("y")), width: 40, height: 40)
        let bx = Int(box.minX.rounded(.down)), by = Int(box.minY.rounded(.down))
        let w = Swift.max(8, Int(box.width.rounded(.up))), h = Swift.max(8, Int(box.height.rounded(.up)))
        let name = p.uniqueName("tap_" + (el.string("name") ?? "element"))
        let wg = XNode("Widget")
        wg.set("name", name).set("w", int: w).set("h", int: h).set("jumpApp", app)
        wg.add("Item").set("ref", "@" + (el.string("name") ?? "")).set("x", int: Int(layout.int("x")) - bx).set("y", int: Int(layout.int("y")) - by)
        p.resources.kids.append(wg)
        layout.set("ref", "@" + name).set("x", int: bx).set("y", int: by)
    }

    /// Назви застосунків для меню
    static let appTitles: [String: String] = [
        "heartrate": "Пульс", "sleep": "Сон", "SpO2": "Кисень у крові", "sport": "Тренування", "activities": "Активність",
        "media": "Музика", "settings": "Налаштування", "weather": "Погода", "timer": "Таймер", "alarm": "Будильник",
        "chronograph": "Секундомір", "flashlight": "Ліхтарик", "findPhone": "Пошук телефону", "pressure": "Стрес",
        "breath": "Дихання", "calendar": "Календар", "compass": "Компас", "worldclock": "Світовий час", "todo": "Справи",
        "womenHealth": "Жіноче здоров'я", "remoteCamera": "Камера телефона", "phone": "Дзвінки", "contact": "Контакти",
        "recorder": "Диктофон", "barometer": "Барометр", "temperature": "Температура", "sms": "Повідомлення",
        "nfcCard": "Картки NFC", "sportsRecord": "Записи тренувань", "vitalityValue": "Бали активності",
        "trainingStatus": "Стан тренованості", "tomato": "Помодоро", "perpetualcalendar": "Календар",
        "navigation": "Навігація", "voiceAssistant": "Голосовий помічник", "share": "Поділитися", "sportsCourse": "Курси тренувань",
    ]

    static func replaceImage(_ p: FaceProject, _ res: XNode, _ img: RGBAImage) {
        let src = res.string("src") ?? "\(res.string("name") ?? "image").png"
        p.setFile(src, img.png)
        res.set("src", src).set("format", img.bestFormat)
    }
}

enum PointerDefaults {
    /// (діапазон значень, кут) для стрілок годинника
    static func range(_ source: String) -> (Int, Int) {
        if source.contains("Hour") { return (24, 720) }
        if source.contains("Minute") || source.contains("Second") { return (60, 360) }
        return (100, 360)
    }
}
