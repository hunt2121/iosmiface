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
    /// Час анімації, с: який кадр показує кожен Sprite (0 — перший кадр)
    var time: Double = 0
    /// Тимчасові позиції шарів під час перетягування (без зміни маніфесту)
    var overrides: [ObjectIdentifier: CGPoint] = [:]
    /// Лише рамки шарів, без малювання (інспектор, вирівнювання)
    private var measureOnly = false

    /// Кольоровий варіант циферблата: 0 — основний, далі за colorGroupTable
    var colorVariant = 0

    init(_ p: FaceProject) { self.p = p }

    /// Ресурс за посиланням; для картинок — версія вибраного кольорового варіанта, якщо вона є
    private func pick(_ ref: String?) -> XNode? {
        guard let base = p.resource(ref: ref) else { return nil }
        guard colorVariant > 0, base.tag == "Image" || base.tag == "ImageArray" else { return base }
        return ColorVariants.variant(p, of: base, index: colorVariant) ?? base
    }

    // MARK: Картинки

    /// Картинка проєкту; розпаковані картинки спільні для всіх рендерів проєкту (полотно, інспектор, мініатюри)
    /// і скидаються лише для змінених файлів
    func image(_ src: String?) -> CGImage? {
        guard let src else { return nil }
        let path = MemoryStorage.normalizedPath(src)
        return p.images.get(path) {
            guard let d = p.file(path), let png = PNG.decode([UInt8](d)) else { return nil }
            return RGBAImage(w: png.w, h: png.h, px: png.rgba).cgImage
        }
    }

    func frames(_ arr: XNode?) -> [CGImage] {
        guard let arr else { return [] }
        if arr.tag == "Image" { return image(arr.string("src")).map { [$0] } ?? [] }
        return arr.all("Image").compactMap { image($0.string("src")) }
    }

    // MARK: Малювання

    /// Тема на полотні розміру пристрою. `layers` — лише шари з цими номерами (для перегляду з анімацією:
    /// шари під нею й над нею малюються окремо); `opaque: false` — без фону теми (прозоре полотно).
    func render(theme: Int, scale: CGFloat = 1, layers: ((Int) -> Bool)? = nil, opaque: Bool = true) -> (UIImage, [LayerBox]) {
        let dev = p.meta.device
        let size = CGSize(width: dev.width, height: dev.height)
        var boxes: [LayerBox] = []
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = opaque
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            // пікселі браслета збільшуються плавно (полотно, перегляд, превʼю в BandFace)
            c.interpolationQuality = .high
            if opaque {
                let bg = p.theme(theme)?.string("bgColor") ?? "#000000"
                c.setFillColor(AssetFactory.color(bg).cgColor)
                c.fill(CGRect(origin: .zero, size: size))
            }
            for (i, l) in p.layouts(theme).enumerated() where layers?(i) ?? true {
                let o = overrides[ObjectIdentifier(l)]
                let x = o?.x ?? CGFloat(l.int("x")), y = o?.y ?? CGFloat(l.int("y"))
                let r = draw(pick(l.string("ref")), at: CGPoint(x: x, y: y), in: c, depth: 0)
                boxes.append(LayerBox(layout: l, rect: r ?? CGRect(x: x, y: y, width: 16, height: 16)))
            }
        }
        return (img, boxes)
    }

    private func put(_ img: CGImage, _ r: CGRect, _ c: CGContext) {
        guard !measureOnly else { return }
        UIImage(cgImage: img).draw(in: r)
    }

    /// Рамки шарів теми без малювання — для інспектора й вирівнювання (у рази швидше за render)
    func boxes(theme: Int) -> [LayerBox] {
        measureOnly = true
        defer { measureOnly = false }
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        return p.layouts(theme).map { l in
            let o = overrides[ObjectIdentifier(l)]
            let x = o?.x ?? CGFloat(l.int("x")), y = o?.y ?? CGFloat(l.int("y"))
            let r = draw(pick(l.string("ref")), at: CGPoint(x: x, y: y), in: ctx, depth: 0)
            return LayerBox(layout: l, rect: r ?? CGRect(x: x, y: y, width: 16, height: 16))
        }
    }

    private func value(_ res: XNode) -> Int {
        SampleData.value(res.string("source") ?? "", live: live, demo: p.meta.demo)
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
            let fr = frames(pick(res.string("ref")))
            guard !fr.isEmpty else { return nil }
            let img = fr[Self.spriteFrame(res, count: fr.count, time: time)]
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(img.width), height: CGFloat(img.height))
            put(img, r, c); return r
        case "DataItemImageNumber": return drawNumber(res, o, c)
        case "DataItemImageValues":
            let fr = frames(pick(res.string("ref")))
            guard !fr.isEmpty else { return nil }
            let params = res.all("Param").map { Int($0.int("value")) }
            let v = value(res)
            var idx = 0
            // без порогів (Param) браслет бере картинку за номером: значення 3 — картинка 3
            if params.isEmpty { idx = max(0, v) }
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
            let items = res.all("Item")
            let offs = widgetOffsets(res, in: c, depth: depth)
            for (i, it) in items.enumerated() {
                let pt = CGPoint(x: o.x + offs[i].x, y: o.y + offs[i].y)
                if let r = draw(pick(it.string("ref")), at: pt, in: c, depth: depth + 1) { u = u.union(r) }
            }
            if res.has("w"), res.has("h") { u = CGRect(x: o.x, y: o.y, width: CGFloat(res.int("w")), height: CGFloat(res.int("h"))) }
            return u.isNull ? nil : u
        case "Slot":
            // у редакторі показуємо вибраний віджет слота (типово — перший)
            let items = res.all("Item")
            guard !items.isEmpty else { return nil }
            let it = items[min(max(0, WidgetSlots.shown(p, res)), items.count - 1)]
            return draw(pick(it.string("ref")), at: o, in: c, depth: depth + 1)
        default: return nil
        }
    }

    /// Зсуви елементів віджета від його лівого верхнього кута. Без flex_direction — x/y елементів;
    /// з flex_direction (row/column) — один за одним з проміжком gap, вирівнювання justify_content / align_items.
    func widgetOffsets(_ w: XNode, in c: CGContext? = nil, depth: Int = 0) -> [CGPoint] {
        let items = w.all("Item")
        let dir = w.string("flex_direction")
        guard dir == "row" || dir == "column" else { return items.map { CGPoint(x: CGFloat($0.int("x")), y: CGFloat($0.int("y"))) } }
        let row = dir == "row"
        let gap = CGFloat(w.int("gap"))
        let was = measureOnly
        measureOnly = true
        var ctx = c
        if ctx == nil {
            ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        var rects: [CGRect] = []
        if let ctx {
            if c == nil { UIGraphicsPushContext(ctx) }
            rects = items.map { draw(pick($0.string("ref")), at: .zero, in: ctx, depth: depth + 1) ?? .zero }
            if c == nil { UIGraphicsPopContext() }
        }
        measureOnly = was
        let main = rects.reduce(0) { $0 + (row ? $1.width : $1.height) } + gap * CGFloat(max(0, rects.count - 1))
        let cross = rects.map { row ? $0.height : $0.width }.max() ?? 0
        let W = w.has("w") ? CGFloat(w.int("w")) : (row ? main : cross)
        let H = w.has("h") ? CGFloat(w.int("h")) : (row ? cross : main)
        let box = row ? W : H, boxCross = row ? H : W
        let jc = w.string("justify_content") ?? "flex-start", ai = w.string("align_items") ?? "flex-start"
        var pos: CGFloat = jc == "center" ? (box - main) / 2 : jc == "flex-end" ? box - main : 0
        var out: [CGPoint] = []
        for r in rects {
            let len = row ? r.width : r.height, th = row ? r.height : r.width
            let cc: CGFloat = ai == "center" ? (boxCross - th) / 2 : ai == "flex-end" ? boxCross - th : 0
            out.append(row ? CGPoint(x: pos - r.minX, y: cc - r.minY) : CGPoint(x: cc - r.minX, y: pos - r.minY))
            pos += len + gap
        }
        return out
    }

    /// Рамка видимих пікселів ресурсу (від точки 0,0): прозорі краї картинок не враховуються
    func visibleBounds(_ res: XNode?) -> CGRect? {
        guard let res, let b = measure(res), b.width >= 1, b.height >= 1, b.width < 4000, b.height < 4000 else { return nil }
        let w = Int(b.width.rounded(.up)), h = Int(b.height.rounded(.up))
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { ctx in
            draw(res, at: CGPoint(x: -b.minX, y: -b.minY), in: ctx.cgContext, depth: 0)
        }
        guard let cg = img.cgImage,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return b }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 12 {
            if x < minX { minX = x }; if x > maxX { maxX = x }; if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        guard maxX >= 0 else { return b }
        return CGRect(x: b.minX + CGFloat(minX), y: b.minY + CGFloat(minY), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }

    /// Рамка ресурсу без малювання (від точки 0,0)
    func measure(_ res: XNode?) -> CGRect? {
        let was = measureOnly
        measureOnly = true
        defer { measureOnly = was }
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        return draw(res, at: .zero, in: ctx, depth: 0)
    }

    /// Кадр анімації: interval мс на кадр; repeatCount 0 — без кінця, інакше після повторів лишається останній
    static func spriteFrame(_ res: XNode, count: Int, time: Double) -> Int {
        let step = Int(time * 1000) / max(1, Int(res.int("interval", 100)))
        let repeats = Int(res.int("repeatCount"))
        if repeats > 0, step >= count * repeats { return count - 1 }
        return step % count
    }

    private func fraction(_ res: XNode) -> CGFloat {
        let v = CGFloat(value(res))
        let start = res.has("valueStartSource") ? 0 : CGFloat(res.int("valueStart"))
        let range = res.has("valueRangeSource") ? 100 : CGFloat(res.int("valueRange"))
        guard range != 0 else { return 0 }
        return min(max((v - start) / range, 0), 1)
    }

    private func drawNumber(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        let fr = frames(pick(res.string("ref")))
        // кадрів може бути менше за 10: так роблять перемикачі стану (2 кадри для «не турбувати», Bluetooth)
        guard !fr.isEmpty else { return nil }
        let total = Int(res.int("totalDigits"))
        var s = String(abs(value(res)))
        if res.bool("leadingZero"), total > 0, s.count < total { s = String(repeating: "0", count: total - s.count) + s }
        if total > 0, s.count > total { s = String(s.suffix(total)) }
        let space = CGFloat(Int8(truncatingIfNeeded: Int(res.int("space"))))
        let fw = CGFloat(fr[0].width), fh = CGFloat(fr[0].height)
        let unit = image(pick(res.string("unitIcon"))?.string("src"))
        var contentW = CGFloat(s.count) * fw + CGFloat(max(0, s.count - 1)) * space
        if let u = unit { contentW += CGFloat(u.width) }
        // x макета — точка прив'язки, як на браслеті: left — лівий край числа, center — його середина,
        // right — правий край (у BigWatch кроки: align="center", x=106 — середина екрана 212).
        var x = o.x
        switch res.string("align") {
        case "right", "flex-end": x = o.x - contentW
        case "center": x = o.x - contentW / 2
        default: break
        }
        let r = CGRect(x: x, y: o.y, width: contentW, height: fh)
        for ch in s {
            let d = ch.wholeNumberValue ?? 0
            if d < fr.count { put(fr[d], CGRect(x: x, y: o.y, width: fw, height: fh), c) }
            x += fw + space
        }
        if let u = unit {
            let ur = CGRect(x: x - space, y: o.y, width: CGFloat(u.width), height: CGFloat(u.height))
            put(u, ur, c)
            return r.union(ur)
        }
        return r
    }

    private func drawPointer(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        guard let img = frames(pick(res.string("ref"))).first else { return nil }
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
        if let bg = image(pick(res.string("bg"))?.string("src")) {
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(bg.width), height: CGFloat(bg.height)); put(bg, r, c); u = r
        }
        guard let fg = frames(pick(res.string("ref"))).first else { return u.isNull ? nil : u }
        let r = CGRect(x: o.x, y: o.y, width: CGFloat(fg.width), height: CGFloat(fg.height))
        let cx = o.x + CGFloat(res.int("pivotX")), cy = o.y + CGFloat(res.int("pivotY"))
        let rad = CGFloat(res.int("barRadius")) + CGFloat(res.int("barWidth"))
        let a0 = CGFloat(res.int("angleStart")), span = CGFloat(res.int("angleRange")) * fraction(res)
        // круглі кінці: як на браслеті (endingStyle=round) — і на початку, і на кінці заповнення півколо
        // радіусом у пів товщини. Сектор + два кола; працює й для повного кільця, де в картинці кінців немає.
        let br = CGFloat(res.int("barRadius")), hw = CGFloat(res.int("barWidth")) / 2
        let round = res.string("endingStyle") != "normal" && hw > 0
        // 0° — угорі, за годинниковою стрілкою
        if abs(span) > 0.01 {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cx, y: cy))
            path.addArc(withCenter: CGPoint(x: cx, y: cy), radius: rad + 4, startAngle: (a0 - 90) * .pi / 180,
                        endAngle: (a0 + span - 90) * .pi / 180, clockwise: span >= 0)
            path.close()
            c.saveGState(); c.addPath(path.cgPath); c.clip(); put(fg, r, c); c.restoreGState()
            // кожне коло — окремим вирізом (обʼєднання шляхів могло б «вирізати» перетин через напрям обходу)
            if round {
                for deg in [a0, a0 + span] {
                    let t = deg * .pi / 180
                    let p = CGPoint(x: cx + br * sin(t), y: cy - br * cos(t))
                    c.saveGState(); c.addEllipse(in: CGRect(x: p.x - hw, y: p.y - hw, width: hw * 2, height: hw * 2)); c.clip(); put(fg, r, c); c.restoreGState()
                }
            }
        }
        // крапка-індикатор на кінці заповнення
        if let ind = image(pick(res.string("indicatorImage"))?.string("src")) {
            let ir = CGFloat(res.has("indicatorRadius") ? res.int("indicatorRadius") : res.int("barRadius"))
            let a = (a0 + span) * .pi / 180
            let ix = cx + ir * sin(a), iy = cy - ir * cos(a)
            put(ind, CGRect(x: ix - CGFloat(ind.width) / 2, y: iy - CGFloat(ind.height) / 2, width: CGFloat(ind.width), height: CGFloat(ind.height)), c)
        }
        return u.union(r)
    }

    private func drawLine(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        var u = CGRect.null
        if let bg = image(pick(res.string("bg"))?.string("src")) {
            let r = CGRect(x: o.x, y: o.y, width: CGFloat(bg.width), height: CGFloat(bg.height)); put(bg, r, c); u = r
        }
        guard let fg = frames(pick(res.string("ref"))).first else { return u.isNull ? nil : u }
        let r = CGRect(x: o.x, y: o.y, width: CGFloat(fg.width), height: CGFloat(fg.height))
        let f = fraction(res)
        let sx = CGFloat(res.int("startX")), ex = CGFloat(res.int("endX")), sy = CGFloat(res.int("startY")), ey = CGFloat(res.int("endY"))
        let len = hypot(ex - sx, ey - sy)
        guard f > 0, len > 0 else { return u.union(r) }
        // заповнення до точки start + (end − start)·f; межа — перпендикуляр до лінії (будь-який кут), заокруглений початок цілий
        let ux = (ex - sx) / len, uy = (ey - sy) / len, nx = -uy, ny = ux, big: CGFloat = 2000, t = len * CGFloat(f)
        func q(_ a: CGFloat, _ b: CGFloat) -> CGPoint { CGPoint(x: o.x + sx + ux * a + nx * b, y: o.y + sy + uy * a + ny * b) }
        c.saveGState()
        c.addLines(between: [q(-big, -big), q(t, -big), q(t, big), q(-big, big)])
        c.closePath(); c.clip(); put(fg, r, c); c.restoreGState()
        return u.union(r)
    }

    private func drawText(_ res: XNode, _ o: CGPoint, _ c: CGContext) -> CGRect? {
        var s = res.string("string") ?? ""
        for src in res.all("Content").compactMap({ $0.string("source") }) {
            if let r = s.range(of: "%s") ?? s.range(of: "%d") { s.replaceSubrange(r, with: String(value(res: src))) }
        }
        let arc = (res.string("style") ?? "normal") != "normal"
        let h0 = CGFloat(max(res.int("h"), 1))
        let size = res.has("fontSize") ? CGFloat(max(res.int("fontSize"), 1)) : max(10, h0 * 0.8)
        let font = Self.font(res.string("fontWeight"), size: size)
        let color = AssetFactory.color(res.string("color") ?? "#FFFFFF").withAlphaComponent(CGFloat(res.int("opacity", 100)) / 100)
        let kern = CGFloat(res.int("letterSpace"))
        if arc { return drawArcText(s, res, o, c, font: font, color: color, kern: kern) }
        let w = CGFloat(max(res.int("w"), 1)), h = h0
        let para = NSMutableParagraphStyle()
        let aligns: [String: NSTextAlignment] = ["center": .center, "right": .right]
        para.alignment = aligns[res.string("align") ?? ""] ?? .left
        let wrap = res.string("longMode") == "wrap"
        para.lineBreakMode = wrap ? .byWordWrapping : .byClipping
        para.lineSpacing = CGFloat(res.int("lineSpace"))
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para, .kern: kern]
        let r = CGRect(x: o.x, y: o.y, width: w, height: h)
        guard !measureOnly else { return r }
        let str = NSAttributedString(string: s, attributes: attrs)
        let opts: NSStringDrawingOptions = wrap ? [.usesLineFragmentOrigin] : [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let bound = CGSize(width: wrap ? w : 10_000, height: 1000)
        let tb = str.boundingRect(with: bound, options: [.usesLineFragmentOrigin], context: nil)
        c.saveGState()
        // поворот навколо середини поля
        let rot = CGFloat(res.int("rotation"))
        if rot != 0 { c.translateBy(x: r.midX, y: r.midY); c.rotate(by: rot * .pi / 180); c.translateBy(x: -r.midX, y: -r.midY) }
        c.clip(to: r)
        var dx: CGFloat = 0
        if !wrap {
            // рядок без переносу: вирівнювання вручну, бо поле ширше за ширину малювання
            switch para.alignment { case .center: dx = (w - tb.width) / 2; case .right: dx = w - tb.width; default: dx = 0 }
        }
        str.draw(with: CGRect(x: r.minX + (wrap ? 0 : dx), y: r.minY + max(0, (h - tb.height) / 2),
                              width: wrap ? w : tb.width + 2, height: max(h, tb.height)), options: opts, context: nil)
        c.restoreGState()
        return r
    }

    /// Текст дугою: коло радіуса radius, рамка — квадрат 2r від точки макета; кут 0° — угорі, за годинниковою
    private func drawArcText(_ s: String, _ res: XNode, _ o: CGPoint, _ c: CGContext, font: UIFont, color: UIColor, kern: CGFloat) -> CGRect? {
        let r = CGFloat(max(res.int("radius"), 1))
        let box = CGRect(x: o.x, y: o.y, width: r * 2, height: r * 2)
        guard !measureOnly, !s.isEmpty else { return box }
        let cx = box.midX, cy = box.midY
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let widths = s.map { (String($0) as NSString).size(withAttributes: attrs).width + kern }
        let total = widths.reduce(0, +)
        // радіус середньої лінії тексту залежно від verticalAlign
        let va = res.string("verticalAlign") ?? "top"
        let mid: CGFloat = va == "center" ? r - font.lineHeight / 2 : va == "bottom" ? r - font.lineHeight : r
        let rr = max(1, va == "top" ? r - font.ascender : mid)
        let a0 = CGFloat(res.int("startAngle")), span = CGFloat(res.int("span"))
        let textAngle = total / rr * 180 / .pi
        var a: CGFloat
        switch res.string("align") ?? "center" {
        case "left": a = a0
        case "right": a = a0 + span - textAngle
        default: a = a0 + (span - textAngle) / 2
        }
        for (ch, w) in zip(s, widths) {
            let half = w / 2 / rr * 180 / .pi
            let ang = (a + half) * .pi / 180
            c.saveGState()
            c.translateBy(x: cx + rr * sin(ang), y: cy - rr * cos(ang))
            c.rotate(by: ang)
            (String(ch) as NSString).draw(at: CGPoint(x: -(w - kern) / 2, y: -font.ascender), withAttributes: attrs)
            c.restoreGState()
            a += w / rr * 180 / .pi
        }
        return box
    }

    /// Системний шрифт потрібної насиченості (браслет малює текст своїм шрифтом — на полотні наближено)
    static func font(_ weight: String?, size: CGFloat) -> UIFont {
        let key = (weight ?? "regular").lowercased()
        let weights: [String: UIFont.Weight] = ["thin": .thin, "extralight": .ultraLight, "light": .light, "regular": .regular,
                                                "normal": .regular, "medium": .medium, "semibold": .semibold, "demibold": .semibold,
                                                "bold": .bold, "heavy": .heavy]
        return UIFont.systemFont(ofSize: size, weight: weights[key] ?? .regular)
    }

    private func value(res src: String) -> Int { SampleData.value(src, live: live, demo: p.meta.demo) }
}
