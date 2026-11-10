// SPDX-License-Identifier: MIT
// Віджети (кілька шарів одним блоком: розташування, вирівнювання, проміжок, дія при натисканні)
// і слоти (місце, де віджет вибирають на браслеті). Формат — як в офіційних циферблатах; так само, як у Windows.

import UIKit
import FaceCompiler

enum WidgetSlots {
    // MARK: Який віджет слота показувати в редакторі (лише в пам'яті)

    private static var shownMap: [String: Int] = [:]
    static func shown(_ p: FaceProject, _ slot: XNode) -> Int { shownMap[p.id + "/" + (slot.string("name") ?? "")] ?? 0 }
    static func show(_ p: FaceProject, _ slot: XNode, _ i: Int) { shownMap[p.id + "/" + (slot.string("name") ?? "")] = i }

    // MARK: Віджет

    /// Віджет, який користувач бачить як віджет (не службова обгортка «натиснув — відкрився застосунок»)
    static func isUserWidget(_ p: FaceProject, _ r: XNode?) -> Bool {
        guard let r, r.tag == "Widget" else { return false }
        return ElementFactory.tapInner(p, r) == nil
    }

    /// row / column / free
    static func arrange(_ w: XNode) -> String {
        let d = w.string("flex_direction")
        return d == "row" || d == "column" ? d! : "free"
    }

    /// start / center / end — по горизонталі
    static func align(_ w: XNode) -> String {
        let v = w.string(arrange(w) == "column" ? "align_items" : "justify_content") ?? "flex-start"
        return v == "center" ? "center" : v == "flex-end" ? "end" : "start"
    }

    static func gap(_ w: XNode) -> Int { Int(w.int("gap")) }

    private static func flex(_ a: String) -> String { a == "center" ? "center" : a == "end" ? "flex-end" : "flex-start" }

    static func setLayout(_ p: FaceProject, _ w: XNode, arrange a: String, align al: String, gap g: Int, layout: XNode? = nil) {
        if a == "free" {
            // вільно: кожен елемент лишається там, де стояв
            let offs = FaceRenderer(p).widgetOffsets(w)
            for (i, it) in w.all("Item").enumerated() { it.set("x", int: Int(offs[i].x.rounded())).set("y", int: Int(offs[i].y.rounded())) }
            for k in ["flex_direction", "justify_content", "align_content", "align_items", "gap"] { w.remove(k) }
        } else {
            w.set("flex_direction", a)
            if a == "row" { w.set("justify_content", flex(al)).set("align_items", "center") }
            else { w.set("align_items", flex(al)).set("justify_content", "center") }
            w.set("align_content", "center").set("gap", int: max(0, g))
            for it in w.all("Item") { it.set("x", int: 0).set("y", int: 0) }
        }
        fit(p, w, layout: layout)
    }

    /// Розмір віджета: щонайменше вміст; у слоті — не менший за той, що був
    /// Запас окантовки навколо видимого вмісту, px
    static let defaultPad = 7

    /// Запас навколо вмісту для віджета: налаштування рамки його слота (або типовий)
    static func pad(_ p: FaceProject, _ w: XNode) -> Int {
        for s in slotsOf(p, w) { if let f = p.meta.slotFrames[s.string("name") ?? ""] { return f.pad } }
        return defaultPad
    }

    static func isManual(_ p: FaceProject, _ w: XNode) -> Bool { p.meta.manualSize.contains(w.string("name") ?? "") }

    /// Розмір віджета задано вручну — картинки з прозорими краями не впливають на область
    static func setSize(_ p: FaceProject, _ w: XNode, width: Int, height: Int) {
        p.meta.manualSize.insert(w.string("name") ?? "")
        w.set("w", int: min(max(width, 8), 2000)).set("h", int: min(max(height, 8), 2000))
    }

    /// Повернути розмір за вмістом (за видимими пікселями). У слоті — один розмір для всіх його віджетів,
    /// слот зсувається в лівий верхній кут вмісту
    static func setAuto(_ p: FaceProject, _ w: XNode, layout: XNode? = nil) {
        p.meta.manualSize.remove(w.string("name") ?? "")
        fit(p, w, layout: layout, shrink: true)
    }

