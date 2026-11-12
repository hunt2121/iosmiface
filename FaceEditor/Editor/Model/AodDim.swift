// SPDX-License-Identifier: MIT
// Приглушення «Завжди на екрані»: чорний напівпрозорий шар на весь екран поверх усіх елементів AOD
// (так зроблено і в готових циферблатах, напр. BigWatch: 212×520, прозорість 84 з 255 ≈ 33 %).

import Foundation
import FaceCompiler

enum AodDim {
    static let aodTheme = 1
    private static var cache: [String: Int] = [:]

    /// Прозорість (1…254) шару-приглушення або 0, якщо шар — не приглушення
    static func alpha(_ p: FaceProject, _ layout: XNode) -> Int {
        guard layout.int("x") == 0, layout.int("y") == 0, let res = p.element(of: layout), res.tag == "Image",
              let src = res.string("src"), let d = p.file(src) else { return 0 }
        let key = "\(src)|\(d.count)|\(d.suffix(48).base64EncodedString())|\(p.meta.device.width)x\(p.meta.device.height)"
        if let a = cache[key] { return a }
        let a = measure(d, p.meta.device.width, p.meta.device.height)
        if cache.count > 200 { cache.removeAll() }
        cache[key] = a
        return a
    }

    private static func measure(_ d: Data, _ w: Int, _ h: Int) -> Int {
        guard let png = PNG.decode([UInt8](d)), png.w >= w, png.h >= h, png.rgba.count >= 4 else { return 0 }
        let px = png.rgba
        let a = Int(px[3])
        guard a != 0, a != 255 else { return 0 }
        var i = 0
        while i + 3 < px.count {
            if px[i] > 8 || px[i + 1] > 8 || px[i + 2] > 8 || abs(Int(px[i + 3]) - a) > 2 { return 0 }
            i += 4
        }
        return a
    }

    /// Службові шари, яких не видно серед шарів і які не вибираються: приглушення AOD і фігура під числом
    static func isDim(_ p: FaceProject, _ layout: XNode, theme: Int) -> Bool {
        NumberBadge.isBadge(layout) || (theme == aodTheme && alpha(p, layout) > 0)
    }

    /// Шар-приглушення в AOD (верхній з таких) або nil
    static func find(_ p: FaceProject) -> XNode? {
        guard p.themes.count > 1 else { return nil }
        return p.layouts(aodTheme).last { alpha(p, $0) > 0 }
    }

    /// Сила приглушення у відсотках (0 — немає)
    static func percent(_ p: FaceProject) -> Int {
        guard let l = find(p) else { return 0 }
        return Int((Double(alpha(p, l)) * 100 / 255).rounded())
    }

    /// Ставить приглушення (0 — прибирає шар)
    static func set(_ p: FaceProject, percent: Int) {
        guard let th = p.theme(aodTheme) else { return }
        var cur = find(p)
        if percent <= 0 {
            if let c = cur { ElementFactory.delete(p, layout: c, theme: aodTheme) }
            return
        }
        let alpha = UInt8(max(1, min(254, Int((Double(percent) * 255 / 100).rounded()))))
        let w = p.meta.device.width, h = p.meta.device.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var i = 3
        while i < px.count { px[i] = alpha; i += 4 }
        let img = RGBAImage(w: w, h: h, px: px)
        if let c = cur, let res = p.element(of: c) {
            if ElementFactory.layouts(of: res, in: p).count > 1 { ElementFactory.delete(p, layout: c, theme: aodTheme); cur = nil }
            else { ElementFactory.replaceImage(p, res, img) }
        }
        if cur == nil {
            let name = ElementFactory.addImageResource(p, img, base: "aod_dim")
            let l = XNode("Layout")
            l.set("ref", "@" + name).set("x", int: 0).set("y", int: 0)
            th.kids.append(l)
        }
        keepOnTop(p)
    }

    /// Позначка шару AOD «над приглушенням» (лише для редактора; компілятор читає в Layout тільки ref, x, y)
    static let aboveKey = "aboveDim"

    static func isAbove(_ l: XNode) -> Bool { l.bool(aboveKey) }

    /// Підняти шар над приглушенням або повернути під нього
    static func setAbove(_ p: FaceProject, _ l: XNode, _ on: Bool) {
        if on { l.set(aboveKey, "true") } else { l.remove(aboveKey) }
        keepOnTop(p)
    }

    /// Порядок AOD: звичайні шари, потім приглушення, потім шари «над приглушенням» (фігура під числом — разом із числом)
    static func keepOnTop(_ p: FaceProject) {
        guard let th = p.theme(aodTheme), let dim = find(p) else { return }
        let lays = th.kids.filter { !$0.isComment && $0.tag == "Layout" && $0 !== dim }
        var above: [XNode] = []
        for (i, l) in lays.enumerated() {
            let next = i + 1 < lays.count ? lays[i + 1] : nil
            if isAbove(l) || (NumberBadge.isBadge(l) && next.map(isAbove) == true) { above.append(l) }
        }
        let tail = [dim] + above
        let cur = th.kids.filter { !$0.isComment && $0.tag == "Layout" }.suffix(tail.count)
        if cur.count == tail.count && zip(cur, tail).allSatisfy({ $0 === $1 }) { return }
        th.kids.removeAll { k in tail.contains { $0 === k } }
        th.kids.append(contentsOf: tail)
    }

    /// Відкритий .bin / старий проєкт: шари, що стоять вище за приглушення, позначаються «над приглушенням»
    static func markFromOrder(_ p: FaceProject) {
        guard let th = p.theme(aodTheme), let dim = find(p) else { return }
        let lays = th.kids.filter { !$0.isComment && $0.tag == "Layout" }
        guard !lays.contains(where: isAbove), let i = lays.firstIndex(where: { $0 === dim }) else { return }
        for l in lays[(i + 1)...] where !NumberBadge.isBadge(l) && alpha(p, l) == 0 { l.set(aboveKey, "true") }
    }
}

extension FaceProject {
    /// Верхній шар екрана без приглушення AOD (його не вибирають — він у властивостях циферблата)
    func topLayout(_ theme: Int) -> XNode? { layouts(theme).last { !AodDim.isDim(self, $0, theme: theme) } }
    /// Шари для списку й вибору: без приглушення AOD
    func editableLayouts(_ theme: Int) -> [XNode] { layouts(theme).filter { !AodDim.isDim(self, $0, theme: theme) } }
}
