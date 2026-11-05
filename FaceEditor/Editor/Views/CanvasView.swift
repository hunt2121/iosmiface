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
            let scale = min((geo.size.width - 32 - 2 * b) / W, (geo.size.height - 24 - 2 * b) / H)
            let size = CGSize(width: W * scale, height: H * scale)
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
                    SelectionFrame(rect: rect)
                    if let pos = dragPos {
                        Text("X \(Int(pos.x)) · Y \(Int(pos.y))")
                            .font(.system(size: 10, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue))
                            .position(x: rect.midX, y: max(8, rect.minY - 12))
                    }
                }
                if guideV { Rectangle().fill(Color.pink).frame(width: 1, height: size.height).offset(x: size.width / 2) }
                if guideH { Rectangle().fill(Color.pink).frame(width: size.width, height: 1).offset(y: size.height / 2) }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(drag(scale: scale, boxes: boxes, W: W, H: H))
            .faceCapsule()
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
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
        // спершу вже вибраний (щоб його легко тягнути), далі — верхній шар
        if let s = selected, let b = boxes.first(where: { $0.layout === s }), b.rect.insetBy(dx: -6, dy: -6).contains(pt) { return s }
        return boxes.last { $0.rect.insetBy(dx: -4, dy: -4).contains(pt) }?.layout
    }

    private func drag(scale: CGFloat, boxes: [LayerBox], W: CGFloat, H: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let start = CGPoint(x: v.startLocation.x / scale, y: v.startLocation.y / scale)
                if dragLayout == nil {
                    moved = false
                    guard let l = hit(start, boxes) else { return }
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
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: max(rect.width, 6), height: max(rect.height, 6))
                .offset(x: rect.minX, y: rect.minY)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color.white).overlay(Circle().stroke(Color.blue, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .offset(x: (i % 2 == 0 ? rect.minX : rect.maxX) - 4.5, y: (i < 2 ? rect.minY : rect.maxY) - 4.5)
            }
        }
        .allowsHitTesting(false)
    }
}
