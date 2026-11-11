// SPDX-License-Identifier: MIT
// «Форма» для чисел: одна фігура (коло, капсула, прямокутник) навколо всього числа, а не під кожною цифрою.
// Цифри числа на браслеті — окремі картинки, тож фігура — окремий шар-картинка під числом. Він не вибирається
// на полотні й у списку шарів і після кожної правки сам стає під своїм числом (під ширину всіх його цифр).

import UIKit
import FaceCompiler

enum NumberBadge {
    static let suffix = "_numbg"

    static func isBadge(_ layout: XNode) -> Bool { (layout.string("ref") ?? "").hasSuffix(suffix) }

    /// Намалювати (або прибрати, якщо форми немає) фігуру під числом
    static func update(_ p: FaceProject, number res: XNode, gen: Generator) {
        let name = res.string("name") ?? ""
        let bg = name + suffix
        remove(p, bg)
        guard !gen.badge.isEmpty, let box = contentSize(p, res), let img = AssetFactory.badgeImage(gen, w: box.width, h: box.height) else { return }
        let src = "\(bg).png"
        p.setFile(src, img.png)
        let e = XNode("Image")
        e.set("name", bg).set("src", src).set("compressMethod", "RLEReversed").set("format", img.bestFormat).set("recolorEnable", bool: false)
        p.resources.kids.append(e)
        for t in 0..<p.themes.count {
            guard let th = p.theme(t) else { continue }
            for l in th.all("Layout") where l.string("ref") == "@" + name {
                let b = XNode("Layout"); b.set("ref", "@" + bg)
                if let i = th.kids.firstIndex(where: { $0 === l }) { th.kids.insert(b, at: i) }
            }
        }
        sync(p)
    }

    private static func remove(_ p: FaceProject, _ bg: String) {
        for t in 0..<p.themes.count { p.theme(t)?.kids.removeAll { $0.tag == "Layout" && $0.string("ref") == "@" + bg } }
        if let old = p.resource(named: bg) {
            if let s = old.string("src") { p.removeFile(s) }
            p.resources.kids.removeAll { $0 === old }
        }
    }

    /// Розмір числа з усіма його цифрами (totalDigits; без нього — 4)
    private static func contentSize(_ p: FaceProject, _ res: XNode) -> CGSize? {
        guard let arr = p.resource(ref: res.string("ref")), let src = arr.all("Image").first?.string("src"),
              let d = p.file(src), let u = UIImage(data: d), let cg = u.cgImage else { return nil }
        let n = max(1, Int(res.int("totalDigits")) > 0 ? Int(res.int("totalDigits")) : 4)
        let space = CGFloat(Int8(truncatingIfNeeded: Int(res.int("space"))))
        return CGSize(width: CGFloat(n * cg.width) + CGFloat(n - 1) * space, height: CGFloat(cg.height))
    }

    /// Після кожної правки: фігура — під своїм числом (одразу перед ним у шарах), по центру всіх його цифр.
    /// Фігура без числа прибирається.
    static func sync(_ p: FaceProject) {
        for t in 0..<p.themes.count {
            guard let th = p.theme(t) else { continue }
            for b in th.all("Layout") where isBadge(b) {
                let bgName = String((b.string("ref") ?? "").dropFirst())
                let name = String(bgName.dropLast(suffix.count))
                guard let num = th.all("Layout").first(where: { $0.string("ref") == "@" + name }), let res = p.resource(named: name),
                      let size = contentSize(p, res), let img = p.resource(named: bgName)?.string("src").flatMap({ p.file($0) }).flatMap({ UIImage(data: $0)?.cgImage })
                else { th.kids.removeAll { $0 === b }; continue }
                // x макета числа — точка прив'язки (left / center / right), як на браслеті
                var x = CGFloat(num.int("x"))
                switch res.string("align") {
                case "right", "flex-end": x -= size.width
                case "center": x -= size.width / 2
                default: break
                }
                let cx = x + size.width / 2, cy = CGFloat(num.int("y")) + size.height / 2
                b.set("x", int: Int((cx - CGFloat(img.width) / 2).rounded())).set("y", int: Int((cy - CGFloat(img.height) / 2).rounded()))
                // одразу під числом
                if let bi = th.kids.firstIndex(where: { $0 === b }), let ni = th.kids.firstIndex(where: { $0 === num }), bi != ni - 1 {
                    th.kids.remove(at: bi)
                    let ni2 = th.kids.firstIndex(where: { $0 === num }) ?? th.kids.count
                    th.kids.insert(b, at: ni2)
                }
            }
        }
    }
}
