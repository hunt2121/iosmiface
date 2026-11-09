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
    static func fit(_ p: FaceProject, _ w: XNode, layout: XNode? = nil) {
        if arrange(w) == "free", !w.all("Item").isEmpty { wrapFree(p, w, layout: layout); return }
        let inSlot = !slotsOf(p, w).isEmpty
        let oldW = Int(w.int("w")), oldH = Int(w.int("h"))
        w.remove("w"); w.remove("h")
        let box = FaceRenderer(p).measure(w) ?? CGRect(x: 0, y: 0, width: 40, height: 30)
        let cw = max(8, Int(box.maxX.rounded(.up))), ch = max(8, Int(box.maxY.rounded(.up)))
        w.set("w", int: max(cw, inSlot ? oldW : 0)).set("h", int: max(ch, inSlot ? oldH : 0))
    }

    /// Вільне розташування: область віджета щільно обгортає його елементи. Якщо віджет стоїть окремим шаром,
    /// шар зсувається в лівий верхній кут елементів; у слоті місце слота лишається, елементи зсуваються всередині.
    static func wrapFree(_ p: FaceProject, _ w: XNode, layout: XNode?) {
        let r = FaceRenderer(p)
        var box = CGRect.null
        for it in w.all("Item") {
            guard let c = p.resource(ref: it.string("ref")), let m = r.measure(c) else { continue }
            box = box.union(m.offsetBy(dx: CGFloat(it.int("x")), dy: CGFloat(it.int("y"))))
        }
        guard !box.isNull else { return }
        let inSlot = layout == nil && !slotsOf(p, w).isEmpty
        var dx = Int(box.minX.rounded(.down)), dy = Int(box.minY.rounded(.down))
        if layout == nil { dx = min(0, dx); dy = min(0, dy) }
        for it in w.all("Item") { it.set("x", int: Int(it.int("x")) - dx).set("y", int: Int(it.int("y")) - dy) }
        if let l = layout { l.set("x", int: Int(l.int("x")) + dx).set("y", int: Int(l.int("y")) + dy) }
        let cw = max(8, Int(box.maxX.rounded(.up)) - dx), ch = max(8, Int(box.maxY.rounded(.up)) - dy)
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
    static func addToWidget(_ p: FaceProject, _ w: XNode, origin: CGPoint, layout: XNode, theme: Int, own: XNode? = nil) {
        guard let th = p.theme(theme), let r = layout.string("ref") else { return }
        if w.all("Item").isEmpty && own != nil {
            for k in ["flex_direction", "justify_content", "align_content", "align_items", "gap"] { w.remove(k) }
        }
        let it = w.add("Item").set("ref", r)
        if arrange(w) == "free" { it.set("x", int: Int(CGFloat(layout.int("x")) - origin.x)).set("y", int: Int(CGFloat(layout.int("y")) - origin.y)) }
        else { it.set("x", int: 0).set("y", int: 0) }
        th.kids.removeAll { $0 === layout }
        fit(p, w, layout: own)
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

    static func slotRemove(_ p: FaceProject, _ slot: XNode, _ index: Int) {
        let items = slot.all("Item")
        guard items.count > 1, index >= 0, index < items.count else { return }
        let r = items[index].string("ref")
        slot.kids.removeAll { $0 === items[index] }
        if let r { ElementFactory.collect(p, ref: r) }
    }

    // MARK: Мініатюри й рамка для вибору на браслеті

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
                let box = AssetFactory.render(pw, ph) { _ in
                    let rad = CGFloat(min(pw, ph)) / 2 - 1.5
                    let path = UIBezierPath(roundedRect: CGRect(x: 1.5, y: 1.5, width: CGFloat(pw) - 3, height: CGFloat(ph) - 3), cornerRadius: rad)
                    path.lineWidth = 3
                    AssetFactory.color("#FF9900").setStroke()
                    path.stroke()
                }
                setImageRef(p, w, attr: "editbox", img: box, name: "weditbox_\(pw)x\(ph)")
            }
        }
    }

    private static func setImageRef(_ p: FaceProject, _ w: XNode, attr: String, img: RGBAImage, name: String) {
        if attr == "editbox", p.resources.elements.contains(where: { $0.tag == "Image" && $0.string("name") == name }) {
            w.set(attr, "@" + name); return
        }
        if let cur = p.resource(ref: w.string(attr)), cur.tag == "Image",
           (cur.string("name") ?? "").hasPrefix(attr == "preview" ? "wpreview_" : "weditbox_") {
            ElementFactory.replaceImage(p, cur, img); return
        }
        let n = ElementFactory.addImageResource(p, img, base: name)
        w.set(attr, "@" + n)
    }
}
