// SPDX-License-Identifier: MIT
// Анімоване превʼю як справжній GIF: спільна палітра на всі кадри (медіанний поділ), перший кадр цілий,
// далі — лише прямокутник змін, де незмінні пікселі прозорі. Файл на сотні КБ замість десятків МБ кадрів у пам'яті;
// показ — покадрове декодування (CGAnimateImageDataWithBlock), тож у пам'яті один кадр.

import Foundation
import CoreGraphics

enum GIFEncoder {
    /// Кадр: RGBA без розмноження (альфа ігнорується — превʼю непрозоре) і тривалість у мс
    struct Frame {
        let rgba: [UInt8]
        let durationMs: Int
    }

    /// Кодує кадри w×h. Якщо файл більший за `budget`, палітра зменшується (255 → 192 → 128 → 96 → 64).
    static func encode(_ frames: [Frame], width w: Int, height h: Int, budget: Int = 480 << 10) -> Data? {
        guard !frames.isEmpty, w > 0, h > 0, frames.allSatisfy({ $0.rgba.count == w * h * 4 }) else { return nil }
        var best: Data?
        for colors in [255, 192, 128, 96, 64] {
            let d = encode(frames, w, h, colors: colors)
            best = d
            if d.count <= budget { break }
        }
        return best
    }

    // MARK: - Палітра

    private static func bin(_ p: [UInt8], _ i: Int) -> Int {
        (Int(p[i]) >> 3) << 10 | (Int(p[i + 1]) >> 3) << 5 | Int(p[i + 2]) >> 3
    }

    /// Один кадр → палітра до 256 кольорів і індекси (для палітрового PNG превʼю).
    static func indexed(_ rgba: [UInt8], colors: Int = 256) -> (indices: [UInt8], palette: [UInt8]) {
        let (pal, map) = palette([Frame(rgba: rgba, durationMs: 0)], colors: colors)
        var out = [UInt8](repeating: 0, count: rgba.count / 4)
        for i in 0..<out.count { out[i] = map[bin(rgba, i * 4)] }
        return (out, pal)
    }

    /// Медіанний поділ гістограми 5-5-5 усіх кадрів: палітра й відповідність «бін → індекс».
    private static func palette(_ frames: [Frame], colors: Int) -> ([UInt8], [UInt8]) {
        var count = [Int](repeating: 0, count: 32768)
        var sr = [Int](repeating: 0, count: 32768), sg = sr, sb = sr
        for f in frames {
            let p = f.rgba
            var i = 0
            while i < p.count {
                let k = bin(p, i)
                count[k] += 1; sr[k] += Int(p[i]); sg[k] += Int(p[i + 1]); sb[k] += Int(p[i + 2])
                i += 4
            }
        }
        func ch(_ k: Int, _ c: Int) -> Int { c == 0 ? k >> 10 : c == 1 ? (k >> 5) & 31 : k & 31 }
        var boxes: [[Int]] = [(0..<32768).filter { count[$0] > 0 }]
        while boxes.count < colors {
            var best = -1, bestScore = 0, bestCh = 0
            for (i, box) in boxes.enumerated() where box.count > 1 {
                var lo = [31, 31, 31], hi = [0, 0, 0], n = 0
                for k in box {
                    for c in 0..<3 { lo[c] = min(lo[c], ch(k, c)); hi[c] = max(hi[c], ch(k, c)) }
                    n += count[k]
                }
                let spans = (0..<3).map { hi[$0] - lo[$0] }
                let c = spans.firstIndex(of: spans.max()!)!
                if spans[c] * n > bestScore { bestScore = spans[c] * n; best = i; bestCh = c }
            }
            guard best >= 0 else { break }
            let sorted = boxes[best].sorted { ch($0, bestCh) < ch($1, bestCh) }
            let total = sorted.reduce(0) { $0 + count[$1] }
            var acc = 0, cut = 1
            for (j, k) in sorted.enumerated() {
                acc += count[k]
                if acc * 2 >= total { cut = max(1, min(sorted.count - 1, j + 1)); break }
            }
            boxes[best] = Array(sorted[..<cut])
            boxes.append(Array(sorted[cut...]))
        }
        var pal = [UInt8](repeating: 0, count: 768)   // 256 кольорів; при colors = 256 індекс 255 теж колір
        var map = [UInt8](repeating: 0, count: 32768)
        for (i, box) in boxes.enumerated() {
            var r = 0, g = 0, b = 0, n = 0
            for k in box { r += sr[k]; g += sg[k]; b += sb[k]; n += count[k]; map[k] = UInt8(i) }
            n = max(n, 1)
            pal[i * 3] = UInt8(r / n); pal[i * 3 + 1] = UInt8(g / n); pal[i * 3 + 2] = UInt8(b / n)
        }
        return (pal, map)
    }