    static func setAutoSlot(_ p: FaceProject, _ ws: [XNode], layout: XNode) {
        let r = FaceRenderer(p)
        for w in ws { p.meta.manualSize.remove(w.string("name") ?? ""); if arrange(w) == "free" { trimGauges(p, w) } }
        var union = CGRect.null
        for w in ws {
            var b = CGRect.null
            if arrange(w) == "free" {
                for it in w.all("Item") {
                    guard let c = p.resource(ref: it.string("ref")), let m = r.visibleBounds(c) else { continue }
                    b = b.union(m.offsetBy(dx: CGFloat(it.int("x")), dy: CGFloat(it.int("y"))))
                }
            } else {
                let (ow, oh) = (w.int("w"), w.int("h")); w.remove("w"); w.remove("h")
                b = r.visibleBounds(w) ?? .null
                w.set("w", int: Int(ow)).set("h", int: Int(oh))
            }
            union = union.union(b)
        }
        guard !union.isNull else { return }
        let pd = ws.first.map { pad(p, $0) } ?? defaultPad
        let dx = Int(union.minX.rounded(.down)) - pd, dy = Int(union.minY.rounded(.down)) - pd
        let cw = max(8, Int(union.maxX.rounded(.up)) + pd - dx), ch = max(8, Int(union.maxY.rounded(.up)) + pd - dy)
        for w in ws {
            if arrange(w) == "free" { for it in w.all("Item") { it.set("x", int: Int(it.int("x")) - dx).set("y", int: Int(it.int("y")) - dy) } }
            w.set("w", int: cw).set("h", int: ch)
        }
        layout.set("x", int: Int(layout.int("x")) + dx).set("y", int: Int(layout.int("y")) + dy)
    }

    /// Дуга у віджеті: картинки (передній план, фон, усі кольорові варіанти) фізично обрізаються по видимих пікселях,
    /// а позиція елемента й центр дуги (pivot) перераховуються — на екрані дуга лишається на тому самому місці.
    /// Так елемент не виступає за область віджета, і зверху не лишається порожнього відступу.
    static func trimGauges(_ p: FaceProject, _ w: XNode) {
        for it in w.all("Item") {
            guard let res = p.resource(ref: it.string("ref")), res.tag == "DataItemArcProgressBar",
                  let fgRef = res.string("ref"), fgRef.hasPrefix("@") else { continue }
            let bgRef = res.string("bg")
            func images(_ ref: String?) -> [XNode] {
                guard let ref, ref.hasPrefix("@") else { return [] }
                return p.resources.elements.filter { $0.tag == "Image" && "@" + ($0.string("name") ?? "") == ref }
            }
            let fg = images(fgRef), bg = images(bgRef)
            // картинки, якими користується ще хтось інший, не чіпаємо
            let others = p.resources.elements.filter { $0 !== res && ($0.string("ref") == fgRef || $0.string("bg") == fgRef || (bgRef != nil && ($0.string("ref") == bgRef || $0.string("bg") == bgRef))) }
            guard !fg.isEmpty, others.isEmpty else { continue }
            func decode(_ n: XNode?) -> CGImage? {
                guard let src = n?.string("src"), let d = p.file(src), let u = UIImage(data: d) else { return nil }
                return u.cgImage
            }
            var box = CGRect.null
            for n in [fg.first, bg.first] {
                guard let cg = decode(n), let b = opaqueBounds(cg) else { continue }
                box = box.union(b)
            }
            guard !box.isNull, let base = decode(fg.first) else { continue }
            let cx = Int(box.minX), cy = Int(box.minY)
            if cx == 0, cy == 0, Int(box.width) == base.width, Int(box.height) == base.height { continue }
            for n in fg + bg {
                guard let src = n.string("src"), let cg = decode(n) else { continue }
                let r = CGRect(x: 0, y: 0, width: cg.width, height: cg.height).intersection(box)
                guard !r.isNull, let c = cg.cropping(to: r), let png = UIImage(cgImage: c).pngData() else { continue }
                p.setFile(src, png)
            }
            res.set("pivotX", int: Int(res.int("pivotX")) - cx).set("pivotY", int: Int(res.int("pivotY")) - cy)
            it.set("x", int: Int(it.int("x")) + cx).set("y", int: Int(it.int("y")) + cy)
        }
    }

