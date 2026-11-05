// SPDX-License-Identifier: MIT
// Кольорові варіанти циферблата (як у Mi Fitness: користувач вибирає колір циферблата на браслеті).
//
// Формат маніфесту:
//  • <Watchface colorGroupTable="#C0,#C1,…"> — кольори; перший — основний вигляд;
//  • <Theme colorGroup="#C0,#C1,…"> — які з них доступні в темі (у нас — усі);
//  • картинка елемента (Image / ImageArray) без colorGroup — основний вигляд, а її варіанти — елементи з тим самим
//    іменем і colorGroup="#Ci" зі своїми файлами. Елементи без варіантів браслет показує однаково в усіх кольорах.
//
// Варіант можна зробити не для кожного елемента: цифри, дуги, лінії й стрілки, створені редактором, малюються
// заново потрібним кольором; одноколірні картинки (наприклад, білі значки) перефарбовуються; багатоколірні
// картинки й текст (його малює браслет своїм шрифтом) — ні.

import Foundation
import UIKit
import FaceCompiler

enum ColorVariants {
    /// Найбільше кольорів (індекс варіанта займає 5 біт; на практиці в циферблатах до 10)
    static let maxColors = 10

    enum Availability: Equatable {
        /// Малюється редактором (цифри, дуга, лінія, стрілка) — у варіанті просто інший колір
        case generator
        /// Одноколірна картинка — перефарбовується
        case tint
        /// Недоступно, з поясненням
        case unavailable(String)

        var isAvailable: Bool { if case .unavailable = self { return false }; return true }
    }

    // MARK: Кольори

    /// Кольори циферблата («#RRGGBB»); порожньо — варіантів немає
    static func colors(_ p: FaceProject) -> [String] {
        guard let raw = p.root.string("colorGroupTable") else { return [] }
        return raw.split(separator: ",").map { normalize(String($0)) }.filter { !$0.isEmpty }
    }

    static func isEnabled(_ p: FaceProject) -> Bool { colors(p).count > 1 }

    static func normalize(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        let hex = t.hasPrefix("#") ? String(t.dropFirst()) : t.hasPrefix("0X") ? String(t.dropFirst(2)) : t
        guard hex.count == 6, Int(hex, radix: 16) != nil else { return "" }
        return "#" + hex
    }

    /// Вмикає варіанти: основний колір і ще один для початку
    static func enable(_ p: FaceProject, base: String, first: String) {
        write(p, [normalize(base), normalize(first)])
    }

    /// Нові кольори: таблиці оновлюються, варіанти всіх увімкнених елементів малюються заново
    /// (варіанти прибраних кольорів видаляються). Перший колір — основний вигляд.
    static func setColors(_ p: FaceProject, _ list: [String]) {
        let old = colors(p)
        let new = Array(list.map(normalize).filter { !$0.isEmpty }.prefix(maxColors))
        let enabled = targetsWithVariants(p, colors: old)
        // картинки, які редактор може намалювати заново, — малюються; готові варіанти з чужих циферблатів
        // лишаються для кольорів, що лишились у списку
        let redraw = enabled.filter { canRedraw(p, $0) }
        for t in redraw { removeVariants(p, of: t) }
        for t in enabled where !redraw.contains(where: { $0 === t }) {
            for v in variants(p, of: t) where !new.dropFirst().contains(normalize(v.string("colorGroup") ?? "")) {
                drop(p, v)
            }
        }
        write(p, new)
        guard new.count > 1 else { return }
        for t in redraw { rebuild(p, target: t) }
    }

    /// Вимикає варіанти повністю: прибираються таблиці й усі картинки варіантів
    static func disable(_ p: FaceProject) {
        let cols = colors(p)
        for t in targetsWithVariants(p, colors: cols) { removeVariants(p, of: t) }
        p.root.remove("colorGroupTable")
        for th in p.themes { th.remove("colorGroup"); th.remove("colorGroupTable") }
        for r in p.resources.elements where r.tag == "Image" || r.tag == "ImageArray" { r.remove("colorGroup") }
    }

    /// Таблиці тем за поточними кольорами (циферблати, де кольори вмикали ще для «Завжди на екрані»)
    static func syncThemes(_ p: FaceProject) {
        let c = colors(p)
        if c.count > 1 { write(p, c) }
    }

    private static func write(_ p: FaceProject, _ list: [String]) {
        guard list.count > 1 else { disable(p); return }
        let joined = list.joined(separator: ",")
        p.root.set("colorGroupTable", joined)
        // кольори в усіх темах, як у робочих циферблатах (експеримент без кольорів у «Завжди на екрані»
        // разом із пропуском копій перезавантажував браслет)
        for th in p.themes { th.set("colorGroup", joined) }
    }

    // MARK: Пошук

