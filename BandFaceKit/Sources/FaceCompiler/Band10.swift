// SPDX-License-Identifier: MIT
// Обмеження Xiaomi Smart Band 10 / 11, знайдені на справжніх циферблатах (Б-1: циферблат із фото-фоном зламав прошивку):
//  • у 11 циферблатах Band 10 (14 382 картинки) усі зображення — indexed8; RGB565A8 і RGBA32 не трапляються жодного разу;
//  • DataItemText немає в жодному з 400+ відомих циферблатів — на браслеті не перевірено.
// Тут: зменшення до 256 кольорів (разом із прозорістю), виправлення сховища перед збиранням і перелік ризиків.

import Foundation

public enum Band10 {
    @inline(__always) static func key(_ p: [UInt8], _ o: Int) -> Int {
        Int(p[o] >> 3) << 13 | Int(p[o + 1] >> 3) << 8 | Int(p[o + 2] >> 3) << 3 | Int(p[o + 3] >> 5)
    }
    @inline(__always) static func ch(_ k: Int, _ c: Int) -> Int {
        c == 0 ? k >> 13 : c == 1 ? (k >> 8) & 31 : c == 2 ? (k >> 3) & 31 : k & 7
    }

    /// RGBA w×h, що вміщається в indexed8 (≤ 256 різних RGBA). Якщо вже вміщається — ті самі пікселі.
    /// Медіанний поділ у просторі R5 G5 B5 A3; майже прозорі пікселі (альфа < 8) — один прозорий колір.
    public static func to256(_ px: [UInt8], _ w: Int, _ h: Int) -> [UInt8] {
        let n = w * h
        guard n > 0, FaceCatalog.colorCount(px) > 256 else { return px }
        let bins = 1 << 18
        var count = [Int](repeating: 0, count: bins)
        var sr = count, sg = count, sb = count, sa = count
        var clear = false
        for i in 0..<n {
            let o = i * 4, a = Int(px[o + 3])
            if a < 8 { clear = true; continue }
            let k = key(px, o)
            count[k] += 1; sr[k] += Int(px[o]); sg[k] += Int(px[o + 1]); sb[k] += Int(px[o + 2]); sa[k] += a
        }
        var boxes: [[Int]] = [(0..<bins).filter { count[$0] > 0 }]
        let colors = clear ? 255 : 256
        while boxes.count < colors {
            var best = -1, bestScore = 0, bestCh = 0
            for (i, box) in boxes.enumerated() where box.count > 1 {
                var lo = [99, 99, 99, 99], hi = [-1, -1, -1, -1], weight = 0
                for k in box {
                    for c in 0..<4 { let v = ch(k, c); if v < lo[c] { lo[c] = v }; if v > hi[c] { hi[c] = v } }
                    weight += count[k]
                }
                var c0 = 0, span = -1
                // альфа має 8 рівнів проти 32 у кольорів — зважуємо, щоб її різниця важила так само
                for c in 0..<4 { let s = (hi[c] - lo[c]) * (c == 3 ? 4 : 1); if s > span { span = s; c0 = c } }
                let score = span * weight
                if score > bestScore { bestScore = score; best = i; bestCh = c0 }
            }
            guard best >= 0 else { break }
            let bc = bestCh
            let sorted = boxes[best].sorted { ch($0, bc) < ch($1, bc) }
            let total = sorted.reduce(0) { $0 + count[$1] }
            var acc = 0, cut = 1
            for (j, k) in sorted.enumerated() {
                acc += count[k]
                if acc * 2 >= total { cut = max(1, min(sorted.count - 1, j + 1)); break }
            }
            boxes[best] = Array(sorted[..<cut])
            boxes.append(Array(sorted[cut...]))
        }
        var map = [Int](repeating: 0, count: bins)
        var pal = [UInt8](repeating: 0, count: boxes.count * 4)
        for (i, box) in boxes.enumerated() {
            var r = 0, g = 0, b = 0, a = 0, weight = 0
            for k in box { r += sr[k]; g += sg[k]; b += sb[k]; a += sa[k]; weight += count[k]; map[k] = i }
            weight = max(weight, 1)
            pal[i * 4] = UInt8(r / weight); pal[i * 4 + 1] = UInt8(g / weight); pal[i * 4 + 2] = UInt8(b / weight); pal[i * 4 + 3] = UInt8(a / weight)
        }
        var out = [UInt8](repeating: 0, count: px.count)
        for i in 0..<n {
            let o = i * 4
            if px[o + 3] < 8 { continue }   // прозорий: 0,0,0,0
            let c = map[key(px, o)] * 4
            out[o] = pal[c]; out[o + 1] = pal[c + 1]; out[o + 2] = pal[c + 2]; out[o + 3] = pal[c + 3]
        }
        return out
    }

    /// Перед збиранням для Band 10/11: кожне Image / ImageArray не у форматі indexed8 стає indexed8
    /// (картинки зменшуються до 256 кольорів). Змінює лише передане сховище. Повертає кількість виправлених ресурсів.
    @discardableResult
    public static func fixImages(_ st: MemoryStorage) -> Int {
        guard let xml = st.files["manifest.xml"], let root = try? XML.parse([UInt8](xml)),
              let res = root.first("Resources") else { return 0 }
        var fixed = 0
        for e in res.elements where (e.tag == "Image" || e.tag == "ImageArray") && e.string("format") != "indexed8" {
            let srcs = e.tag == "Image" ? [e.string("src")].compactMap { $0 } : e.all("Image").compactMap { $0.string("src") }
            for s in srcs {
                guard let d = st.read(s), let img = ImageDecoder.decode([UInt8](d)) else { continue }
                try? st.write(s, Data(PNG.encode(img.w, img.h, to256(img.rgba, img.w, img.h))))
            }
            e.set("format", "indexed8")
            fixed += 1
        }
        if fixed > 0 { st.files["manifest.xml"] = Data(XML.print(root)) }
        return fixed
    }

    /// Елементи, яких немає в жодному відомому циферблаті Band 10 (не перевірені на браслеті): тег → кількість.
    public static func untested(_ root: XNode) -> [String: Int] {
        var o: [String: Int] = [:]
        for e in root.first("Resources")?.elements ?? [] where e.tag == "DataItemText" { o[e.tag, default: 0] += 1 }
        return o
    }
}
