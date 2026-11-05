// SPDX-License-Identifier: MIT
// RLE «RLEReversed» і формати пікселів (порт 0x140042ec0 / кодеків зображень WatchfaceCompiler).

enum RLE {
    static let magic: UInt32 = 0x5AA5_21E0

    /// Розпакування потоку: c&0x80 — c&0x7F літеральних елементів, інакше повтор елемента c&0x7F разів.
    static func decompress(_ src: [UInt8], from start: Int, outSize: Int, elem E: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(outSize)
        var i = start
        let n = src.count
        while i < n {
            let c = Int(src[i]); i += 1
            let k = c & 0x7F
            if c & 0x80 != 0 {
                let m = k * E
                out.append(contentsOf: src.slice(i, min(m, max(0, n - i))))
                i += m
            } else {
                if k > 0 {
                    let el = src.slice(i, E)
                    for _ in 0..<k { out.append(contentsOf: el) }
                }
                i += E
            }
        }
        if out.count >= outSize { return Array(out.prefix(outSize)) }
        return out + [UInt8](repeating: 0, count: outSize - out.count)
    }

    @inline(__always) private static func eq(_ s: [UInt8], _ a: Int, _ b: Int, _ E: Int) -> Bool {
        let n = s.count
        for k in 0..<E {
            let x = a + k < n ? s[a + k] : nil
            let y = b + k < n ? s[b + k] : nil
            if x != y { return false }
        }
        return true
    }

    /// Точний порт 0x140042ec0 (мінімальна серія 5, максимум 127, з особливостями літерального сканування).
    static func compress(_ src: [UInt8], elem E: Int, minRun: Int = 5) -> [UInt8] {
        let n = src.count
        var out: [UInt8] = []
        var pos = 0
        if n == 0 { return out }
        while pos < n {
            if n < E { break }
            var run = 0, off = 0
            if pos < n {
                while true {
                    if !eq(src, pos + off, pos, E) { break }
                    run += 1
                    if run == 0x7F { break }
                    off += E
                    if off + pos >= n { break }
                }
            }
            if run == 0 { break }
            if run < minRun {
                var r14 = 0, cnt = 0, eqc = 0, prev = pos
                while true {
                    let cur = pos + r14
                    eqc += 1
                    if eq(src, cur, prev, E) {
                        if eqc > minRun { break }
                    } else {
                        cnt += eqc; prev = cur; eqc = 0
                        if cnt >= 0x7F { cnt = 0x7F; break }
                    }
                    r14 += E
                    if r14 + pos >= n {
                        cnt += eqc
                        if cnt >= 0x7F { cnt = 0x7F }
                        break
                    }
                }
                out.append(UInt8((cnt & 0x7F) | 0x80))
                out.append(contentsOf: src.slice(pos, min(cnt * E, n - pos)))
                pos += cnt * E
            } else {
                out.append(UInt8(run))
                out.append(contentsOf: src.slice(pos, min(E, n - pos)))
                pos += run * E
            }
        }
        return out
    }

    /// Блок «E0 21 A5 5A, (E | size<<4), потік».
    static func block(_ raw: [UInt8], elem E: Int) -> [UInt8] {
        var w = ByteWriter()
        w.u32(magic)
        w.u32(Int((UInt32(E) & 0xF) | ((UInt32(truncatingIfNeeded: raw.count) << 4) & 0x0FFF_FFFF)))
        w.append(compress(raw, elem: E))
        return w.bytes
    }
}

/// Формати пікселів: 0 — RGBA32 (BGRA у файлі), 6 — RGB565A8, 0x10 — indexed8.
enum PixelFormat {
    static func name(_ f: UInt8) -> String? {
        switch f { case 0: return "RGBA32"; case 6: return "RGB565A8"; case 0x10: return "indexed8"; default: return nil }
    }
    static func bpp(_ f: UInt8) -> Int { f == 0 ? 4 : (f == 6 ? 3 : 1) }