    /// Версія картинки `base` для кольору з індексом `index` (nil — варіанта немає)
    static func variant(_ p: FaceProject, of base: XNode, index: Int) -> XNode? {
        let cols = colors(p)
        guard index > 0, index < cols.count, let name = base.string("name") else { return nil }
        let c = cols[index]
        return p.resources.elements.first {
            $0.tag == base.tag && $0.string("name") == name && normalize($0.string("colorGroup") ?? "") == c
        }
    }

    /// Усі варіанти картинки (крім основної)
    static func variants(_ p: FaceProject, of base: XNode) -> [XNode] {
        guard let name = base.string("name") else { return [] }
        let first = colors(p).first
        return p.resources.elements.filter {
            $0 !== base && $0.tag == base.tag && $0.string("name") == name
                && $0.has("colorGroup") && normalize($0.string("colorGroup") ?? "") != first
        }
    }

    private static func targetsWithVariants(_ p: FaceProject, colors: [String]) -> [XNode] {
        var seen = Set<String>()
        var out: [XNode] = []
        for r in p.resources.elements where (r.tag == "Image" || r.tag == "ImageArray") {
            guard let name = r.string("name"), !seen.contains(name) else { continue }
            seen.insert(name)
            if let base = p.resource(named: name), !variants(p, of: base).isEmpty { out.append(base) }
        }
        return out
    }

    // MARK: Елемент

    /// Ресурс елемента (на який посилається шар) → картинки, що міняють колір.
    /// Для дуги й лінії — лише заповнення, фон шкали лишається.
    static func targets(_ p: FaceProject, element res: XNode) -> [XNode] {
        switch res.tag {
        case "Image", "ImageArray": return [res]
        case "DataItemImageNumber", "DataItemImageValues", "Sprite", "DataItemPointer",
             "DataItemArcProgressBar", "DataItemLineProgressBar":
            return p.resource(ref: res.string("ref")).map { [$0] } ?? []
        default: return []
        }
    }

    static func availability(_ p: FaceProject, element res: XNode) -> Availability {
        switch res.tag {
        case "DataItemText":
            return .unavailable(loc("Текст малює сам браслет своїм шрифтом — кольорових варіантів для нього немає."))
        case "Widget", "Slot":
            return .unavailable(loc("Віджети показують дані застосунків — кольорових варіантів для них немає."))
        default: break
        }
        let ts = targets(p, element: res)
        guard !ts.isEmpty else { return .unavailable(loc("Для цього елемента кольорових варіантів немає.")) }
        if let g = generator(p, element: res), g.kind != .image, g.kind != .frames { return .generator }
        for t in ts where !frames(p, t).allSatisfy({ tintBase($0) != nil }) {
            return .unavailable(loc("Картинка багатоколірна — перефарбувати її в інший колір не вийде."))
        }
        return .tint
    }

    /// Чи змінюється елемент разом із кольором циферблата
    static func isOn(_ p: FaceProject, element res: XNode) -> Bool {
        targets(p, element: res).contains { !variants(p, of: $0).isEmpty }
    }

    /// Увімкнути або вимкнути варіанти для елемента
    static func set(_ p: FaceProject, element res: XNode, on: Bool) {
        for t in targets(p, element: res) {
            if on { rebuild(p, target: t, element: res) } else { removeVariants(p, of: t) }
        }
    }

    /// Після зміни картинок елемента (шрифт, розмір, нове фото) — варіанти малюються заново
    static func refresh(_ p: FaceProject, element res: XNode) {
        guard isEnabled(p), isOn(p, element: res) else { return }
        if availability(p, element: res).isAvailable { set(p, element: res, on: true) } else { set(p, element: res, on: false) }
    }

    // MARK: Малювання варіантів

    private static func generator(_ p: FaceProject, element res: XNode) -> Generator? {
        p.meta.generators[res.string("name") ?? ""]
    }

    /// Елемент, якому належить картинка (щоб знайти його параметри малювання)
    private static func owner(_ p: FaceProject, of target: XNode) -> XNode? {
        guard let name = target.string("name") else { return nil }
        let ref = "@" + name
        return p.resources.elements.first { $0.string("ref") == ref && p.meta.generators[$0.string("name") ?? ""] != nil }
    }

    /// Прибирає всі варіанти картинки (коли саму картинку видаляють)
    static func removeAll(_ p: FaceProject, of base: XNode) { removeVariants(p, of: base) }

    private static func removeVariants(_ p: FaceProject, of base: XNode) {
        for v in variants(p, of: base) { drop(p, v) }
    }

    private static func drop(_ p: FaceProject, _ v: XNode) {
        if let s = v.string("src") { p.removeFile(s) }
        for i in v.all("Image") { if let s = i.string("src") { p.removeFile(s) } }
        p.resources.kids.removeAll { $0 === v }
    }

    /// Чи може редактор сам намалювати варіанти картинки (параметри малювання або одноколірна)
    private static func canRedraw(_ p: FaceProject, _ base: XNode) -> Bool {
        if let el = owner(p, of: base), let g = generator(p, element: el), g.kind != .image, g.kind != .frames { return true }
        let fr = frames(p, base)
        return !fr.isEmpty && fr.allSatisfy { tintBase($0) != nil }
    }

