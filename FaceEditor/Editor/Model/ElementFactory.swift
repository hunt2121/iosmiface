// SPDX-License-Identifier: MIT
// Створення, копіювання й видалення елементів циферблата (ресурс у <Resources> + <Layout> у темі),
// а також перегенерація картинок згенерованих елементів.

import Foundation
import FaceCompiler

enum ElementKind: String, CaseIterable, Identifiable {
    case text, digits, image, animation, pointer, arc, line, values, widget, slot, other
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

    var title: String {
        switch self {
        case .text: return loc("Текст")
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

    static func addText(_ p: FaceProject, string: String, sources: [String], theme: Int, center: (Int, Int), color: String) {
        let name = p.uniqueName("text")
        let e = XNode("DataItemText")
        let w = 160, h = 30
        e.set("name", name).set("color", color).set("opacity", int: 100).set("fontId", "misans").set("fontWeight", "bold")
            .set("letterSpace", int: 0).set("align", "center").set("longMode", "clip").set("style", "normal")
            .set("lineSpace", int: 0).set("w", int: w).set("h", int: h).set("rotation", int: 0).set("string", string)
        for s in sources { e.add("Content").set("source", s) }
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - w / 2, y: center.1 - h / 2)
    }

    static func addImage(_ p: FaceProject, _ img: RGBAImage, theme: Int, center: (Int, Int)) {
        let name = addImageResource(p, img, base: "image")
        p.meta.generators[name] = Generator(kind: .image)
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

    static func addArc(_ p: FaceProject, source: String, gen: Generator, theme: Int, center: (Int, Int)) {
        let fg = AssetFactory.ring(radius: gen.radius, width: gen.width, color: gen.color)
        let bg = AssetFactory.ring(radius: gen.radius, width: gen.width, color: gen.bgColor)
        // фон перед основною — так само, як їх упорядковує компілятор (стабільні id після розпакування)
        let bgName = addImageResource(p, bg, base: "arcBg")
        let fgName = addImageResource(p, fg, base: "arc")
        let name = p.uniqueName("arc")
        p.meta.generators[name] = gen
        let e = XNode("DataItemArcProgressBar")
        e.set("name", name).set("source", source).set("ref", "@" + fgName).set("bg", "@" + bgName)
            .set("endingStyle", "round").set("renderRule", "alwaysShow").set("valueStart", int: 0).set("valueRange", int: 100)
            .set("angleStart", int: 220).set("angleRange", int: 280).set("pivotX", int: fg.w / 2).set("pivotY", int: fg.h / 2)
            .set("barRadius", int: Int(gen.radius)).set("barWidth", int: Int(gen.width))
        p.resources.kids.append(e)
        addLayout(p, ref: name, theme: theme, x: center.0 - fg.w / 2, y: center.1 - fg.h / 2)
    }

    static func addLine(_ p: FaceProject, source: String, gen: Generator, theme: Int, center: (Int, Int)) {
        let fg = AssetFactory.bar(length: gen.length, width: gen.width, color: gen.color)
        let bg = AssetFactory.bar(length: gen.length, width: gen.width, color: gen.bgColor)
        let bgName = addImageResource(p, bg, base: "barBg")
        let fgName = addImageResource(p, fg, base: "bar")
        let name = p.uniqueName("line")
        p.meta.generators[name] = gen
        let e = XNode("DataItemLineProgressBar")
        e.set("name", name).set("source", source).set("ref", "@" + fgName).set("bg", "@" + bgName)
            .set("endingStyle", "round").set("renderRule", "alwaysShow").set("valueStart", int: 0).set("valueRange", int: 100)
            .set("startX", int: 0).set("startY", int: fg.h / 2).set("endX", int: fg.w).set("endY", int: fg.h / 2).set("barWidth", int: fg.h)
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
        case .arc:
            let fg = AssetFactory.ring(radius: gen.radius, width: gen.width, color: gen.color)
            if let r = p.resource(ref: res.string("ref")) { replaceImage(p, r, fg) }
            if let b = p.resource(ref: res.string("bg")) { replaceImage(p, b, AssetFactory.ring(radius: gen.radius, width: gen.width, color: gen.bgColor)) }
            res.set("pivotX", int: fg.w / 2).set("pivotY", int: fg.h / 2).set("barRadius", int: Int(gen.radius)).set("barWidth", int: Int(gen.width))
        case .line:
            let fg = AssetFactory.bar(length: gen.length, width: gen.width, color: gen.color)
            if let r = p.resource(ref: res.string("ref")) { replaceImage(p, r, fg) }
            if let b = p.resource(ref: res.string("bg")) { replaceImage(p, b, AssetFactory.bar(length: gen.length, width: gen.width, color: gen.bgColor)) }
            res.set("startX", int: 0).set("startY", int: fg.h / 2).set("endX", int: fg.w).set("endY", int: fg.h / 2).set("barWidth", int: fg.h)
        case .pointer:
            let img = AssetFactory.hand(length: gen.length, width: gen.width, color: gen.color)
            if let r = p.resource(ref: res.string("ref")) { replaceImage(p, r, img) }
            res.set("pivotX", int: img.w / 2).set("pivotY", int: img.h - img.w / 2)
        default: break
        }
        // кольорові варіанти елемента — тим самим шрифтом і розміром
        ColorVariants.refresh(p, element: res)
    }

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