    private static func opaqueBounds(_ cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 12 {
            if x < minX { minX = x }; if x > maxX { maxX = x }; if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func fit(_ p: FaceProject, _ w: XNode, layout: XNode? = nil, shrink: Bool = false) {
        if isManual(p, w) { return }
        if arrange(w) == "free", !w.all("Item").isEmpty { wrapFree(p, w, layout: layout, shrink: shrink); return }
        let inSlot = !shrink && !slotsOf(p, w).isEmpty
        let oldW = Int(w.int("w")), oldH = Int(w.int("h"))
        w.remove("w"); w.remove("h")
        let box = FaceRenderer(p).visibleBounds(w) ?? CGRect(x: 0, y: 0, width: 40, height: 30)
        let pd = pad(p, w)
        let cw = max(8, Int(box.maxX.rounded(.up)) + 2 * pd), ch = max(8, Int(box.maxY.rounded(.up)) + 2 * pd)
        w.set("w", int: max(cw, inSlot ? oldW : 0)).set("h", int: max(ch, inSlot ? oldH : 0))
    }

    /// Вільне розташування: область віджета щільно обгортає його елементи. Якщо віджет стоїть окремим шаром,
    /// шар зсувається в лівий верхній кут елементів; у слоті місце слота лишається, елементи зсуваються всередині.
    static func wrapFree(_ p: FaceProject, _ w: XNode, layout: XNode?, shrink: Bool = false) {
        trimGauges(p, w)
        let r = FaceRenderer(p)
        var box = CGRect.null
        for it in w.all("Item") {
            guard let c = p.resource(ref: it.string("ref")), let m = r.visibleBounds(c) else { continue }
            box = box.union(m.offsetBy(dx: CGFloat(it.int("x")), dy: CGFloat(it.int("y"))))
        }
        guard !box.isNull else { return }
        let inSlot = !shrink && layout == nil && !slotsOf(p, w).isEmpty
        let pd = pad(p, w)
        var dx = Int(box.minX.rounded(.down)) - pd, dy = Int(box.minY.rounded(.down)) - pd
        if layout == nil { dx = min(0, dx); dy = min(0, dy) }
        for it in w.all("Item") { it.set("x", int: Int(it.int("x")) - dx).set("y", int: Int(it.int("y")) - dy) }
        if let l = layout { l.set("x", int: Int(l.int("x")) + dx).set("y", int: Int(l.int("y")) + dy) }
        let cw = max(8, Int(box.maxX.rounded(.up)) + pd - dx), ch = max(8, Int(box.maxY.rounded(.up)) + pd - dy)
        w.set("w", int: max(cw, inSlot ? Int(w.int("w")) : 0)).set("h", int: max(ch, inSlot ? Int(w.int("h")) : 0))
    }

    @discardableResult
    static func newWidget(_ p: FaceProject, title: String, w: Int = 80, h: Int = 30) -> XNode {
        let x = XNode("Widget")
        x.set("name", p.uniqueName("widget")).set("widgetName", title).set("groupType", "general").set("w", int: w).set("h", int: h)
            .set("flex_direction", "row").set("justify_content", "center").set("align_content", "center").set("align_items", "center").set("gap", int: 4)
        p.resources.kids.append(x)
        return x
    }

    static func addWidget(_ p: FaceProject, theme: Int, center: (Int, Int), title: String) {
        let w = newWidget(p, title: title)
        ElementFactory.addLayout(p, ref: w.string("name") ?? "", theme: theme, x: center.0 - 40, y: center.1 - 15)
    }

    /// Шар екрана переходить у віджет. Перший шар порожнього віджета робить розташування «вільно»:
    /// елемент лишається на місці, а область віджета стає точно навколо нього.
    static func addToWidget(_ p: FaceProject, _ w: XNode, origin: CGPoint, layout: XNode, theme: Int, own: XNode? = nil, slotLayout: XNode? = nil) {
        guard let th = p.theme(theme), let r = layout.string("ref") else { return }
        if w.all("Item").isEmpty {
            for k in ["flex_direction", "justify_content", "align_content", "align_items", "gap"] { w.remove(k) }
        }
        let it = w.add("Item").set("ref", r)
        if arrange(w) == "free" { it.set("x", int: Int(CGFloat(layout.int("x")) - origin.x)).set("y", int: Int(CGFloat(layout.int("y")) - origin.y)) }
        else { it.set("x", int: 0).set("y", int: 0) }
        th.kids.removeAll { $0 === layout }
        // віджет у слоті: область росте навколо вмісту, а слот зсувається разом із нею; елементи інших віджетів слота лишаються на місці
        let target = own ?? slotLayout
        let before = target.map { (Int($0.int("x")), Int($0.int("y"))) }
        fit(p, w, layout: target)
        if own == nil, let t = target, let before {
            let dx = Int(t.int("x")) - before.0, dy = Int(t.int("y")) - before.1
            if dx != 0 || dy != 0 {
                for s in slotsOf(p, w) {
                    for o in widgets(p, s) where o !== w && arrange(o) == "free" {
                        for i in o.all("Item") { i.set("x", int: Int(i.int("x")) - dx).set("y", int: Int(i.int("y")) - dy) }
                    }
                }
            }
        }
    }

    /// Елемент віджета знову стає окремим шаром — на тому самому місці
    static func takeOut(_ p: FaceProject, _ w: XNode, index: Int, origin: CGPoint, theme: Int, own: XNode? = nil) {
        let items = w.all("Item")
        guard index >= 0, index < items.count else { return }
        let offs = FaceRenderer(p).widgetOffsets(w)
        let r = items[index].string("ref")
        w.kids.removeAll { $0 === items[index] }
        if let r { ElementFactory.addLayout(p, ref: String(r.dropFirst()), theme: theme, x: Int((origin.x + offs[index].x).rounded()), y: Int((origin.y + offs[index].y).rounded())) }
        fit(p, w, layout: own)
    }

    /// Розгрупувати: усі елементи — окремими шарами на своїх місцях, віджет прибирається
    static func ungroup(_ p: FaceProject, layout: XNode, theme: Int) {
        guard let w = p.element(of: layout), let th = p.theme(theme) else { return }
        let offs = FaceRenderer(p).widgetOffsets(w)
        var at = th.kids.firstIndex { $0 === layout } ?? th.kids.count - 1
        for (i, it) in w.all("Item").enumerated() {
            guard let r = it.string("ref") else { continue }
            let l = XNode("Layout")
            l.set("ref", r).set("x", int: Int((CGFloat(layout.int("x")) + offs[i].x).rounded())).set("y", int: Int((CGFloat(layout.int("y")) + offs[i].y).rounded()))
            at += 1
            th.kids.insert(l, at: min(at, th.kids.count))
        }
        w.kids.removeAll { $0.tag == "Item" }
        ElementFactory.delete(p, layout: layout, theme: theme)
    }

    static func moveItem(_ w: XNode, _ index: Int, _ dir: Int) {
        let items = w.all("Item")
        let j = index + dir
        guard index >= 0, j >= 0, j < items.count,
              let a = w.kids.firstIndex(where: { $0 === items[index] }), let b = w.kids.firstIndex(where: { $0 === items[j] }) else { return }
        w.kids.swapAt(a, b)
    }

    static func setTap(_ w: XNode, _ app: String) {
        if app.isEmpty { w.remove("jumpApp") } else { w.set("jumpApp", app) }
    }

    // MARK: Слот

    static func slotsOf(_ p: FaceProject, _ w: XNode) -> [XNode] {
        let key = "@" + (w.string("name") ?? "")
        return p.resources.elements.filter { $0.tag == "Slot" && $0.all("Item").contains { $0.string("ref") == key } }
    }

    static func widgets(_ p: FaceProject, _ slot: XNode) -> [XNode] {
        slot.all("Item").compactMap { p.resource(ref: $0.string("ref")) }
    }

    static func addSlot(_ p: FaceProject, theme: Int, center: (Int, Int), firstTitle: String) {
        let w = newWidget(p, title: firstTitle, w: 112, h: 74)
        w.set("flex_direction", "column")
        let s = XNode("Slot")
        s.set("name", p.uniqueName("slot")).set("type", "widget")
        s.add("Item").set("ref", "@" + (w.string("name") ?? ""))
        p.resources.kids.append(s)
        ElementFactory.addLayout(p, ref: s.string("name") ?? "", theme: theme, x: center.0 - 56, y: center.1 - 37)
    }

    @discardableResult
    static func slotNewWidget(_ p: FaceProject, _ slot: XNode, title: String) -> XNode {
        let f = widgets(p, slot).first { $0.has("w") && $0.has("h") }
        let w = newWidget(p, title: title, w: f.map { Int($0.int("w")) } ?? 112, h: f.map { Int($0.int("h")) } ?? 74)
        w.set("flex_direction", "column")
        slot.add("Item").set("ref", "@" + (w.string("name") ?? ""))
        return w
    }

    /// Віджети циферблата, які можна додати в слот (ще не в ньому)
    static func candidates(_ p: FaceProject, _ slot: XNode) -> [XNode] {
        let have = widgets(p, slot)
        let nested = Set(p.resources.elements.filter { $0.tag == "Widget" }.flatMap { $0.all("Item") }.compactMap { $0.string("ref") })
        return p.resources.elements.filter { e in isUserWidget(p, e) && !have.contains { $0 === e } && !nested.contains("@" + (e.string("name") ?? "")) }
    }

    /// Готовий віджет у слот; якщо він стояв окремим шаром — шар прибирається
    static func slotAddExisting(_ p: FaceProject, _ slot: XNode, _ w: XNode) {
        let key = "@" + (w.string("name") ?? "")
        slot.add("Item").set("ref", key)
        let sk = "@" + (slot.string("name") ?? "")
        for t in 0..<p.themes.count {
            // слот стає на місце віджета — елементи лишаються там, де були
            if let l = p.layouts(t).first(where: { $0.string("ref") == key }), let sl = p.layouts(t).first(where: { $0.string("ref") == sk }) {
                sl.set("x", int: Int(l.int("x"))).set("y", int: Int(l.int("y")))
            }
            p.theme(t)?.kids.removeAll { $0.tag == "Layout" && $0.string("ref") == key }
        }
    }

    /// Віджет виймається зі слота й стає окремим шаром на місці слота (на кожному екрані); мініатюра й рамка вибору прибираються.
    /// Якщо це був єдиний віджет слота, слот зникає.
    static func slotTakeOut(_ p: FaceProject, _ slot: XNode, _ index: Int) {
        let items = slot.all("Item")
        guard index >= 0, index < items.count, let r = items[index].string("ref"), let w = p.resource(ref: r) else { return }
        let sk = "@" + (slot.string("name") ?? "")
        slot.kids.removeAll { $0 === items[index] }
        for t in 0..<p.themes.count {
            guard let th = p.theme(t), let sl = p.layouts(t).first(where: { $0.string("ref") == sk }) else { continue }
            let l = XNode("Layout")
            l.set("ref", r).set("x", int: Int(sl.int("x"))).set("y", int: Int(sl.int("y")))
            let at = th.kids.firstIndex { $0 === sl } ?? th.kids.count - 1
            th.kids.insert(l, at: min(at + 1, th.kids.count))
        }
        // мініатюра й рамка потрібні лише віджетам у слоті
        if slotsOf(p, w).isEmpty {
            let pv = w.string("preview"), eb = w.string("editbox")
            w.remove("preview"); w.remove("editbox")
            if let pv { ElementFactory.collect(p, ref: pv) }
            if let eb { ElementFactory.collect(p, ref: eb) }
        }
        if slot.all("Item").isEmpty {
            for t in 0..<p.themes.count { p.theme(t)?.kids.removeAll { $0.tag == "Layout" && $0.string("ref") == sk } }
            p.resources.kids.removeAll { $0 === slot }
        }
    }

    static func slotRemove(_ p: FaceProject, _ slot: XNode, _ index: Int) {
        let items = slot.all("Item")
        guard items.count > 1, index >= 0, index < items.count else { return }
        let r = items[index].string("ref")
        slot.kids.removeAll { $0 === items[index] }
        if let r { ElementFactory.collect(p, ref: r) }
    }

    // MARK: Мініатюри й рамка для вибору на браслеті

    /// Відступ рамки вибору від країв екрана, px (0 — лише не виходить за край)
    private static let screenMargin: CGFloat = 0
    private static let previewScale: CGFloat = 0.634 // як в офіційних: 112×74 → 71×47

    static func refreshPreviews(_ p: FaceProject) {
        let r = FaceRenderer(p)
        for slot in p.resources.elements where slot.tag == "Slot" {
            for w in widgets(p, slot) where w.has("w") && w.has("h") {
                let W = CGFloat(w.int("w")), H = CGFloat(w.int("h"))
                let pw = max(8, Int((W * previewScale).rounded())), ph = max(8, Int((H * previewScale).rounded()))
                let img = AssetFactory.render(pw, ph) { c in
                    c.setFillColor(UIColor.black.cgColor); c.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
                    c.scaleBy(x: previewScale, y: previewScale)
                    r.draw(w, at: .zero, in: c, depth: 0)
                }
                setImageRef(p, w, attr: "preview", img: img, name: "wpreview_" + (w.string("name") ?? "w"))
                let st = p.meta.slotFrames[slot.string("name") ?? ""] ?? SlotFrame()
                let lay = p.layouts(0).first { $0.string("ref") == "@" + (slot.string("name") ?? "") }
                let ox = Int(lay?.int("x") ?? 0), oy = Int(lay?.int("y") ?? 0)
                let box = frameImage(p, st, pw: pw, ph: ph, origin: lay == nil ? nil : (ox, oy))
                let tag = "\(st.color.dropFirst())_\(st.alpha)_\(st.width)_\(st.fill)_\(st.shape)_\(st.radius)"
                setImageRef(p, w, attr: "editbox", img: box, name: "weditbox_\(pw)x\(ph)_\(tag)" + (lay != nil ? "_\(ox)_\(oy)" : ""))
            }
        }
    }

    /// Картинка рамки вибору: форма віджета, обрізана екраном (origin — місце слота на екрані), м'які кути, вигляд зі `SlotFrame`
    static func frameImage(_ p: FaceProject, _ st: SlotFrame, pw: Int, ph: Int, origin: (Int, Int)?) -> RGBAImage {
        AssetFactory.render(pw, ph) { _ in
            guard st.shape == 0 else { return }
            let half = CGFloat(st.width) / 2
            let boxRect = CGRect(x: half, y: half, width: CGFloat(pw) - 2 * half, height: CGFloat(ph) - 2 * half)
            var screen: (CGRect, CGFloat)?
            if let (ox, oy) = origin {
                let dev = p.meta.device
                let m = screenMargin + half / previewScale
                screen = (CGRect(x: (m - CGFloat(ox)) * previewScale, y: (m - CGFloat(oy)) * previewScale,
                                 width: (CGFloat(dev.width) - 2 * m) * previewScale, height: (CGFloat(dev.height) - 2 * m) * previewScale),
                          (CGFloat(dev.corner) - m) * previewScale)
            }
            let (core, rr) = softCore(box: boxRect, boxRadius: min(boxRect.width, boxRect.height) / 2, screen: screen, radius: CGFloat(st.radius) * previewScale)
            let c = AssetFactory.color(st.color)
            if st.fill > 0 {
                c.withAlphaComponent(CGFloat(st.fill) / 100).setFill()
                UIBezierPath(cgPath: dilate(core, rr)).fill()
            }
            if st.width > 0, st.alpha > 0 {
                let ring = dilate(core, rr + half).subtracting(dilate(core, max(rr - half, 0)))
                c.withAlphaComponent(CGFloat(st.alpha) / 100).setFill()
                UIBezierPath(cgPath: ring).fill()
            }
        }
    }

    /// Радіус м'яких кутів рамки вибору (там, де її обрізає екран), px циферблата
    static let cornerRadius: CGFloat = 16

    /// Рамка з м'якими кутами = (область ∩ екран) з відкриттям радіусом r: спершу обидві форми стискаються на r
    /// і перетинаються, потім результат розширюється на r. Повертає стиснуту форму й використаний радіус.
    static func softCore(box: CGRect, boxRadius: CGFloat, screen: (CGRect, CGFloat)?, radius: CGFloat) -> (CGPath, CGFloat) {
        let r = max(0, min(radius, min(box.width, box.height) / 2 - 1))
        func eroded(_ rect: CGRect, _ rad: CGFloat) -> CGPath {
            let q = rect.insetBy(dx: r, dy: r)
            return UIBezierPath(roundedRect: q, cornerRadius: max(0, min(rad - r, min(q.width, q.height) / 2))).cgPath
        }
        var core = eroded(box, boxRadius)
        if let (rect, rad) = screen { core = core.intersection(eroded(rect, rad)) }
        return (core, r)
    }

    /// Розширення форми на t (об'єднання з товстою обводкою контуру)
    static func dilate(_ path: CGPath, _ t: CGFloat) -> CGPath {
        guard t > 0 else { return path }
        return path.union(path.copy(strokingWithWidth: 2 * t, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }

    private static func setImageRef(_ p: FaceProject, _ w: XNode, attr: String, img: RGBAImage, name: String) {
        if attr == "editbox" {
            // рамки спільні для віджетів з однаковим виглядом, тож на місці їх не міняємо: беремо наявну за назвою або створюємо нову
            let old = w.string(attr)
            if p.resources.elements.contains(where: { $0.tag == "Image" && $0.string("name") == name }) {
                w.set(attr, "@" + name)
            } else {
                let n = ElementFactory.addImageResource(p, img, base: name)
                w.set(attr, "@" + n)
            }
            if let old, old != w.string(attr) { ElementFactory.collect(p, ref: old) }
            return
        }
        if let cur = p.resource(ref: w.string(attr)), cur.tag == "Image",
           (cur.string("name") ?? "").hasPrefix("wpreview_") {
            ElementFactory.replaceImage(p, cur, img); return
        }
        let n = ElementFactory.addImageResource(p, img, base: name)
        w.set(attr, "@" + n)
    }
}
