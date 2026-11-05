// SPDX-License-Identifier: MIT
// Малює тему циферблата так, як її покаже браслет (з пробними даними), і повертає рамки шарів для вибору й перетягування.

import UIKit
import FaceCompiler

struct LayerBox {
    let layout: XNode
    let rect: CGRect
}

final class FaceRenderer {
    let p: FaceProject
    var live = false
    /// Тимчасові позиції шарів під час перетягування (без зміни маніфесту)
    var overrides: [ObjectIdentifier: CGPoint] = [:]
    private var cache: [String: CGImage] = [:]
    private var cacheRevision = -1

    init(_ p: FaceProject) { self.p = p }

    // MARK: Картинки

    func image(_ src: String?) -> CGImage? {
        guard let src else { return nil }
        if cacheRevision != p.revision { cache = [:]; cacheRevision = p.revision }
        if let c = cache[src] { return c }
        guard let d = p.file(src), let png = PNG.decode([UInt8](d)) else { return nil }
        let img = RGBAImage(w: png.w, h: png.h, px: png.rgba).cgImage
        cache[src] = img
        return img
    }

    func frames(_ arr: XNode?) -> [CGImage] {
        guard let arr else { return [] }
        if arr.tag == "Image" { return image(arr.string("src")).map { [$0] } ?? [] }
        return arr.all("Image").compactMap { image($0.string("src")) }
    }

    // MARK: Малювання

    /// Тема на полотні розміру пристрою.
    func render(theme: Int, scale: CGFloat = 1) -> (UIImage, [LayerBox]) {
        let dev = p.meta.device
        let size = CGSize(width: dev.width, height: dev.height)
        var boxes: [LayerBox] = []
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let bg = p.theme(theme)?.string("bgColor") ?? "#000000"
            c.setFillColor(AssetFactory.color(bg).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            for l in p.layouts(theme) {
                let o = overrides[ObjectIdentifier(l)]
                let x = o?.x ?? CGFloat(l.int("x")), y = o?.y ?? CGFloat(l.int("y"))
                let r = draw(p.resource(ref: l.string("ref")), at: CGPoint(x: x, y: y), in: c, depth: 0)
                boxes.append(LayerBox(layout: l, rect: r ?? CGRect(x: x, y: y, width: 16, height: 16)))
            }
        }
        return (img, boxes)
    }

    private func put(_ img: CGImage, _ r: CGRect, _ c: CGContext) {
        UIImage(cgImage: img).draw(in: r)
    }

    private func value(_ res: XNode) -> Int {
        SampleData.value(res.string("source") ?? "", live: live)
    }

