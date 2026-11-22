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
        // стан — на самому екрані; обидва стани — два окремі екрани
        s.screens.flatMap { sc -> [Item] in
            if sc.bluetooth && sc.battery { return [Item(screen: sc, state: 1), Item(screen: sc, state: 2)] }
            return [Item(screen: sc, state: sc.bluetooth ? 1 : sc.battery ? 2 : 0)]
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

    /// Найбільша сторона готової картинки, pt (1920 px)
    static let maxSide: CGFloat = 960

    /// Стовпців: до 5 — один ряд, до 12 — два, далі по 6
    static func autoColumns(_ n: Int) -> Int { n <= 5 ? max(1, n) : n <= 12 ? (n + 1) / 2 : 6 }

    /// Задані формати — довша сторона 960 pt (1920 px), як і найбільша «Авто»
    static func fixedSize(_ f: ShotSet.Format) -> CGSize? {
        switch f {
        case .auto: return nil
        case .square: return CGSize(width: 960, height: 960)
        case .story: return CGSize(width: 540, height: 960)
        case .wide: return CGSize(width: 960, height: 540)
        }
    }

    /// Розкладка сітки: стовпці, ширина екрана, вузький режим (дрібніші підписи, стани — лише значком)
    struct Layout {
        var cols: Int, w: CGFloat, narrow: Bool
        /// Скільки екранів на картинці: два-три — розставлені ширше
        var n = 0
        /// Масштаб текстів (у вузьких форматах тексти менші, щоб уміщалися)
        var ts: CGFloat = 1
        /// Найширша мітка стану в повному вигляді (значок і текст)
        var pill: CGFloat = 0
        var gap: CGFloat { narrow ? 18 * ts : n <= 2 ? 72 * ts : n == 3 ? 46 * ts : 30 * ts }
        var rowGap: CGFloat { 30 * ts }
    }

    /// Ширина місця під екран: сам екран чи браслет, назва, мітка стану (у вузькому режимі мітка — лише значок)
    static func itemWidth(_ s: ShotSet, _ l: Layout) -> CGFloat {
        max(cellBody(s, w: l.w).width, s.captions ? (l.narrow ? l.w + 18 * l.ts : max(l.w + 40 * l.ts, l.pill)) : 0)
    }

    static func captionHeight(_ s: ShotSet, items: [Item], ts: CGFloat) -> CGFloat {
        guard s.captions else { return 0 }
        return (items.contains { stateText($0) != nil } ? 94 : 52) * ts
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

    /// Ширина мітки стану в повному вигляді
    private static func pillWidth(_ text: String, ts: CGFloat) -> CGFloat {
        let a = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17.8 * ts, weight: .medium)])
        return (12 + 20 + 7 + 14) * ts + a.size().width
    }

    // MARK: Складання

    static func compose(_ p: FaceProject, _ s: ShotSet) -> UIImage? {
        let list = Self.items(s)
        guard !list.isEmpty else { return nil }
        let bg = background(p, s.background)
        let pal = Palette(light: isLight(bg))
        let fixed = fixedSize(s.format)
        let pad = CGSize(width: 56, height: 48)

        // шапка; у вузьких форматах (9:16) усі тексти зменшуються, щоб рядок над назвою й назва вміщалися
        let above = s.above ?? autoAbove(p), title = s.title ?? autoTitle(p), below = s.below ?? autoBelow(p)
        let titleBase: CGFloat = fixed == nil ? 70 : s.format == .wide ? 48 : 53
        func aboveText(_ ts: CGFloat) -> NSAttributedString {
            NSAttributedString(string: above.uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 18.4 * ts, weight: .semibold), .foregroundColor: pal.sub, .kern: 3.4 * ts])
        }
        func titleText(_ ts: CGFloat) -> NSAttributedString {
            NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: titleBase * ts, weight: .heavy), .foregroundColor: pal.fg, .kern: -1 * ts])
        }
        let need = max(above.isEmpty ? 0 : aboveText(1).size().width + 2 * 58, title.isEmpty ? 0 : titleText(1).size().width)
        let ts: CGFloat = fixed.map { min(1, ($0.width - 2 * pad.width) / max(1, need)) } ?? 1
        let aboveA = aboveText(ts), titleA = titleText(ts)
        let chips = below.components(separatedBy: " · ").filter { !$0.isEmpty }
        let chipA = chips.map { NSAttributedString(string: $0, attributes: [.font: UIFont.systemFont(ofSize: 19.5 * ts, weight: .medium), .foregroundColor: pal.sub]) }
        let chipH: CGFloat = 36 * ts
        var header: CGFloat = 0
        if !above.isEmpty { header += aboveA.size().height }
        if !title.isEmpty { header += (header > 0 ? 14 * ts : 0) + titleA.size().height }
        if !chips.isEmpty { header += (header > 0 ? 16 * ts : 0) + chipH }
        if header > 0 { header += 46 * ts }
        let creditA = NSAttributedString(string: loc("Зроблено в BandFace"), attributes: [.font: UIFont.systemFont(ofSize: 19.2 * ts, weight: .medium), .foregroundColor: pal.sub.withAlphaComponent(0.8)])
        let footer: CGFloat = s.credit ? 44 * ts + creditA.size().height : 0

        // сітка
        let n = list.count
        let capH = captionHeight(s, items: list, ts: ts)
        let pill = list.compactMap { stateText($0) }.map { pillWidth($0, ts: ts) }.max() ?? 0
        func L(_ cols: Int, _ w: CGFloat, _ narrow: Bool) -> Layout { Layout(cols: cols, w: w, narrow: narrow, n: n, ts: ts, pill: pill) }
        var lay = L(autoColumns(n), screenWidth(s.size), false)
        var canvas: CGSize
        if let fx = fixed {
            // формат заданий: стовпці й ширина екрана — найбільші, що вміщаються з відступами
            let area = CGSize(width: fx.width - 2 * pad.width, height: fx.height - 2 * pad.height - header - footer)
            var best = L(1, 10, false)
            for narrow in [false, true] {
                for c in 1...n {
                    var lo: CGFloat = 10, hi: CGFloat = 400
                    for _ in 0..<24 {
                        let m = (lo + hi) / 2
                        let g = gridSize(s, L(c, m, narrow), n: n, capH: capH)
                        if g.width <= area.width && g.height <= area.height { lo = m } else { hi = m }
                    }
                    if lo > best.w { best = L(c, lo, narrow) }
                }
                // вузький режим — лише коли звичайний дає зовсім дрібні екрани
                if best.w >= 90 * ts { break }
            }
            best.w = min(floor(best.w * [1, 0.9, 0.78][max(0, min(2, s.size))]), 300)
            lay = best
            canvas = fx
        } else {
            let minW = max(640, need + 2 * pad.width)
            func fit(_ l: Layout) -> CGSize {
                let g = gridSize(s, l, n: n, capH: capH)
                return CGSize(width: max(g.width + 2 * pad.width, minW), height: g.height + 2 * pad.height + header + footer)
            }
            canvas = fit(lay)
            // не більше 1920 px по довшій стороні (960 pt): більші картинки месенджери однаково зменшують;
            // замість зменшення всієї картинки — менші екрани, тексти лишаються того ж розміру
            if max(canvas.width, canvas.height) > maxSide {
                for narrow in [false, true] {
                    var lo: CGFloat = 30, hi = screenWidth(s.size)
                    for _ in 0..<24 {
                        let m = (lo + hi) / 2
                        let c = fit(L(lay.cols, m, narrow))
                        if max(c.width, c.height) <= maxSide { lo = m } else { hi = m }
                    }
                    lay = L(lay.cols, floor(lo), narrow)
                    if lo >= 90 { break }
                }
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
            let y0 = (canvas.height - total) / 2
            var y = y0
            func centered(_ a: NSAttributedString, at yy: CGFloat) { a.draw(at: CGPoint(x: (canvas.width - a.size().width) / 2, y: yy)) }
            if header > 0 {
                if !above.isEmpty {
                    let sz = aboveA.size()
                    centered(aboveA, at: y)
                    // тонкі лінії з обох боків
                    c.setFillColor(pal.line.cgColor)
                    let ly = y + sz.height / 2
                    c.fill(CGRect(x: (canvas.width - sz.width) / 2 - 58 * ts, y: ly, width: 40 * ts, height: 1.5))
                    c.fill(CGRect(x: (canvas.width + sz.width) / 2 + (18 - 3.4) * ts, y: ly, width: 40 * ts, height: 1.5))
                    y += sz.height
                }
                if !title.isEmpty { if y > y0 { y += 14 * ts }; centered(titleA, at: y); y += titleA.size().height }
                if !chips.isEmpty {
                    if y > y0 { y += 16 * ts }
                    let widths = chipA.map { $0.size().width + 30 * ts }
                    var x = (canvas.width - (widths.reduce(0, +) + CGFloat(chips.count - 1) * 8 * ts)) / 2
                    for (i, a) in chipA.enumerated() {
                        let r = CGRect(x: x, y: y, width: widths[i], height: chipH)
                        c.setStrokeColor(pal.line.cgColor); c.setLineWidth(1)
                        c.addPath(UIBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: chipH / 2).cgPath); c.strokePath()
                        a.draw(at: CGPoint(x: x + 15 * ts, y: y + (chipH - a.size().height) / 2))
                        x += widths[i] + 8 * ts
                    }
                    y += chipH
                }
                y += 46 * ts
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
                if s.captions { drawCaption(p, it, pal: pal, narrow: lay.narrow, ts: ts, centerX: cx, width: iw, top: top + body.height + 22 * ts) }
            }
            if s.credit {
                let cy = y + grid.height + 44 * ts
                let icon = 20 * ts
                let tw = creditA.size().width, total = icon + 8 * ts + tw
                let x0 = (canvas.width - total) / 2
                pal.sub.withAlphaComponent(0.8).setFill()
                Icons.band(in: CGRect(x: x0, y: cy + (creditA.size().height - icon) / 2, width: icon, height: icon)).fill()
                creditA.draw(at: CGPoint(x: x0 + icon + 8 * ts, y: cy))
            }
        }
    }

    /// Значок стану картинкою (для кнопок під карткою): колір — шаблон, смужка заряду — свій колір
    static func stateIcon(_ state: Int, size: CGFloat, color: UIColor, low: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            color.setFill(); color.setStroke()
            Icons.draw(state: state, in: CGRect(x: 0, y: 0, width: size, height: size), low: low)
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Підпис під екраном: назва і мітка стану (кольорова капсула зі значком; у вузькому режимі — лише значок)
    private static func drawCaption(_ p: FaceProject, _ it: Item, pal: Palette, narrow: Bool, ts: CGFloat, centerX cx: CGFloat, width: CGFloat, top: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        para.alignment = .center
        let nameA = NSAttributedString(string: name(p, it.screen), attributes: [.font: UIFont.systemFont(ofSize: (narrow ? 16 : 23) * ts, weight: .semibold), .foregroundColor: pal.fg, .paragraphStyle: para])
        let nh = nameA.size().height
        nameA.draw(with: CGRect(x: cx - width / 2, y: top, width: width, height: nh), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        guard let st = stateText(it) else { return }
        let col = pal.state(it)
        let pillY = top + nh + 9 * ts, pillH: CGFloat = 32 * ts, iconW: CGFloat = 20 * ts
        let textA = NSAttributedString(string: st, attributes: [.font: UIFont.systemFont(ofSize: 17.8 * ts, weight: .medium), .foregroundColor: col])
        let w = narrow ? 38 * ts : pillWidth(st, ts: ts)
        let r = CGRect(x: cx - w / 2, y: pillY, width: w, height: pillH)
        col.withAlphaComponent(pal.light ? 0.12 : 0.15).setFill()
        UIBezierPath(roundedRect: r, cornerRadius: pillH / 2).fill()
        let ir = CGRect(x: narrow ? cx - iconW / 2 : r.minX + 12 * ts, y: pillY + (pillH - iconW) / 2, width: iconW, height: iconW)
        col.setFill(); col.setStroke()
        Icons.state(it, in: ir)
        if !narrow { textA.draw(at: CGPoint(x: ir.maxX + 7 * ts, y: pillY + (pillH - textA.size().height) / 2)) }
    }

    private static func drawScreen(_ p: FaceProject, _ s: ShotSet, _ it: Item, renderer: FaceRenderer, band: UIImage?, light: Bool, rect: CGRect, in c: CGContext) {
        var screen = rect
        if let band {
            let k = rect.width / bandImg.width
            screen = CGRect(x: rect.minX + bandScreen.minX * k, y: rect.minY + bandScreen.minY * k, width: bandScreen.width * k, height: bandScreen.height * k)
        }
        // тінь-овал під екраном, ніби він стоїть на поверхні
        if let band {
            // тінь браслета — за його формою (м'яка, донизу)
            c.saveGState()
            if s.shadow { c.setShadow(offset: CGSize(width: 0, height: 14), blur: 22, color: UIColor.black.withAlphaComponent(light ? 0.22 : 0.55).cgColor) }
            band.draw(in: rect)
            c.restoreGState()
        } else if s.shadow {
            groundShadow(c, under: rect, alpha: light ? 0.35 : 0.75)
        }
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
    enum Icons {
        /// Значок стану в квадраті r (поле 26×26): перекреслений Bluetooth, батарея з низьким зарядом, місяць (AOD).
        /// low — колір смужки заряду (у кнопках — червоний)
        static func state(_ it: Item, in r: CGRect, low: UIColor? = nil) { draw(state: it.state, aod: it.screen.aod, in: r, low: low) }

        static func draw(state: Int, aod: Bool = false, in r: CGRect, low: UIColor? = nil) {
            let k = r.width / 26
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: r.minX + x * k, y: r.minY + y * k, width: w * k, height: h * k) }
            switch state {
            case 1:
                let b = UIBezierPath()
                b.move(to: pt(8.2, 8.6)); b.addLine(to: pt(17.4, 16.6)); b.addLine(to: pt(12.8, 20.8)); b.addLine(to: pt(12.8, 5.2))
                b.addLine(to: pt(17.4, 9.4)); b.addLine(to: pt(8.2, 17.4))
                b.move(to: pt(5, 5)); b.addLine(to: pt(21, 21))
                b.lineWidth = 2.3 * k; b.lineCapStyle = .round; b.lineJoinStyle = .round
                b.stroke()
            case 2:
                let body = UIBezierPath(roundedRect: rect(3, 6.5, 19, 13), cornerRadius: 3 * k)
                body.append(UIBezierPath(roundedRect: rect(5.3, 8.8, 14.4, 8.4), cornerRadius: 0.9 * k))
                body.usesEvenOddFillRule = true
                body.fill()
                UIBezierPath(roundedRect: rect(23.2, 10.6, 1.4, 4.8), cornerRadius: 0.7 * k).fill()
                let ctx = UIGraphicsGetCurrentContext()
                ctx?.saveGState()
                if let low { low.setFill() }
                UIBezierPath(roundedRect: rect(6.8, 10.3, 3.4, 5.4), cornerRadius: 1 * k).fill()
                ctx?.restoreGState()
            default:
                // місяць: велике коло мінус зсунуте
                let ctx = UIGraphicsGetCurrentContext()
                ctx?.saveGState()
                UIBezierPath(ovalIn: rect(3, 3, 20, 20)).addClip()
                let m = UIBezierPath(ovalIn: rect(3, 3, 20, 20))
                m.append(UIBezierPath(ovalIn: rect(9.6, -1.6, 17.4, 17.4)))
                m.usesEvenOddFillRule = true
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