    /// Малює варіанти картинки для всіх кольорів, крім основного (старі прибираються)
    private static func rebuild(_ p: FaceProject, target base: XNode, element: XNode? = nil) {
        removeVariants(p, of: base)
        let cols = colors(p)
        guard cols.count > 1, let name = base.string("name") else { return }
        let el = element ?? owner(p, of: base)
        let gen = el.flatMap { generator(p, element: $0) }
        let src = frames(p, base)
        guard !src.isEmpty else { return }
        // нові вузли — одразу після основного й попередніх варіантів
        var insertAt = (p.resources.kids.firstIndex { $0 === base } ?? p.resources.kids.count - 1) + 1
        for (i, c) in cols.enumerated() where i > 0 {
            var images: [RGBAImage] = []
            if let gen, gen.kind != .image, gen.kind != .frames {
                var g = gen; g.color = c
                switch gen.kind {
                case .digits: images = AssetFactory.digitFrames(g)
                case .arc: images = [AssetFactory.ring(radius: g.radius, width: g.width, color: c)]
                case .line: images = [AssetFactory.bar(length: g.length, width: g.width, color: c)]
                case .pointer: images = [AssetFactory.hand(length: g.length, width: g.width, color: c)]
                default: images = []
                }
            } else {
                images = src.compactMap { tint($0, to: c) }
            }
            guard images.count == src.count || base.tag == "ImageArray", !images.isEmpty else { continue }
            let tag = c.dropFirst().lowercased()
            let v = XNode(base.tag)
            v.set("name", name).set("compressMethod", base.string("compressMethod") ?? "RLEReversed")
            if base.tag == "Image", let img = images.first {
                let file = "\(name)_\(tag).png"
                p.setFile(file, img.png)
                v.set("src", file).set("format", img.bestFormat)
            } else {
                v.set("format", images.contains { $0.bestFormat == "RGB565A8" } ? "RGB565A8" : "indexed8")
            }
            v.set("recolorEnable", bool: false).set("colorGroup", c)
            if base.tag == "ImageArray" {
                for (k, img) in images.enumerated() {
                    let file = "\(name)_\(tag)/\(k).png"
                    p.setFile(file, img.png)
                    v.add("Image").set("src", file)
                }
            }
            p.resources.kids.insert(v, at: min(insertAt, p.resources.kids.count))
            insertAt += 1
        }
    }

    /// Кадри картинки (Image — один)
    private static func frames(_ p: FaceProject, _ res: XNode) -> [RGBAImage] {
        let srcs = res.tag == "Image" ? [res.string("src")].compactMap { $0 } : res.all("Image").compactMap { $0.string("src") }
        return srcs.compactMap { s in
            guard let d = p.file(s), let png = PNG.decode([UInt8](d)) else { return nil }
            return RGBAImage(w: png.w, h: png.h, px: png.rgba)
        }
    }

    // MARK: Перефарбування

    /// Колір одноколірної картинки (найяскравіший піксель), якщо всі видимі пікселі — його відтінки; інакше nil
    private static func tintBase(_ img: RGBAImage) -> (Int, Int, Int)? {
        let px = img.px
        var best = (0, 0, 0), bestL = -1
        var i = 0
        while i < px.count {
            if px[i + 3] > 32 {
                let l = Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2])
                if l > bestL { bestL = l; best = (Int(px[i]), Int(px[i + 1]), Int(px[i + 2])) }
            }
            i += 4
        }
        guard bestL > 30 else { return nil }   // порожня або майже чорна картинка
        i = 0
        while i < px.count {
            if px[i + 3] > 32 {
                // піксель ≈ k × базовий колір (допуск на згладжування)
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                let k = Double(r + g + b) / Double(bestL)
                if abs(Double(best.0) * k - Double(r)) > 28 || abs(Double(best.1) * k - Double(g)) > 28
                    || abs(Double(best.2) * k - Double(b)) > 28 { return nil }
            }
            i += 4
        }
        return best
    }

    /// Перефарбовує одноколірну картинку: відтінок → новий колір тієї ж яскравості відносно базового
    static func tint(_ img: RGBAImage, to hex: String) -> RGBAImage? {
        guard let base = tintBase(img) else { return nil }
        let c = AssetFactory.color(hex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let baseL = Double(base.0 + base.1 + base.2)
        var out = img.px
        var i = 0
        while i < out.count {
            if out[i + 3] > 0 {
                let k = min(1, Double(Int(out[i]) + Int(out[i + 1]) + Int(out[i + 2])) / baseL)
                out[i] = UInt8(min(255, (Double(r) * 255 * k).rounded()))
                out[i + 1] = UInt8(min(255, (Double(g) * 255 * k).rounded()))
                out[i + 2] = UInt8(min(255, (Double(b) * 255 * k).rounded()))
            }
            i += 4
        }
        return RGBAImage(w: img.w, h: img.h, px: out)
    }
}