    /// Малює ресурс; повертає рамку.
    @discardableResult
    func draw(_ res: XNode?, at o: CGPoint, in c: CGContext, depth: Int) -> CGRect? {
        guard let res, depth < 6 else { return nil }
        switch res.tag {
        case "Image":
            guard let img = image(res.string("src")) else { return nil }
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(img.width), height: CGFloat(img.height))
            put(img, r, c); return r
        case "ImageArray":
            guard let img = frames(res).first else { return nil }
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(img.width), height: CGFloat(img.height))
            put(img, r, c); return r
        case "Sprite":
            return draw(p.resource(ref: res.string("ref")), at: o, in: c, depth: depth + 1)
        case "DataItemImageNumber": return drawNumber(res, o, c)
        case "DataItemImageValues":
            let fr = frames(p.resource(ref: res.string("ref")))
            guard !fr.isEmpty else { return nil }
            let params = res.all("Param").map { Int($0.int("value")) }
            let v = value(res)
            var idx = 0
            for (i, t) in params.enumerated() where v >= t { idx = i }
            let img = fr[min(idx, fr.count - 1)]
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(img.width), height: CGFloat(img.height))
            put(img, r, c); return r
        case "DataItemPointer": return drawPointer(res, o, c)
        case "DataItemArcProgressBar": return drawArc(res, o, c)
        case "DataItemLineProgressBar": return drawLine(res, o, c)
        case "DataItemText": return drawText(res, o, c)
        case "Widget":
            var u = CGRect.null
            for it in res.all("Item") {
                let pt = CGPoint(x: o.x + CGFloat(it.int("x")), y: o.y + CGFloat(it.int("y")))
                if let r = draw(p.resource(ref: it.string("ref")), at: pt, in: c, depth: depth + 1) { u = u.union(r) }
            }
            if res.has("w"), res.has("h") { u = CGRect(x: o.x, y: o.y, width: CGFloat(res.int("w")), height: CGFloat(res.int("h"))) }
            return u.isNull ? nil : u
        case "Slot":
            if let it = res.all("Item").first { return draw(p.resource(ref: it.string("ref")), at: o, in: c, depth: depth + 1) }
            return nil
        default: return nil
        }
    }

    private func fraction(_ res: XNode) -> CGFloat {
        let v = CGFloat(value(res))
        let start = res.has("valueStartSource") ? 0 : CGFloat(res.int("valueStart"))
        let range = res.has("valueRangeSource") ? 100 : CGFloat(res.int("valueRange"))
        guard range != 0 else { return 0 }
        return min(max((v - start) / range, 0), 1)
    }

    private func drawNumber(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        let fr = frames(p.resource(ref: res.string("ref")))
        guard fr.count >= 10 else { return nil }
        let total = Int(res.int("totalDigits"))
        var s = String(abs(value(res)))
        if res.bool("leadingZero"), total > 0, s.count < total { s = String(repeating: "0", count: total - s.count) + s }
        if total > 0, s.count > total { s = String(s.suffix(total)) }
        let space = CGFloat(Int8(truncatingIfNeeded: Int(res.int("space"))))
        let fw = CGFloat(fr[0].width), fh = CGFloat(fr[0].height)
        let n = CGFloat(max(total, s.count))
        let boxW = n * fw + max(0, n - 1) * space
        let contentW = CGFloat(s.count) * fw + CGFloat(max(0, s.count - 1)) * space
        var x = o.x
        switch res.string("align") {
        case "right": x = o.x + boxW - contentW
        case "center": x = o.x + (boxW - contentW) / 2
        default: break
        }
        for ch in s {
            let d = ch.wholeNumberValue ?? 0
            put(fr[d], CGRect(x: x, y: o.y, width: fw, height: fh), c)
            x += fw + space
        }
        var r = CGRect(x: o.x, y: o.y, width: boxW, height: fh)
        if let u = image(p.resource(ref: res.string("unitIcon"))?.string("src")) {
            let ur = CGRect(x: x, y: o.y, width: CGFloat(u.width), height: CGFloat(u.height))
            put(u, ur, c); r = r.union(ur)
        }
        return r
    }

    private func drawPointer(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        guard let img = frames(p.resource(ref: res.string("ref"))).first else { return nil }
        let px = CGFloat(res.int("pivotX")), py = CGFloat(res.int("pivotY"))
        let a = CGFloat(res.int("angleStart")) + CGFloat(res.int("angleRange")) * fraction(res)
        c.saveGState()
        c.translateBy(x: o.x + px, y: o.y + py)
        c.rotate(by: a * .pi / 180)
        put(img, CGRect(x: -px, y: -py, width: CGFloat(img.width), height: CGFloat(img.height)), c)
        c.restoreGState()
        // рамка — коло, яке описує стрілка
        let rad = max(hypot(px, py), hypot(CGFloat(img.width) - px, CGFloat(img.height) - py))
        return CGRect(x: o.x + px - rad, y: o.y + py - rad, width: rad * 2, height: rad * 2)
    }

    private func drawArc(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        var u = CGRect.null
        if let bg = image(p.resource(ref: res.string("bg"))?.string("src")) {
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(bg.width), height: CGFloat(bg.height)); put(bg, r, c); u = r
        }
        guard let fg = frames(p.resource(ref: res.string("ref"))).first else { return u.isNull ? nil : u }
        let r = CGRect(x: o.x, y: o.y, width: CGFloat(fg.width), height: CGFloat(fg.height))
        let cx = o.x + CGFloat(res.int("pivotX")), cy = o.y + CGFloat(res.int("pivotY"))
        let rad = CGFloat(res.int("barRadius")) + CGFloat(res.int("barWidth"))
        let a0 = CGFloat(res.int("angleStart")), span = CGFloat(res.int("angleRange")) * fraction(res)
        // 0° — угорі, за годинниковою стрілкою
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx, y: cy))
        path.addArc(withCenter: CGPoint(x: cx, y: cy), radius: rad + 4, startAngle: (a0 - 90) * .pi / 180,
                    endAngle: (a0 + span - 90) * .pi / 180, clockwise: span >= 0)
        path.close()
        c.saveGState(); c.addPath(path.cgPath); c.clip(); put(fg, r, c); c.restoreGState()
        return u.union(r)
    }

    private func drawLine(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        var u = CGRect.null
        if let bg = image(p.resource(ref: res.string("bg"))?.string("src")) {
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(bg.width), height: CGFloat(bg.height)); put(bg, r, c); u = r
        }
        guard let fg = frames(p.resource(ref: res.string("ref"))).first else { return u.isNull ? nil : u }
        let r = CGRect(x: o.x, y: o.y, width: CGFloat(fg.width), height: CGFloat(fg.height))
        let f = fraction(res)
        let sx = CGFloat(res.int("startX")), ex = CGFloat(res.int("endX")), sy = CGFloat(res.int("startY")), ey = CGFloat(res.int("endY"))
        var clip = r
        if abs(ex - sx) >= abs(ey - sy) {
            let a = min(sx, sx + (ex - sx) * f), b = max(sx, sx + (ex - sx) * f)
            clip = CGRect(x: o.x + a, y: r.minY, width: b - a, height: r.height)
        } else {
            let a = min(sy, sy + (ey - sy) * f), b = max(sy, sy + (ey - sy) * f)
            clip = CGRect(x: r.minX, y: o.y + a, width: r.width, height: b - a)
        }
        c.saveGState(); c.clip(to: clip); put(fg, r, c); c.restoreGState()
        return u.union(r)
    }

    private func drawText(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        let w = CGFloat(max(res.int("w"), 1)), h = CGFloat(max(res.int("h"), 1))
        var s = res.string("string") ?? ""
        for src in res.all("Content").compactMap({ $0.string("source") }) {
            if let r = s.range(of: "%s") ?? s.range(of: "%d") { s.replaceSubrange(r, with: String(value(res: src))) }
        }
        let size = res.has("fontSize") ? CGFloat(res.int("fontSize")) : max(10, h * 0.8)
        let weights: [String: UIFont.Weight] = ["thin": .thin, "extralight": .ultraLight, "light": .light, "regular": .regular, "normal": .regular,
                                                "medium": .medium, "semibold": .semibold, "demibold": .semibold, "bold": .bold, "heavy": .heavy]
        let weight = weights[res.string("fontWeight") ?? ""] ?? .regular
        let color = AssetFactory.color(res.string("color") ?? "#FFFFFF").withAlphaComponent(CGFloat(res.int("opacity", 100)) / 100)
        let para = NSMutableParagraphStyle()
        let aligns: [String: NSTextAlignment] = ["center": .center, "right": .right]
        para.alignment = aligns[res.string("align") ?? ""] ?? .left
        para.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
                                                    .paragraphStyle: para, .kern: CGFloat(res.int("letterSpace"))]
        let r = CGRect(x: o.x, y: o.y, width: w, height: h)
        let str = NSAttributedString(string: s, attributes: attrs)
        let th = str.boundingRect(with: CGSize(width: w, height: 1000), options: [.usesLineFragmentOrigin], context: nil).height
        c.saveGState(); c.clip(to: r)
        str.draw(with: CGRect(x: r.minX, y: r.minY + max(0, (h - th) / 2), width: w, height: max(h, th)), options: [.usesLineFragmentOrigin], context: nil)
        c.restoreGState()
        return r
    }

    private func value(res src: String) -> Int { SampleData.value(src, live: live) }
}