    // MARK: - Файл

    private static let transparent: UInt8 = 255

    private static func encode(_ frames: [Frame], _ w: Int, _ h: Int, colors: Int) -> Data {
        let (pal, map) = palette(frames, colors: min(colors, 255))
        let indexed: [[UInt8]] = frames.map { f in
            var out = [UInt8](repeating: 0, count: w * h)
            for i in 0..<(w * h) { out[i] = map[bin(f.rgba, i * 4)] }
            return out
        }
        var b = Data("GIF89a".utf8)
        func u16(_ v: Int) { b.append(UInt8(v & 255)); b.append(UInt8(v >> 8 & 255)) }
        u16(w); u16(h)
        b.append(0xF7); b.append(0); b.append(0)          // глобальна палітра на 256 кольорів
        b.append(contentsOf: pal)
        b.append(contentsOf: [0x21, 0xFF, 0x0B] + Array("NETSCAPE2.0".utf8) + [0x03, 0x01, 0x00, 0x00, 0x00])   // без кінця

        // кадри: перший цілий; далі прямокутник змін, незмінні пікселі прозорі; однакові кадри зливаються
        var prev: [UInt8]?
        var pending: (x: Int, y: Int, w: Int, h: Int, px: [UInt8], ms: Int, tr: Bool)?
        func flush() {
            guard let f = pending else { return }
            b.append(contentsOf: [0x21, 0xF9, 0x04, UInt8(1 << 2 | (f.tr ? 1 : 0))])   // не прибирати попередній кадр
            u16(max(2, (f.ms + 5) / 10)); b.append(f.tr ? transparent : 0); b.append(0)
            b.append(0x2C); u16(f.x); u16(f.y); u16(f.w); u16(f.h); b.append(0)
            b.append(8)
            let lz = lzw(f.px)
            var i = 0
            while i < lz.count {
                let n = min(255, lz.count - i)
                b.append(UInt8(n)); b.append(contentsOf: lz[i..<(i + n)]); i += n
            }
            b.append(0)
        }
        for (fi, cur) in indexed.enumerated() {
            let ms = frames[fi].durationMs
            guard let p = prev else {
                pending = (0, 0, w, h, cur, ms, false); prev = cur; continue
            }
            var x0 = w, y0 = h, x1 = -1, y1 = -1
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where cur[row + x] != p[row + x] {
                    if x < x0 { x0 = x }; if x > x1 { x1 = x }; if y < y0 { y0 = y }; if y > y1 { y1 = y }
                }
            }
            if x1 < 0 { pending?.ms += ms; continue }   // кадр не змінився — довше показуємо попередній
            flush()
            let fw = x1 - x0 + 1, fh = y1 - y0 + 1
            var sub = [UInt8](repeating: transparent, count: fw * fh)
            for y in 0..<fh {
                let s = (y0 + y) * w + x0
                for x in 0..<fw where cur[s + x] != p[s + x] { sub[y * fw + x] = cur[s + x] }
            }
            pending = (x0, y0, fw, fh, sub, ms, true)
            prev = cur
        }
        flush()
        b.append(0x3B)
        return b
    }

    /// LZW із мінімальним кодом 8 біт. Таблиця з «поколіннями»: очищення без перезапису 1 млн комірок.
    private static func lzw(_ px: [UInt8]) -> [UInt8] {
        let clear = 256, eoi = 257
        var out: [UInt8] = []
        out.reserveCapacity(px.count / 2)
        var acc = 0, bits = 0
        func emit(_ code: Int, _ size: Int) {
            acc |= code << bits; bits += size
            while bits >= 8 { out.append(UInt8(acc & 255)); acc >>= 8; bits -= 8 }
        }
        var table = [Int32](repeating: 0, count: 4096 * 256)
        var gen: Int32 = 1
        var size = 9, next = eoi + 1
        emit(clear, size)
        guard var prefix = px.first.map(Int.init) else { emit(eoi, size); return out }
        for i in 1..<max(1, px.count) where i < px.count {
            let k = Int(px[i])
            let slot = prefix << 8 | k
            let e = table[slot]
            if e >> 12 == gen { prefix = Int(e & 4095); continue }
            emit(prefix, size)
            if next < 4096 {
                table[slot] = gen << 12 | Int32(next)
                next += 1
                if next > (1 << size), size < 12 { size += 1 }
            } else {
                emit(clear, size)
                gen += 1; size = 9; next = eoi + 1
            }
            prefix = k
        }
        emit(prefix, size)
        emit(eoi, size)
        if bits > 0 { out.append(UInt8(acc & 255)) }
        return out
    }
}
