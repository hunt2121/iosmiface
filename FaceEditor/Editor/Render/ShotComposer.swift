// SPDX-License-Identifier: MIT
// «Набір знімків»: екрани циферблата (стилі, кольори, AOD, стани) на одній оформленій картинці —
// тло, назва, підписи, рамка капсулою чи браслетом. Розмір — за кількістю екранів або за форматом (1:1, 9:16, 16:9).

import UIKit
import FaceCompiler

enum ShotComposer {
    /// Один екран на картинці (екран набору або його стан)
    struct Item {
        var screen: ShotScreen
        /// 0 — звичайний, 1 — Bluetooth від'єднано, 2 — заряд 15 %
        var state = 0
    }

    static func items(_ s: ShotSet) -> [Item] {
        s.screens.flatMap { sc -> [Item] in
            var r = [Item(screen: sc)]
            if sc.bluetooth { r.append(Item(screen: sc, state: 1)) }
            if sc.battery { r.append(Item(screen: sc, state: 2)) }
            return r
        }
    }

    // MARK: Тексти

    /// Тема екрана: стиль або його AOD (якщо AOD немає — сам стиль)
    static func theme(_ p: FaceProject, _ sc: ShotScreen) -> Int {
        let styles = p.styleThemes
        let t = styles.indices.contains(sc.style) ? styles[sc.style] : (styles.first ?? 0)
        if sc.aod, let a = p.aodTheme(forStyle: t) { return a }
        return t
    }

    static func colorName(_ i: Int) -> String { i == 0 ? loc("Основний колір") : String(format: loc("Колір %d"), i) }

    /// Підпис за замовчуванням: «Стиль 1 · Колір 2» (без кольору, якщо кольорів немає)
    static func defaultName(_ p: FaceProject, _ sc: ShotScreen) -> String {
        let styles = p.styleThemes
        let t = styles.indices.contains(sc.style) ? styles[sc.style] : (styles.first ?? 0)
        var s = p.styleTitle(t)
        if ColorVariants.isEnabled(p) { s += " · " + colorName(sc.color) }
        return s
    }

    static func name(_ p: FaceProject, _ sc: ShotScreen) -> String { sc.name.isEmpty ? defaultName(p, sc) : sc.name }

    static func stateText(_ it: Item) -> String? {
        switch it.state {
        case 1: return loc("Bluetooth від'єднано")
        case 2: return loc("Заряд 15 %")
        default: return it.screen.aod ? loc("Завжди на екрані") : nil
        }
    }

