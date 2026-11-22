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
    static func autoAbove(_ p: FaceProject) -> String { String(format: loc("Циферблат для Xiaomi %@"), p.meta.device.title) }
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

    // MARK: Розміри

    private static let devW: CGFloat = 212, devH: CGFloat = 520
    /// Рамка-браслет: картинка 480×1240, екран у ній — (97, 262, 287×704)
    private static let bandImg = CGSize(width: 480, height: 1240)
    private static let bandScreen = CGRect(x: 97, y: 262, width: 287, height: 704)

    /// Ширина екрана (pt) за розміром
    static func screenWidth(_ size: Int) -> CGFloat { [170, 150, 120][max(0, min(2, size))] }

    /// Рамка одного екрана (pt): без підпису
    static func cellBody(_ s: ShotSet, w: CGFloat) -> CGSize {
        if s.band { let k = w / bandScreen.width; return CGSize(width: bandImg.width * k, height: bandImg.height * k) }
        return CGSize(width: w, height: w * devH / devW)
    }

    static func captionHeight(_ s: ShotSet, items: [Item]) -> CGFloat {
        guard s.captions else { return 0 }
        return items.contains { stateText($0) != nil } ? 54 : 34
    }

    /// Стовпців: до 5 — один ряд, до 12 — два, далі по 6
    static func autoColumns(_ n: Int) -> Int { n <= 5 ? max(1, n) : n <= 12 ? (n + 1) / 2 : 6 }

    /// Розмір картинки в pt (пікселі — удвічі більше)
    static func canvasSize(_ s: ShotSet, header: CGFloat, footer: CGFloat, n: Int) -> CGSize? {
        switch s.format {
        case .auto: return nil
        case .square: return CGSize(width: 620, height: 620)
        case .story: return CGSize(width: 540, height: 960)
        case .wide: return CGSize(width: 960, height: 540)
        }
    }

    // MARK: Складання

    static func compose(_ p: FaceProject, _ s: ShotSet) -> UIImage? {
        let list = Self.items(s)
        guard !list.isEmpty else { return nil }
        let bg = background(p, s.background)
        let light = isLight(bg)
        let fg = light ? UIColor(white: 0.07, alpha: 1) : .white
        let sub = light ? AssetFactory.color("#6B6F78") : AssetFactory.color("#9AA0AA")
        let kick = light ? AssetFactory.color("#8A8F99") : AssetFactory.color("#8F97A6")

        // тексти шапки
        let above = (s.above ?? autoAbove(p)), title = (s.title ?? autoTitle(p)), below = (s.below ?? autoBelow(p))
        let aboveA = NSAttributedString(string: above.uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: kick, .kern: 2.2])
        let titleA = NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 56, weight: .heavy), .foregroundColor: fg, .kern: 0.5])
        let belowA = NSAttributedString(string: below, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: sub])
        var header: CGFloat = 0
        if !above.isEmpty { header += aboveA.size().height + 6 }
        if !title.isEmpty { header += titleA.size().height }
        if !below.isEmpty { header += belowA.size().height + 4 }
        if header > 0 { header += 36 }
        let creditA = NSAttributedString(string: loc("Зроблено в BandFace"), attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: fg.withAlphaComponent(0.5), .kern: 0.4])
        let footer: CGFloat = s.credit ? creditA.size().height + 34 : 0

        // сітка: стовпці й розмір екрана
        let n = list.count
        let capH = captionHeight(s, items: list)
        var w = screenWidth(s.size)
        var cols = autoColumns(n)
        let gapX: CGFloat = 34, gapY: CGFloat = 34
        let pad = CGSize(width: 60, height: 50)
        func gridSize(_ cols: Int, _ w: CGFloat) -> CGSize {
            let body = cellBody(s, w: w), rows = (n + cols - 1) / cols
            let cw = max(body.width, s.captions ? w + 40 : 0)
            return CGSize(width: CGFloat(cols) * cw + CGFloat(cols - 1) * gapX, height: CGFloat(rows) * (body.height + capH) + CGFloat(rows - 1) * gapY)
        }
        var canvas: CGSize
        if let fixed = canvasSize(s, header: header, footer: footer, n: n) {
            // формат заданий: стовпці й масштаб — щоб екрани були якнайбільші й уміщалися
            let area = CGSize(width: fixed.width - 2 * pad.width, height: fixed.height - 2 * pad.height - header - footer)
            var best: (cols: Int, w: CGFloat) = (1, 10)
            for c in 1...n {
                let g = gridSize(c, 100)
                let k = min(area.width / g.width, area.height / g.height)
                let wc = 100 * k * [1, 0.9, 0.75][max(0, min(2, s.size))]
                if wc > best.w { best = (c, wc) }
            }
            cols = best.cols; w = min(best.w, 260)
            canvas = fixed
        } else {
            let g = gridSize(cols, w)
            canvas = CGSize(width: max(g.width + 2 * pad.width, 640), height: g.height + 2 * pad.height + header + footer)
        }
        let grid = gridSize(cols, w)
        let body = cellBody(s, w: w)
        let cellW = (grid.width - CGFloat(cols - 1) * gapX) / CGFloat(cols)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = true
        let bandImage = s.band ? UIImage(named: light ? "ShotBandDark" : "ShotBandLight") : nil
        let renderer = FaceRenderer(p)
        if let t = s.time { var d = p.meta.demo; d.time = t; d.realTime = false; renderer.demo = d }

        return UIGraphicsImageRenderer(size: canvas, format: fmt).image { ctx in
            let c = ctx.cgContext
            // тло
            if bg.count > 1, let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bg.map(\.cgColor) as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: canvas.width * 0.3, y: 0), end: CGPoint(x: canvas.width * 0.7, y: canvas.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                c.setFillColor(bg[0].cgColor); c.fill(CGRect(origin: .zero, size: canvas))
            }
            // шапка і сітка — разом по центру
            let total = header + grid.height + footer
            var y = (canvas.height - total) / 2
            func center(_ a: NSAttributedString) {
                let sz = a.size()
                a.draw(at: CGPoint(x: (canvas.width - sz.width) / 2, y: y))
                y += sz.height
            }
            if header > 0 {
                if !above.isEmpty { center(aboveA); y += 6 }
                if !title.isEmpty { center(titleA) }
                if !below.isEmpty { y += 4; center(belowA) }
                y += 36
            }
            let x0 = (canvas.width - grid.width) / 2
            let rows = (n + cols - 1) / cols
            for (i, it) in list.enumerated() {
                let r = i / cols, col = i % cols
                // останній неповний ряд — по центру
                let inRow = r == rows - 1 ? n - r * cols : cols
                let rowX = x0 + (grid.width - (CGFloat(inRow) * cellW + CGFloat(inRow - 1) * gapX)) / 2
                let cx = rowX + CGFloat(col) * (cellW + gapX) + cellW / 2
                let top = y + CGFloat(r) * (body.height + capH + gapY)
                drawScreen(p, s, it, renderer: renderer, band: bandImage, light: light,
                           rect: CGRect(x: cx - body.width / 2, y: top, width: body.width, height: body.height), in: c)
                if s.captions {
                    let nameA = NSAttributedString(string: name(p, it.screen), attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: fg])
                    var ty = top + body.height + 14
                    let ns = nameA.size()
                    nameA.draw(in: CGRect(x: cx - min(ns.width, cellW + 20) / 2, y: ty, width: min(ns.width, cellW + 20), height: ns.height))
                    ty += ns.height + 3
                    if let st = stateText(it) {
                        let col: UIColor = it.state == 2 ? (light ? AssetFactory.color("#E07800") : AssetFactory.color("#FFC46B"))
                            : it.state == 1 || it.screen.aod ? (light ? AssetFactory.color("#2F7DF6") : AssetFactory.color("#9CC8FF")) : sub
                        let a = NSAttributedString(string: st, attributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: col])
                        a.draw(at: CGPoint(x: cx - a.size().width / 2, y: ty))
                    }
                }
            }
            if s.credit {
                y += grid.height + 34
                center(creditA)
            }
        }
    }

    private static func drawScreen(_ p: FaceProject, _ s: ShotSet, _ it: Item, renderer: FaceRenderer, band: UIImage?, light: Bool, rect: CGRect, in c: CGContext) {
        // екран
        var screen = rect
        if let band {
            let k = rect.width / bandImg.width
            screen = CGRect(x: rect.minX + bandScreen.minX * k, y: rect.minY + bandScreen.minY * k, width: bandScreen.width * k, height: bandScreen.height * k)
            c.saveGState()
            if s.shadow { c.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: UIColor.black.withAlphaComponent(light ? 0.18 : 0.45).cgColor) }
            band.draw(in: rect)
            c.restoreGState()
        }
        renderer.colorVariant = it.screen.color
        renderer.bluetoothOff = it.state == 1
        renderer.lowBattery = it.state == 2
        let (img, _) = renderer.render(theme: theme(p, it.screen), scale: max(1, ceil(screen.width * 2 / devW)))
        let r = band != nil || s.rounded ? CGFloat(p.meta.device.corner) * screen.width / CGFloat(p.meta.device.width) : 0
        let path = UIBezierPath(roundedRect: screen, cornerRadius: r)
        if band == nil, s.shadow {
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: UIColor.black.withAlphaComponent(light ? 0.18 : 0.45).cgColor)
            c.setFillColor(UIColor.black.cgColor)
            c.addPath(path.cgPath); c.fillPath()
            c.restoreGState()
        }
        c.saveGState()
        c.addPath(path.cgPath); c.clip()
        img.draw(in: screen)
        c.restoreGState()
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
