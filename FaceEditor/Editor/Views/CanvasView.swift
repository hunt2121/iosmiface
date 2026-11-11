// SPDX-License-Identifier: MIT
// Полотно: циферблат у формі браслета, вибір шару дотиком, перетягування з прив'язкою до центру, країв і сітки.

import SwiftUI
import FaceCompiler

struct CanvasView: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    /// Кольоровий варіант для показу (0 — основний)
    var variant = 0
    @Binding var selected: XNode?
    let snap: Bool
    let grid: Int
    /// Масштаб полотна: 1 — вписано, 2 — 200 %, 3 — 300 % (порожнім місцем полотно пересувається)
    var zoom: CGFloat = 1
    /// Замок: елементи не пересуваються — дотик лише вибирає, а палець рухає збільшене полотно
    var locked = false

    @State private var renderer: FaceRenderer?
    @State private var dragLayout: XNode?
    @State private var dragStart = CGPoint.zero      // позиція шару на початку
    @State private var dragPos: CGPoint?             // поточна (у пікселях браслета)
    @State private var guideV = false
    @State private var guideH = false
    @State private var moved = false
    /// Під час перетягування: шари під вибраним, сам шар і шари над ним — намальовані один раз;
    /// далі лише зсувається картинка шару (без перемальовування всього циферблата на кожен рух пальця)
    @State private var dragCache: DragCache?
    /// Ручки дуги й лінії: «a0»/«a1» — початок/кінець дуги, «l0»/«l1» — кінці лінії
    @State private var handle: String?
    @State private var hStart: Double = 0
    @State private var hRange: Double = 0
    @State private var hA = CGPoint.zero
    @State private var hB = CGPoint.zero
    @State private var hSnapped = false
    @State private var touchDown = Date()
    /// Рамка розміру віджета/слота: ручка, що тягнеться, її рамка (у пікселях браслета) і напрямні прилипання
    @State private var sizeHandle: String?
    @State private var sizeRect: CGRect?
    @State private var sizeStart = CGRect.zero
    @State private var sizeGuideX: [CGFloat] = []
    @State private var sizeGuideY: [CGFloat] = []
    /// Палець притримали перед рухом — без прив'язки кутів
    @State private var freeMode: Bool?
    /// Зсув збільшеного полотна і його значення на початку жесту
    @State private var pan = CGSize.zero
    @State private var panStart: CGSize?

    struct DragCache {
        let below: UIImage
        let layer: UIImage
        let above: UIImage
        /// рамки шарів на початку перетягування
        let boxes: [LayerBox]
    }
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let dev = project.meta.device
            let W = CGFloat(dev.width), H = CGFloat(dev.height)
            let b = FaceFrame.border
            let scale = min((geo.size.width - 32 - 2 * b) / W, (geo.size.height - 24 - 2 * b) / H) * zoom
            let size = CGSize(width: W * scale, height: H * scale)
            // зсув збільшеного полотна не дає вийти за межі
            let maxX = max(0, (size.width - geo.size.width) / 2 + 40), maxY = max(0, (size.height - geo.size.height) / 2 + 40)
            let pn = CGSize(width: min(maxX, max(-maxX, pan.width)), height: min(maxY, max(-maxY, pan.height)))
            let origin = CGPoint(x: geo.size.width / 2 - size.width / 2 + pn.width, y: geo.size.height / 2 - size.height / 2 + pn.height)
            // рівно під фізичні пікселі полотна (раніше — у 6 разів більше, що гальмувало перетягування)
            let cache = dragCache
            let r: (UIImage, [LayerBox])? = cache == nil ? currentRender(scale * displayScale) : nil
            let boxes = r?.1 ?? cache?.boxes ?? []
            // зсув перетягуваного шару (у пікселях браслета)
            let shift = cache != nil && dragPos != nil ? CGSize(width: dragPos!.x - dragStart.x, height: dragPos!.y - dragStart.y) : .zero
            ZStack(alignment: .topLeading) {
                if let r {
                    Image(uiImage: r.0).resizable().frame(width: size.width, height: size.height)
                } else if let cache {
                    Image(uiImage: cache.below).resizable().frame(width: size.width, height: size.height)
                    Image(uiImage: cache.layer).resizable().frame(width: size.width, height: size.height)
                        .offset(x: shift.width * scale, y: shift.height * scale)
                    Image(uiImage: cache.above).resizable().frame(width: size.width, height: size.height)
                }
                if let box0 = selectedBox(boxes) {
                    let box = box0.offsetBy(dx: shift.width, dy: shift.height)
                    let rect = CGRect(x: box.minX * scale, y: box.minY * scale, width: box.width * scale, height: box.height * scale)
                    SelectionFrame(rect: rect, corners: gauge == nil,
                                   screen: sizeTarget == nil ? nil : CGSize(width: CGFloat(project.meta.device.width) * scale, height: CGFloat(project.meta.device.height) * scale),
                                   corner: CGFloat(project.meta.device.corner) * scale, softRadius: WidgetSlots.cornerRadius * scale)
                    if let pos = dragPos {
                        Text("X \(Int(pos.x)) · Y \(Int(pos.y))")
                            .font(.system(size: 10, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue))
                            .position(x: rect.midX, y: max(8, rect.minY - 12))
                    }
                }
                if cache == nil || handle != nil { handlesOverlay(scale: scale) }
                if cache == nil { sizeOverlay(scale: scale, W: W, H: H) }
                if guideV { Rectangle().fill(Color.pink).frame(width: 1, height: size.height).offset(x: size.width / 2) }
                if guideH { Rectangle().fill(Color.pink).frame(width: size.width, height: 1).offset(y: size.height / 2) }
            }
            .frame(width: size.width, height: size.height)
            .faceCapsule()
            .position(x: geo.size.width / 2 + pn.width, y: geo.size.height / 2 + pn.height)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // жест — на всю панель полотна: дотик поза циферблатом теж відкриває налаштування циферблата
            .contentShape(Rectangle())
            .gesture(drag(scale: scale, origin: origin, boxes: boxes, W: W, H: H))
            .onChange(of: zoom) { _ in pan = .zero }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Полотно циферблата")
            .accessibilityIdentifier("canvas")
        }
    }

    private func currentRender(_ pixelScale: CGFloat) -> (UIImage, [LayerBox]) {
        let rd = renderer ?? FaceRenderer(project)
        if renderer == nil { DispatchQueue.main.async { renderer = rd } }
        rd.overrides = [:]
        rd.colorVariant = variant
        if let l = dragLayout, let p = dragPos { rd.overrides[ObjectIdentifier(l)] = p }
        return rd.render(theme: theme, scale: max(1, pixelScale))
    }

    /// Три шари для перетягування: під вибраним, вибраний, над ним
    private func makeCache(for l: XNode, pixelScale: CGFloat) -> DragCache? {
        guard let i = project.layouts(theme).firstIndex(where: { $0 === l }) else { return nil }
        let rd = renderer ?? FaceRenderer(project)
        rd.overrides = [:]
        rd.colorVariant = variant
        let ps = max(1, pixelScale)
        let below = rd.render(theme: theme, scale: ps, layers: { $0 < i }).0
        let layer = rd.render(theme: theme, scale: ps, layers: { $0 == i }, opaque: false).0
        let above = rd.render(theme: theme, scale: ps, layers: { $0 > i }, opaque: false).0
        return DragCache(below: below, layer: layer, above: above, boxes: rd.boxes(theme: theme))
    }

    private func selectedBox(_ boxes: [LayerBox]) -> CGRect? {
        guard let s = selected else { return nil }
        return boxes.first { $0.layout === s }?.rect
    }

    private func hit(_ pt: CGPoint, _ boxes: [LayerBox]) -> XNode? {
        // шари під точкою, згори донизу; приглушення AOD не вибирається — воно у властивостях циферблата
        let cands = boxes.reversed().filter { !AodDim.isDim(project, $0.layout, theme: theme) && $0.rect.insetBy(dx: -4, dy: -4).contains(pt) }.map(\.layout)
        // спершу — ті, що справді намальовані в цьому місці: прозора частина рамки (середина дуги, поля картинки)
        // не закриває шари під нею
        let rd = renderer ?? FaceRenderer(project)
        rd.colorVariant = variant
        let solid = cands.filter { rd.opaque($0, near: pt) }
        if let s = selected, solid.contains(where: { $0 === s }) { return s }
        if let top = solid.first { return top }
        // у порожньому місці: вже вибраний (щоб його легко тягнути), далі — верхній шар
        if let s = selected, let b = boxes.first(where: { $0.layout === s }), b.rect.insetBy(dx: -6, dy: -6).contains(pt) { return s }
        return cands.first
    }

    // MARK: Розмір віджета й слота

    /// Віджет чи слот вибраного шару: його віджети й шар
    private var sizeTarget: ([XNode], XNode)? {
        guard let s = selected, let res = project.element(of: s) else { return nil }
        if res.tag == "Widget" { return ([res], s) }
        if res.tag == "Slot" { let ws = WidgetSlots.widgets(project, res); return ws.isEmpty ? nil : (ws, s) }
        return nil
    }

    private func currentSizeRect() -> CGRect? {
        guard let (ws, l) = sizeTarget else { return nil }
        let w = ws.map { Int($0.int("w")) }.max() ?? 0, h = ws.map { Int($0.int("h")) }.max() ?? 0
        return CGRect(x: CGFloat(l.int("x")), y: CGFloat(l.int("y")), width: CGFloat(max(w, 8)), height: CGFloat(max(h, 8)))
    }

    private static func sizePoints(_ r: CGRect) -> [(String, CGPoint)] {
        [("tl", CGPoint(x: r.minX, y: r.minY)), ("t", CGPoint(x: r.midX, y: r.minY)), ("tr", CGPoint(x: r.maxX, y: r.minY)),
         ("r", CGPoint(x: r.maxX, y: r.midY)), ("br", CGPoint(x: r.maxX, y: r.maxY)), ("b", CGPoint(x: r.midX, y: r.maxY)),
         ("bl", CGPoint(x: r.minX, y: r.maxY)), ("l", CGPoint(x: r.minX, y: r.midY))]
    }

    private func startSizeHandle(_ pt: CGPoint, scale: CGFloat) -> Bool {
        guard let r = currentSizeRect() else { return false }
        let tol = 22 / scale
        guard let h = Self.sizePoints(r).map({ ($0.0, hypot($0.1.x - pt.x, $0.1.y - pt.y)) }).filter({ $0.1 <= tol }).min(by: { $0.1 < $1.1 }) else { return false }
        sizeHandle = h.0; sizeStart = r; sizeRect = r
        return true
    }

    private func moveSize(_ pt: CGPoint, boxes: [LayerBox], W: CGFloat, H: CGFloat) {
        guard let h = sizeHandle else { return }
        let others = boxes.filter { $0.layout !== selected && !AodDim.isDim(project, $0.layout, theme: theme) }.map(\.rect)
        let xs: [CGFloat] = [0, W / 2, W] + others.flatMap { (r: CGRect) -> [CGFloat] in [r.minX, r.midX, r.maxX] }
        let ys: [CGFloat] = [0, H / 2, H] + others.flatMap { (r: CGRect) -> [CGFloat] in [r.minY, r.midY, r.maxY] }
        var gx: [CGFloat] = [], gy: [CGFloat] = []
        func sn(_ v: CGFloat, _ c: [CGFloat], _ g: inout [CGFloat]) -> CGFloat {
            if snap, let m = c.min(by: { abs($0 - v) < abs($1 - v) }), abs(m - v) <= 4 { g.append(m); return m }
            return v.rounded()
        }
        let L = h.contains("l"), R = h.contains("r"), T = h.hasPrefix("t"), B = h.hasPrefix("b")
        var minX = sizeStart.minX, maxX = sizeStart.maxX, minY = sizeStart.minY, maxY = sizeStart.maxY
        if L { minX = min(sn(pt.x, xs, &gx), maxX - 8) }
        if R { maxX = max(sn(pt.x, xs, &gx), minX + 8) }
        if T { minY = min(sn(pt.y, ys, &gy), maxY - 8) }
        if B { maxY = max(sn(pt.y, ys, &gy), minY + 8) }
        if project.sizeRatioLock, (L || R), (T || B), sizeStart.height > 0 {
            let ratio = sizeStart.width / sizeStart.height
            let nh = max(8, ((maxX - minX) / ratio).rounded())
            if T { minY = maxY - nh } else { maxY = minY + nh }
            gy = []
        }
        sizeGuideX = gx; sizeGuideY = gy
        sizeRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func endSize() {
        defer { sizeHandle = nil; sizeRect = nil; sizeGuideX = []; sizeGuideY = [] }
        guard let r = sizeRect, r != sizeStart, let (ws, l) = sizeTarget else { return }
        let dx = Int(r.minX - sizeStart.minX), dy = Int(r.minY - sizeStart.minY)
        project.edit { p in
            for w in ws {
                WidgetSlots.setSize(p, w, width: Int(r.width), height: Int(r.height))
                // зсув лівого чи верхнього краю не має зрушувати вміст з місця (вільне розташування)
                if (dx != 0 || dy != 0), WidgetSlots.arrange(w) == "free" {
                    for it in w.all("Item") { it.set("x", int: Int(it.int("x")) - dx).set("y", int: Int(it.int("y")) - dy) }
                }
            }
            l.set("x", int: Int(r.minX)).set("y", int: Int(r.minY))
        }
    }

    @ViewBuilder private func sizeOverlay(scale: CGFloat, W: CGFloat, H: CGFloat) -> some View {
        if sizeTarget != nil, let r0 = sizeRect ?? currentSizeRect() {
            let r = CGRect(x: r0.minX * scale, y: r0.minY * scale, width: r0.width * scale, height: r0.height * scale)
            ZStack(alignment: .topLeading) {
                if sizeHandle != nil {
                    Rectangle().fill(Color.blue.opacity(0.07)).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                    ForEach(Array(sizeGuideX.enumerated()), id: \.offset) { _, x in Rectangle().fill(Color.pink).frame(width: 1, height: H * scale).offset(x: x * scale) }
                    ForEach(Array(sizeGuideY.enumerated()), id: \.offset) { _, y in Rectangle().fill(Color.pink).frame(width: W * scale, height: 1).offset(y: y * scale) }
                    tag("\(Int(r0.width)) × \(Int(r0.height))", at: CGPoint(x: r.midX - 30, y: max(20, r.minY)), snapped: !sizeGuideX.isEmpty || !sizeGuideY.isEmpty)
                }
                ForEach(Array(Self.sizePoints(r0).enumerated()), id: \.offset) { _, np in
                    let name = np.0, pt = np.1
                    let edge = name.count == 1
                    let horizontal = name == "t" || name == "b"
                    RoundedRectangle(cornerRadius: 6).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue, lineWidth: 2))
                        .frame(width: edge ? (horizontal ? 22 : 11) : 12, height: edge ? (horizontal ? 11 : 22) : 12)
                        .position(x: pt.x * scale, y: pt.y * scale)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Ручки дуги й лінії

    /// Дуга чи лінія вибраного шару
    private var gauge: (XNode, ElementKind)? {
        guard let s = selected, let res = project.element(of: s) else { return nil }
        let k = ElementKind.of(res, in: project)
        return k == .arc || k == .line ? (res, k) : nil
    }

    private func arcCenter(_ res: XNode) -> CGPoint {
        guard let s = selected else { return .zero }
        return CGPoint(x: CGFloat(s.int("x") + res.int("pivotX")), y: CGFloat(s.int("y") + res.int("pivotY")))
    }

    private static func onArc(_ c: CGPoint, _ r: CGFloat, _ deg: Double) -> CGPoint {
        let t = deg * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(sin(t)), y: c.y - r * CGFloat(cos(t)))
    }

    private static func norm(_ a: Double) -> Double { let m = a.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }

    /// До найближчого кратного step, якщо ближче за 4°
    private static func snapTo(_ a: Double, _ step: Double) -> (Double, Bool) {
        let n = (a / step).rounded() * step
        return abs(n - a) <= 4 ? (n, true) : (a.rounded(), false)
    }

    private func ends(_ res: XNode, _ k: ElementKind) -> (CGPoint, CGPoint)? {
        guard let s = selected else { return nil }
        if k == .arc {
            let c = arcCenter(res), r = CGFloat(res.int("barRadius"))
            guard r > 0 else { return nil }
            return (Self.onArc(c, r, Double(res.int("angleStart"))), Self.onArc(c, r, Double(res.int("angleStart") + res.int("angleRange"))))
        }
        return (CGPoint(x: CGFloat(s.int("x") + res.int("startX")), y: CGFloat(s.int("y") + res.int("startY"))),
                CGPoint(x: CGFloat(s.int("x") + res.int("endX")), y: CGFloat(s.int("y") + res.int("endY"))))
    }

    private func startHandle(_ pt: CGPoint, scale: CGFloat) -> Bool {
        guard case let (res, k)? = gauge, case let (a, b)? = ends(res, k) else { return false }
        if k == .line, !(project.meta.generators[res.string("name") ?? ""]?.drawn ?? false) { return false }
        let tol = 18 / scale
        let d = { (p: CGPoint) in hypot(p.x - pt.x, p.y - pt.y) }
        if d(b) <= tol { handle = k == .arc ? "a1" : "l1" } else if d(a) <= tol { handle = k == .arc ? "a0" : "l0" } else { return false }
        hStart = Double(res.int("angleStart")); hRange = Double(res.int("angleRange")); hA = a; hB = b; hSnapped = false
        touchDown = Date(); freeMode = nil
        return true
    }

    private func moveHandle(_ pt: CGPoint) {
        guard let h = handle, case let (res, _)? = gauge else { return }
        let snapOn = snap && !(freeMode ?? false)
        hSnapped = false
        if h.hasPrefix("a") {
            let c = arcCenter(res)
            var th = Self.norm(atan2(Double(pt.x - c.x), Double(-(pt.y - c.y))) * 180 / .pi)
            var s1 = false
            if snapOn { (th, s1) = Self.snapTo(th, 45); th = Self.norm(th) } else { th = th.rounded() }
            let s0 = Double(res.int("angleStart")), r0 = Double(res.int("angleRange"))
            let ccw = r0 < 0
            if h == "a1" {
                var r = ccw ? -Self.norm(s0 - th) : Self.norm(th - s0)
                if abs(r) < 1 { r = (ccw ? -1 : 1) * (abs(hRange) > 180 ? 360 : 1) }
                if snapOn {
                    // довжина — до 90/180/270/360
                    let m = (abs(r) / 90).rounded() * 90
                    if m > 0, abs(m - abs(r)) <= 2 { r = (r < 0 ? -1 : 1) * m; s1 = true }
                }
                hRange = r
            } else {
                let e = s0 + r0
                var r = ccw ? -Self.norm(th - e) : Self.norm(e - th)
                if abs(r) < 1 { r = (ccw ? -1 : 1) * 360 }
                hStart = th; hRange = r
            }
            hSnapped = s1
        } else {
            let fixed = h == "l1" ? hA : hB
            let len = max(4, hypot(Double(pt.x - fixed.x), Double(pt.y - fixed.y)))
            var ang = atan2(Double(pt.y - fixed.y), Double(pt.x - fixed.x)) * 180 / .pi
            if snapOn { (ang, hSnapped) = Self.snapTo(ang, 45) }
            let t = ang * .pi / 180
            let m = CGPoint(x: (Double(fixed.x) + cos(t) * len).rounded(), y: (Double(fixed.y) + sin(t) * len).rounded())
            if h == "l1" { hB = m } else { hA = m }
        }
    }

    private func endHandle() {
        defer { handle = nil }
        guard let h = handle, case let (res, k)? = gauge, let layout = selected else { return }
        let name = res.string("name") ?? ""
        let gen = project.meta.generators[name].map { ElementFactory.synced(res, $0) }
        if h.hasPrefix("a") {
            if Int(hStart) == Int(res.int("angleStart")), Int(hRange) == Int(res.int("angleRange")) { return }
            let s = hStart, r = hRange
            if var g = gen, g.drawn {
                g.start = s; g.range = r
                let gg = g
                project.edit { ElementFactory.regenerate($0, element: name, gen: gg) }
            } else {
                project.edit { _ in res.set("angleStart", int: Int(s)).set("angleRange", int: Int(r)) }
            }
        } else if k == .line, let g = gen {
            if case let (a, b)? = ends(res, k), a == hA, b == hB { return }
            let A = hA, B = hB
            project.edit { p in ElementFactory.placeLine(p, res: res, layout: layout, gen: g, from: A, to: B) }
        }
    }

    @ViewBuilder private func handlesOverlay(scale: CGFloat) -> some View {
        if case let (res, k)? = gauge, case let (a0, b0)? = ends(res, k) {
            let (a, b) = shownEnds(res, k, a0, b0)
            let sc = { (p: CGPoint) in CGPoint(x: p.x * scale, y: p.y * scale) }
            let sel = Color.blue
            ZStack(alignment: .topLeading) {
                if handle != nil {
                    if k == .arc {
                        let c = arcCenter(res), r = CGFloat(res.int("barRadius"))
                        Path { p in
                            if abs(hRange) >= 359.5 { p.addEllipse(in: CGRect(x: (c.x - r) * scale, y: (c.y - r) * scale, width: 2 * r * scale, height: 2 * r * scale)) }
                            else { p.addArc(center: sc(c), radius: r * scale, startAngle: .degrees(hStart - 90), endAngle: .degrees(hStart + hRange - 90), clockwise: hRange < 0) }
                        }
                        .stroke(sel.opacity(0.45), style: StrokeStyle(lineWidth: CGFloat(max(2, res.int("barWidth"))) * scale, lineCap: .round))
                        let moving = handle == "a1" ? b : a
                        Path { p in p.move(to: sc(c)); p.addLine(to: sc(moving)) }
                            .stroke(hSnapped ? Color.pink : sel, style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                        tag(handle == "a1" ? "\(Int(abs(hRange)))°" : loc("від") + " \(Int(Self.norm(hStart)))°", at: sc(moving), snapped: hSnapped)
                    } else {
                        Path { p in p.move(to: sc(a)); p.addLine(to: sc(b)) }
                            .stroke(sel.opacity(0.45), style: StrokeStyle(lineWidth: CGFloat(max(2, res.int("barWidth"))) * scale, lineCap: .round))
                        if hSnapped {
                            let len = max(1, hypot(b.x - a.x, b.y - a.y)), ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
                            Path { p in p.move(to: sc(CGPoint(x: a.x - ux * 40, y: a.y - uy * 40))); p.addLine(to: sc(CGPoint(x: b.x + ux * 40, y: b.y + uy * 40))) }
                                .stroke(Color.pink, style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                        }
                        let ang = Self.norm(-atan2(Double(b.y - a.y), Double(b.x - a.x)) * 180 / .pi)
                        tag("\(Int(ang.rounded()))° · \(Int(hypot(b.x - a.x, b.y - a.y).rounded())) px", at: sc(handle == "l1" ? b : a), snapped: hSnapped)
                    }
                }
                dot(sc(a), 14); dot(sc(b), k == .arc ? 16 : 14)
            }
            .allowsHitTesting(false)
        }
    }

    /// Кінці, які показуємо: під час перетягування — нові
    private func shownEnds(_ res: XNode, _ k: ElementKind, _ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGPoint) {
        guard handle != nil else { return (a, b) }
        if k == .arc {
            let c = arcCenter(res), r = CGFloat(res.int("barRadius"))
            return (Self.onArc(c, r, hStart), Self.onArc(c, r, hStart + hRange))
        }
        return (hA, hB)
    }

    private func dot(_ p: CGPoint, _ size: CGFloat) -> some View {
        Circle().fill(Color.white).overlay(Circle().stroke(Color.blue, lineWidth: 2))
            .frame(width: size, height: size).position(p)
    }

    private func tag(_ text: String, at p: CGPoint, snapped: Bool) -> some View {
        Text(verbatim: text).font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(snapped ? Color.pink : Color.blue))
            .fixedSize()
            .position(x: p.x + 30, y: p.y - 18)
    }

    private func drag(scale: CGFloat, origin: CGPoint, boxes: [LayerBox], W: CGFloat, H: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                // збільшене полотно пересувається пальцем по порожньому місцю
                if let ps = panStart { pan = CGSize(width: ps.width + v.translation.width, height: ps.height + v.translation.height); return }
                if locked {
                    if zoom > 1, abs(v.translation.width) + abs(v.translation.height) > 4 { panStart = CGSize(width: pan.width - v.translation.width, height: pan.height - v.translation.height) }
                    return
                }
                let start = CGPoint(x: (v.startLocation.x - origin.x) / scale, y: (v.startLocation.y - origin.y) / scale)
                // ручки розміру віджета чи слота
                if sizeHandle != nil || (dragLayout == nil && startSizeHandle(start, scale: scale)) {
                    if abs(v.translation.width) + abs(v.translation.height) > 1 {
                        moveSize(CGPoint(x: (v.location.x - origin.x) / scale, y: (v.location.y - origin.y) / scale), boxes: boxes, W: W, H: H)
                    }
                    return
                }
                // ручки на кінцях дуги чи лінії
                if handle != nil || (dragLayout == nil && startHandle(start, scale: scale)) {
                    let moved = abs(v.translation.width) + abs(v.translation.height) > 2
                    if moved, freeMode == nil { freeMode = Date().timeIntervalSince(touchDown) > 0.5 }
                    if moved { moveHandle(CGPoint(x: (v.location.x - origin.x) / scale, y: (v.location.y - origin.y) / scale)) }
                    return
                }
                if dragLayout == nil {
                    moved = false
                    guard let l = hit(start, boxes) else {
                        if zoom > 1, abs(v.translation.width) + abs(v.translation.height) > 4 { panStart = CGSize(width: pan.width - v.translation.width, height: pan.height - v.translation.height) }
                        return
                    }
                    selected = l
                    dragLayout = l
                    dragStart = CGPoint(x: CGFloat(l.int("x")), y: CGFloat(l.int("y")))
                }
                guard let l = dragLayout else { return }
                let dx = v.translation.width / scale, dy = v.translation.height / scale
                if abs(dx) + abs(dy) > 1.5, !moved {
                    moved = true
                    dragCache = makeCache(for: l, pixelScale: scale * displayScale)
                }
                guard moved else { return }
                var x = dragStart.x + dx, y = dragStart.y + dy
                let g = CGFloat(max(1, grid))
                x = (x / g).rounded() * g; y = (y / g).rounded() * g
                guideV = false; guideH = false
                if snap, let b = boxes.first(where: { $0.layout === l })?.rect {
                    let offX = b.minX - dragStart.x, offY = b.minY - dragStart.y
                    let cx = x + offX + b.width / 2, cy = y + offY + b.height / 2
                    if abs(cx - W / 2) < 4 { x = W / 2 - b.width / 2 - offX; guideV = true }
                    if abs(cy - H / 2) < 4 { y = H / 2 - b.height / 2 - offY; guideH = true }
                    if abs(x + offX) < 4 { x = -offX }
                    if abs(y + offY) < 4 { y = -offY }
                    if abs(x + offX + b.width - W) < 4 { x = W - b.width - offX }
                    if abs(y + offY + b.height - H) < 4 { y = H - b.height - offY }
                }
                dragPos = CGPoint(x: x.rounded(), y: y.rounded())
            }
            .onEnded { v in
                if panStart != nil { panStart = nil; return }
                if locked {
                    // замок: дотик лише вибирає шар (або знімає вибір)
                    let start = CGPoint(x: (v.startLocation.x - origin.x) / scale, y: (v.startLocation.y - origin.y) / scale)
                    selected = hit(start, boxes)
                    return
                }
                if sizeHandle != nil { endSize(); return }
                if handle != nil { if freeMode != nil { endHandle() } else { handle = nil }; return }
                defer { dragLayout = nil; dragPos = nil; guideV = false; guideH = false; dragCache = nil }
                guard let l = dragLayout else {
                    // дотик повз шари — зняти вибір
                    selected = nil
                    return
                }
                if moved, let p = dragPos {
                    project.edit { _ in l.set("x", int: Int(p.x)).set("y", int: Int(p.y)) }
                }
            }
    }
}

/// Пунктирна рамка з чотирма маркерами.
struct SelectionFrame: View {
    let rect: CGRect
    /// Кутові маркери (у дуги й лінії — свої ручки на кінцях)
    var corners = true
    /// Для віджета й слота: рамка повторює скруглення екрана, не виходить за його край, кути м'які
    var screen: CGSize? = nil
    var corner: CGFloat = 0
    var softRadius: CGFloat = 0

    private var shape: Path {
        let r = CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 6), height: max(rect.height, 6))
        guard let screen else { return Path(roundedRect: r, cornerRadius: 4) }
        // віджет і слот: форма екрана внизу, не виходить за край, кути м'які (як рамка вибору на браслеті)
        let (core, rr) = WidgetSlots.softCore(box: r, boxRadius: 4, screen: (CGRect(x: 0, y: 0, width: screen.width, height: screen.height), corner),
                                               radius: softRadius)
        return Path(WidgetSlots.dilate(core, rr))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            ForEach(0..<(corners ? 4 : 0), id: \.self) { i in
                Circle().fill(Color.white).overlay(Circle().stroke(Color.blue, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .offset(x: (i % 2 == 0 ? rect.minX : rect.maxX) - 4.5, y: (i < 2 ? rect.minY : rect.maxY) - 4.5)
            }
        }
        .allowsHitTesting(false)
    }
}
