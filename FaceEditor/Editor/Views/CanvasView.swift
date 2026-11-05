// SPDX-License-Identifier: MIT
// Полотно: циферблат у формі браслета, вибір шару дотиком, перетягування з прив'язкою до центру, країв і сітки.

import SwiftUI
import FaceCompiler

struct CanvasView: View {
    @ObservedObject var project: FaceProject
    let theme: Int
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

    var body: some View {
        GeometryReader { geo in
            let dev = project.meta.device
            let W = CGFloat(dev.width), H = CGFloat(dev.height)
            let scale = min((geo.size.width - 32) / W, (geo.size.height - 24) / H)
            let size = CGSize(width: W * scale, height: H * scale)
            let r = currentRender()
            ZStack(alignment: .topLeading) {
                Image(uiImage: r.0).resizable().frame(width: size.width, height: size.height)
                if let box = selectedBox(r.1) {
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
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(dev.corner) * scale, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CGFloat(dev.corner) * scale, style: .continuous).stroke(Color(.systemGray3), lineWidth: 3))
            .contentShape(Rectangle())
            .gesture(drag(scale: scale, boxes: r.1, W: W, H: H))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .accessibilityLabel("Полотно циферблата")
        }
    }

    private func currentRender() -> (UIImage, [LayerBox]) {
        let rd = renderer ?? FaceRenderer(project)
        if renderer == nil { DispatchQueue.main.async { renderer = rd } }
        rd.overrides = [:]
        if let l = dragLayout, let p = dragPos { rd.overrides[ObjectIdentifier(l)] = p }
        return rd.render(theme: theme, scale: UIScreen.main.scale * 1.5)
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
                if abs(dx) + abs(dy) > 1.5 { moved = true }
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
                defer { dragLayout = nil; dragPos = nil; guideV = false; guideH = false }
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