    /// Сирі дані -> RGBA8888.
    static func decode(_ fmt: UInt8, _ raw: [UInt8], _ w: Int, _ h: Int) throws -> [UInt8] {
        let n = w * h
        var out = [UInt8](repeating: 0, count: n * 4)
        switch fmt {
        case 0:
            for i in 0..<n {
                out[i * 4] = raw.u8(i * 4 + 2); out[i * 4 + 1] = raw.u8(i * 4 + 1)
                out[i * 4 + 2] = raw.u8(i * 4); out[i * 4 + 3] = raw.u8(i * 4 + 3)
            }
        case 6:
            for i in 0..<n {
                let v = Int(raw.u16(i * 3))
                let r5 = v >> 11, g6 = (v >> 5) & 0x3F, b5 = v & 0x1F
                out[i * 4] = UInt8((r5 * 255 + 15) / 31)
                out[i * 4 + 1] = UInt8((g6 * 255 + 31) / 63)
                out[i * 4 + 2] = UInt8((b5 * 255 + 15) / 31)
                out[i * 4 + 3] = raw.u8(i * 3 + 2)
            }
        case 0x10:
            for i in 0..<n {
                let p = Int(raw.u8(1024 + i)) * 4
                out[i * 4] = raw.u8(p + 2); out[i * 4 + 1] = raw.u8(p + 1)
                out[i * 4 + 2] = raw.u8(p); out[i * 4 + 3] = raw.u8(p + 3)
            }
        default:
            throw FaceCompilerError("Unknown color format: \(fmt) (\(hexUpper(UInt32(fmt), width: 2)))")
        }
        return out
    }

    /// RGBA8888 -> сирі дані формату.
    static func encode(_ fmt: UInt8, _ rgba: [UInt8], _ w: Int, _ h: Int) throws -> [UInt8] {
        let n = w * h
        switch fmt {
        case 0:
            var out = [UInt8](repeating: 0, count: n * 4)
            for i in 0..<n {
                out[i * 4] = rgba[i * 4 + 2]; out[i * 4 + 1] = rgba[i * 4 + 1]
                out[i * 4 + 2] = rgba[i * 4]; out[i * 4 + 3] = rgba[i * 4 + 3]
            }
            return out
        case 6:
            var out = [UInt8](repeating: 0, count: n * 3)
            for i in 0..<n {
                let r = Int(Double(rgba[i * 4]) * 31.0 / 255.0)
                let g = Int(Double(rgba[i * 4 + 1]) * 63.0 / 255.0)
                let b = Int(Double(rgba[i * 4 + 2]) * 31.0 / 255.0)
                let v = ((r << 6 | g) << 5 | b) & 0xFFFF
                out[i * 3] = UInt8(v & 0xFF); out[i * 3 + 1] = UInt8(v >> 8); out[i * 3 + 2] = rgba[i * 4 + 3]
            }
            return out
        case 0x10:
            var index: [UInt32: Int] = [:]
            var cols: [UInt32] = []
            var idx = [UInt8](repeating: 0, count: n)
            for i in 0..<n {
                let c = UInt32(rgba[i * 4]) | UInt32(rgba[i * 4 + 1]) << 8 | UInt32(rgba[i * 4 + 2]) << 16 | UInt32(rgba[i * 4 + 3]) << 24
                if let k = index[c] { idx[i] = UInt8(k); continue }
                if cols.count >= 256 { throw FaceCompilerError("Image has more than 256 colors!") }
                index[c] = cols.count; idx[i] = UInt8(cols.count); cols.append(c)
            }
            // доповнення нулями: якщо колір 0 трапився пізніше — індекс першої появи
            var pal = [UInt8](repeating: 0, count: 1024)
            for (k, c) in cols.enumerated() {
                pal[k * 4] = UInt8((c >> 16) & 0xFF); pal[k * 4 + 1] = UInt8((c >> 8) & 0xFF)
                pal[k * 4 + 2] = UInt8(c & 0xFF); pal[k * 4 + 3] = UInt8(c >> 24)
            }
            return pal + idx
        default:
            throw FaceCompilerError("Unknown color format: \(fmt) (\(hexUpper(UInt32(fmt), width: 2)))")
        }
    }
}