    static func autoTitle(_ p: FaceProject) -> String { p.displayName }
    /// «Циферблат для Xiaomi Smart Band 10 • 11»: Band 10 і 11 мають той самий екран — циферблат підходить обом
    static func autoAbove(_ p: FaceProject) -> String {
        let d = p.meta.device
        let name = d.width == 212 && d.height == 520 ? "Smart Band 10 • 11" : d.title
        return String(format: loc("Циферблат для Xiaomi %@"), name)
    }
    /// «2 стилі · 3 кольори»; один стиль без кольорів — порожньо
    static func autoBelow(_ p: FaceProject) -> String {
        let n = p.styleThemes.count, c = ColorVariants.isEnabled(p) ? ColorVariants.colors(p).count : 0
        var parts: [String] = []
        if n > 1 { parts.append(plural(n, loc("%d стиль"), loc("%d стилі"), loc("%d стилів"))) }
        if c > 1 { parts.append(plural(c, loc("%d колір"), loc("%d кольори"), loc("%d кольорів"))) }
        return parts.joined(separator: " · ")
    }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = n % 10, b = n % 100
        let f = a == 1 && b != 11 ? one : (2...4).contains(a) && !(12...14).contains(b) ? few : many
        return String(format: f, n)
    }

    // MARK: Тло

    /// Кольори тла (два — градієнт згори вниз)
    static func background(_ p: FaceProject, _ key: String) -> [UIColor] {
        func c(_ h: String) -> UIColor { AssetFactory.color(h) }
        switch key {
        case "dark": return [c("#1F2A3A"), c("#0C0C0E")]
        case "black": return [c("#000000")]
        case "white": return [c("#FFFFFF")]
        case "light": return [c("#F2F2F5")]
        case "blue": return [c("#1E4FD8"), c("#0B1A4A")]
        case "face":
            // з циферблата: основний колір, притемнений до глибокого тла
            let base = ColorVariants.colors(p).first ?? p.theme(p.styleThemes.first ?? 0)?.string("bgColor") ?? "#1F2A3A"
            let k = c(base)
            return [k.mix(with: .black, 0.55), k.mix(with: .black, 0.88)]
        default: return [c(key)]
        }
    }

    static func isLight(_ colors: [UIColor]) -> Bool {
        let l = colors.map { $0.luminance }.reduce(0, +) / CGFloat(max(1, colors.count))
        return l > 0.55
    }

    // MARK: Розміри (pt; картинка — удвічі більша)

    private static let devW: CGFloat = 212, devH: CGFloat = 520
    /// Рамка-браслет: картинка 480×1240, екран у ній — (97, 262, 287×704)
    private static let bandImg = CGSize(width: 480, height: 1240)
    private static let bandScreen = CGRect(x: 97, y: 262, width: 287, height: 704)

    /// Ширина екрана за розміром (формат «Авто»)
    static func screenWidth(_ size: Int) -> CGFloat { [170, 150, 120][max(0, min(2, size))] }

    /// Розмір самого екрана чи браслета (без підпису)
    static func cellBody(_ s: ShotSet, w: CGFloat) -> CGSize {
        if s.band { let k = w / bandScreen.width; return CGSize(width: bandImg.width * k, height: bandImg.height * k) }
        return CGSize(width: w, height: w * devH / devW)
    }

    /// Найбільша сторона готової картинки, pt (2560 px)
    static let maxSide: CGFloat = 1280

    /// Стовпців: до 5 — один ряд, до 12 — два, далі по 6
    static func autoColumns(_ n: Int) -> Int { n <= 5 ? max(1, n) : n <= 12 ? (n + 1) / 2 : 6 }

    static func fixedSize(_ f: ShotSet.Format) -> CGSize? {
        switch f {
        case .auto: return nil
        case .square: return CGSize(width: 620, height: 620)
        case .story: return CGSize(width: 540, height: 960)
        case .wide: return CGSize(width: 960, height: 540)
        }
    }

    /// Розкладка сітки: стовпці, ширина екрана, вузький режим (дрібніші підписи, стани — лише значком)
    struct Layout {
        var cols: Int, w: CGFloat, narrow: Bool
        var gap: CGFloat { narrow ? 18 : 30 }
        let rowGap: CGFloat = 30
    }

    static func itemWidth(_ s: ShotSet, _ l: Layout) -> CGFloat {
        max(cellBody(s, w: l.w).width, s.captions ? l.w + (l.narrow ? 18 : 40) : 0)
    }

    static func captionHeight(_ s: ShotSet, items: [Item]) -> CGFloat {
        guard s.captions else { return 0 }
        return items.contains { stateText($0) != nil } ? 66 : 39
    }

    static func gridSize(_ s: ShotSet, _ l: Layout, n: Int, capH: CGFloat) -> CGSize {
        let rows = (n + l.cols - 1) / l.cols, body = cellBody(s, w: l.w)
        return CGSize(width: CGFloat(l.cols) * itemWidth(s, l) + CGFloat(l.cols - 1) * l.gap,
                      height: CGFloat(rows) * (body.height + capH) + CGFloat(rows - 1) * l.rowGap)
    }

    // MARK: Кольори текстів

    private struct Palette {
        let light: Bool
        var fg: UIColor { light ? AssetFactory.color("#111318") : .white }
        var sub: UIColor { light ? AssetFactory.color("#6B7080") : AssetFactory.color("#A3A9B6") }
        var line: UIColor { light ? UIColor(white: 0, alpha: 0.12) : UIColor(white: 1, alpha: 0.14) }
        func state(_ it: Item) -> UIColor {
            let dark = it.state == 1 ? "#5AA2FF" : it.state == 2 ? "#FFB23F" : "#B9A6FF"
            let lt = it.state == 1 ? "#1E6FE0" : it.state == 2 ? "#C46A00" : "#6A4FD8"
            return AssetFactory.color(light ? lt : dark)
        }
    }

    // MARK: Складання

    static func compose(_ p: FaceProject, _ s: ShotSet) -> UIImage? {
        let list = Self.items(s)
        guard !list.isEmpty else { return nil }
        let bg = background(p, s.background)
        let pal = Palette(light: isLight(bg))
        let fixed = fixedSize(s.format)

        // шапка
        let above = s.above ?? autoAbove(p), title = s.title ?? autoTitle(p), below = s.below ?? autoBelow(p)
        let titleSize: CGFloat = fixed == nil ? 64 : s.format == .wide ? 44 : 48
        let aboveA = NSAttributedString(string: above.uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: pal.sub, .kern: 2.6])
        let titleA = NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: titleSize, weight: .heavy), .foregroundColor: pal.fg, .kern: -1])
        let chips = below.components(separatedBy: " · ").filter { !$0.isEmpty }
        let chipFont = UIFont.systemFont(ofSize: 12.5, weight: .medium)
        let chipA = chips.map { NSAttributedString(string: $0, attributes: [.font: chipFont, .foregroundColor: pal.sub]) }
        let chipH: CGFloat = 24
        var header: CGFloat = 0
        if !above.isEmpty { header += aboveA.size().height }
        if !title.isEmpty { header += (header > 0 ? 12 : 0) + titleA.size().height }
        if !chips.isEmpty { header += (header > 0 ? 14 : 0) + chipH }
        if header > 0 { header += 42 }
        let creditA = NSAttributedString(string: loc("Зроблено в BandFace"), attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: pal.sub.withAlphaComponent(0.8)])
        let footer: CGFloat = s.credit ? 40 + creditA.size().height : 0

        // сітка
        let n = list.count
        let capH = captionHeight(s, items: list)
        let pad = CGSize(width: 56, height: 48)
        var lay = Layout(cols: autoColumns(n), w: screenWidth(s.size), narrow: false)
        var canvas: CGSize
        if let fx = fixed {
            // формат заданий: стовпці й ширина екрана — найбільші, що вміщаються з відступами
            let area = CGSize(width: fx.width - 2 * pad.width, height: fx.height - 2 * pad.height - header - footer)
            var best = Layout(cols: 1, w: 10, narrow: false)
            for narrow in [false, true] {
                for c in 1...n {
                    var lo: CGFloat = 10, hi: CGFloat = 400
                    for _ in 0..<24 {
                        let m = (lo + hi) / 2
                        let g = gridSize(s, Layout(cols: c, w: m, narrow: narrow), n: n, capH: capH)
                        if g.width <= area.width && g.height <= area.height { lo = m } else { hi = m }
                    }
                    if lo > best.w { best = Layout(cols: c, w: lo, narrow: narrow) }
                }
                // вузький режим — лише коли звичайний дає зовсім дрібні екрани
                if best.w >= 90 { break }
            }
            best.w = min(floor(best.w * [1, 0.9, 0.78][max(0, min(2, s.size))]), 260)
            lay = best
            canvas = fx
        } else {
            func fit(_ l: Layout) -> CGSize {
                let g = gridSize(s, l, n: n, capH: capH)
                return CGSize(width: max(g.width + 2 * pad.width, 640), height: g.height + 2 * pad.height + header + footer)
            }
            canvas = fit(lay)
            // не більше 2560 px по довшій стороні (1280 pt): більші картинки месенджери однаково зменшують;
            // замість зменшення всієї картинки — менші екрани, тексти лишаються того ж розміру
            if max(canvas.width, canvas.height) > maxSide {
                var lo: CGFloat = 30, hi = lay.w
                for _ in 0..<24 {
                    let m = (lo + hi) / 2
                    let c = fit(Layout(cols: lay.cols, w: m, narrow: false))
                    if max(c.width, c.height) <= maxSide { lo = m } else { hi = m }
                }
                lay.w = floor(lo)
                lay.narrow = lay.w < 90
                canvas = fit(lay)
            }
        }
        let grid = gridSize(s, lay, n: n, capH: capH)
        let body = cellBody(s, w: lay.w)
        let iw = itemWidth(s, lay)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = true
        let bandImage = s.band ? UIImage(named: pal.light ? "ShotBandDark" : "ShotBandLight") : nil
        let renderer = FaceRenderer(p)
        if let t = s.time { var d = p.meta.demo; d.time = t; d.realTime = false; renderer.demo = d }

        return UIGraphicsImageRenderer(size: canvas, format: fmt).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            // тло
            if bg.count > 1, let g = CGGradient(colorsSpace: space, colors: bg.map(\.cgColor) as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: canvas.width * 0.35, y: 0), end: CGPoint(x: canvas.width * 0.65, y: canvas.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                c.setFillColor(bg[0].cgColor); c.fill(CGRect(origin: .zero, size: canvas))
            }
            // легке світіння за екранами
            let glow = pal.light ? UIColor(white: 1, alpha: 0.75) : UIColor(red: 0.47, green: 0.63, blue: 1, alpha: 0.10)
            if let g = CGGradient(colorsSpace: space, colors: [glow.cgColor, glow.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
                c.saveGState()
                c.translateBy(x: canvas.width / 2, y: canvas.height * 0.62)
                c.scaleBy(x: 1, y: 0.75)
                c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: canvas.width * 0.6 * 0.7, options: [])
                c.restoreGState()
            }

            let total = header + grid.height + footer
            var y = (canvas.height - total) / 2
            func centered(_ a: NSAttributedString, at yy: CGFloat) { a.draw(at: CGPoint(x: (canvas.width - a.size().width) / 2, y: yy)) }
            if header > 0 {
                if !above.isEmpty {
                    let sz = aboveA.size()
                    centered(aboveA, at: y)
                    // тонкі лінії з обох боків
                    c.setFillColor(pal.line.cgColor)
                    let ly = y + sz.height / 2
                    c.fill(CGRect(x: (canvas.width - sz.width) / 2 - 14 - 28, y: ly, width: 28, height: 1))
                    c.fill(CGRect(x: (canvas.width + sz.width) / 2 + 14 - 2.6, y: ly, width: 28, height: 1))
                    y += sz.height
                }
                if !title.isEmpty { if y > (canvas.height - total) / 2 { y += 12 }; centered(titleA, at: y); y += titleA.size().height }
                if !chips.isEmpty {
                    if y > (canvas.height - total) / 2 { y += 14 }
                    let widths = chipA.map { $0.size().width + 22 }
                    var x = (canvas.width - (widths.reduce(0, +) + CGFloat(chips.count - 1) * 8)) / 2
                    for (i, a) in chipA.enumerated() {
                        let r = CGRect(x: x, y: y, width: widths[i], height: chipH)
                        c.setStrokeColor(pal.line.cgColor); c.setLineWidth(1)
                        c.addPath(UIBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: chipH / 2).cgPath); c.strokePath()
                        a.draw(at: CGPoint(x: x + 11, y: y + (chipH - a.size().height) / 2))
                        x += widths[i] + 8
                    }
                    y += chipH
                }
                y += 42
            }

            let rows = (n + lay.cols - 1) / lay.cols
            for (i, it) in list.enumerated() {
                let r = i / lay.cols, col = i % lay.cols
                let inRow = r == rows - 1 ? n - r * lay.cols : lay.cols
                let rowX = (canvas.width - (CGFloat(inRow) * iw + CGFloat(inRow - 1) * lay.gap)) / 2
                let cx = rowX + CGFloat(col) * (iw + lay.gap) + iw / 2
                let top = y + CGFloat(r) * (body.height + capH + lay.rowGap)
                drawScreen(p, s, it, renderer: renderer, band: bandImage, light: pal.light,
                           rect: CGRect(x: cx - body.width / 2, y: top, width: body.width, height: body.height), in: c)
                if s.captions { drawCaption(p, it, pal: pal, narrow: lay.narrow, centerX: cx, width: iw, top: top + body.height + 20) }
            }
            if s.credit {
                let cy = y + grid.height + 40
                let tw = creditA.size().width, total = 13 + 6 + tw
                let x0 = (canvas.width - total) / 2
                pal.sub.withAlphaComponent(0.8).setFill()
                Icons.band(in: CGRect(x: x0, y: cy + (creditA.size().height - 13) / 2, width: 13, height: 13)).fill()
                creditA.draw(at: CGPoint(x: x0 + 19, y: cy))
            }
        }
    }

    /// Підпис під екраном: назва і мітка стану (кольорова капсула зі значком; у вузькому режимі — лише значок)
    private static func drawCaption(_ p: FaceProject, _ it: Item, pal: Palette, narrow: Bool, centerX cx: CGFloat, width: CGFloat, top: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        para.alignment = .center
        let nameA = NSAttributedString(string: name(p, it.screen), attributes: [.font: UIFont.systemFont(ofSize: narrow ? 12 : 14.5, weight: .semibold), .foregroundColor: pal.fg, .paragraphStyle: para])
        let nh = nameA.size().height
        nameA.draw(with: CGRect(x: cx - width / 2, y: top, width: width, height: nh), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        guard let st = stateText(it) else { return }
        let col = pal.state(it)
        let pillY = top + nh + 7, pillH: CGFloat = 20, iconW: CGFloat = 12
        let textA = NSAttributedString(string: st, attributes: [.font: UIFont.systemFont(ofSize: 11.5, weight: .medium), .foregroundColor: col])
        let w = narrow ? 26 : 8 + iconW + 5 + textA.size().width + 9
        let r = CGRect(x: cx - w / 2, y: pillY, width: w, height: pillH)
        col.withAlphaComponent(pal.light ? 0.12 : 0.15).setFill()
        UIBezierPath(roundedRect: r, cornerRadius: pillH / 2).fill()
        let ir = CGRect(x: narrow ? cx - iconW / 2 : r.minX + 8, y: pillY + (pillH - iconW) / 2, width: iconW, height: iconW)
        col.setFill(); col.setStroke()
        Icons.state(it, in: ir)
        if !narrow { textA.draw(at: CGPoint(x: ir.maxX + 5, y: pillY + (pillH - textA.size().height) / 2)) }
    }

    private static func drawScreen(_ p: FaceProject, _ s: ShotSet, _ it: Item, renderer: FaceRenderer, band: UIImage?, light: Bool, rect: CGRect, in c: CGContext) {
        var screen = rect
        if let band {
            let k = rect.width / bandImg.width
            screen = CGRect(x: rect.minX + bandScreen.minX * k, y: rect.minY + bandScreen.minY * k, width: bandScreen.width * k, height: bandScreen.height * k)
        }
        // тінь-овал під екраном, ніби він стоїть на поверхні
        if s.shadow { groundShadow(c, under: rect, alpha: band != nil ? (light ? 0.35 : 0.7) : (light ? 0.35 : 0.75)) }
        band?.draw(in: rect)
        renderer.colorVariant = it.screen.color
        renderer.bluetoothOff = it.state == 1
        renderer.lowBattery = it.state == 2
        renderer.slotChoice = it.screen.widgets
        let (img, _) = renderer.render(theme: theme(p, it.screen), scale: max(1, ceil(screen.width * 2 / devW)))
        let r = band != nil || s.rounded ? CGFloat(p.meta.device.corner) * screen.width / CGFloat(p.meta.device.width) : 0
        let path = UIBezierPath(roundedRect: screen, cornerRadius: r)
        c.saveGState()
        c.addPath(path.cgPath); c.clip()
        img.draw(in: screen)
        c.restoreGState()
        if band == nil {
            // тонкий світлий обідок по краю капсули
            c.setStrokeColor(UIColor(white: 1, alpha: 0.08).cgColor); c.setLineWidth(1)
            c.addPath(UIBezierPath(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), cornerRadius: max(0, r - 0.5)).cgPath); c.strokePath()
        }
    }

    private static func groundShadow(_ c: CGContext, under r: CGRect, alpha: CGFloat) {
        let w = r.width * 0.76, h: CGFloat = 28
        let space = CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: space, colors: [UIColor(white: 0, alpha: 0.9 * alpha).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1]) else { return }
        c.saveGState()
        c.translateBy(x: r.midX, y: r.maxY)
        c.scaleBy(x: 1, y: h / w)
        c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w / 2 + 6, options: [])
        c.restoreGState()
    }

    /// Значки міток і підпису (малюються самі — у SF Symbols немає значка Bluetooth). Колір — поточний fill/stroke
    private enum Icons {
        /// Значок стану в квадраті r: Bluetooth від'єднано, батарея, місяць (AOD)
        static func state(_ it: Item, in r: CGRect) {
            let k = r.width / 18
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
            switch it.state {
            case 1:
                let b = UIBezierPath()
                b.move(to: pt(5, 5.6)); b.addLine(to: pt(12.4, 12)); b.addLine(to: pt(8.8, 15.2)); b.addLine(to: pt(8.8, 2.8))
                b.addLine(to: pt(12.4, 6)); b.addLine(to: pt(5, 12.4))
                b.move(to: pt(3.2, 3.2)); b.addLine(to: pt(14.8, 14.8))
                b.lineWidth = 1.9 * k; b.lineCapStyle = .round; b.lineJoinStyle = .round
                b.stroke()
            case 2:
                let body = UIBezierPath(roundedRect: CGRect(x: r.minX + 0.8 * k, y: r.minY + 3.8 * k, width: 14 * k, height: 10.4 * k), cornerRadius: 3 * k)
                body.lineWidth = 1.6 * k; body.stroke()
                UIBezierPath(roundedRect: CGRect(x: r.minX + 2.8 * k, y: r.minY + 5.8 * k, width: 2.6 * k, height: 6.4 * k), cornerRadius: 1 * k).fill()
                UIBezierPath(roundedRect: CGRect(x: r.minX + 15.6 * k, y: r.minY + 7.2 * k, width: 1.8 * k, height: 3.6 * k), cornerRadius: 0.9 * k).fill()
            default:
                // місяць: велике коло мінус зсунуте
                let m = UIBezierPath(ovalIn: CGRect(x: r.minX + 1.5 * k, y: r.minY + 1.5 * k, width: 15 * k, height: 15 * k))
                m.append(UIBezierPath(ovalIn: CGRect(x: r.minX + 6.5 * k, y: r.minY - 2 * k, width: 13 * k, height: 13 * k)))
                m.usesEvenOddFillRule = true
                let ctx = UIGraphicsGetCurrentContext()
                ctx?.saveGState()
                UIBezierPath(ovalIn: CGRect(x: r.minX + 1.5 * k, y: r.minY + 1.5 * k, width: 15 * k, height: 15 * k)).addClip()
                m.fill()
                ctx?.restoreGState()
            }
        }

        /// Браслет (як значок вкладки «Головна»), поле 26×26
        static func band(in r: CGRect) -> UIBezierPath {
            let k = r.width / 26
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: r.minX + ((x - 15) * 0.88889 + 13) * k, y: r.minY + ((y - 15) * 0.88889 + 13) * k)
            }
            let p = UIBezierPath()
            p.move(to: pt(11.3, 1.5)); p.addLine(to: pt(18.7, 1.5)); p.addLine(to: pt(19.4, 6.6)); p.addLine(to: pt(10.6, 6.6)); p.close()
            p.move(to: pt(10.6, 23.4)); p.addLine(to: pt(19.4, 23.4)); p.addLine(to: pt(18.7, 28.5)); p.addLine(to: pt(11.3, 28.5)); p.close()
            let a = pt(8, 5.6), b = pt(22, 24.4), ia = pt(10.9, 8.4), ib = pt(19.1, 21.6)
            p.append(UIBezierPath(roundedRect: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y), cornerRadius: 5.4 * 0.88889 * k))
            p.append(UIBezierPath(roundedRect: CGRect(x: ia.x, y: ia.y, width: ib.x - ia.x, height: ib.y - ia.y), cornerRadius: 1.1 * 0.88889 * k))
            p.usesEvenOddFillRule = true
            return p
        }
    }
}

private extension UIColor {
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    func mix(with o: UIColor, _ t: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a); o.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r + (r2 - r) * t, green: g + (g2 - g) * t, blue: b + (b2 - b) * t, alpha: 1)
    }
}
