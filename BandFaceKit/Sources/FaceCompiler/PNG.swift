// SPDX-License-Identifier: MIT
// PNG без системних бібліотек, щоб результат був однаковим на будь-якій платформі:
// • запис — побайтово як у stb_image_write (його використовує exe): евристика фільтрів, власний deflate, quality 8;
// • читання — як stb_image з req_comp=4 (усі типи кольору, глибини 1–16, tRNS, Adam7, 16 біт -> старший байт).

import Foundation

public enum PNG {
    // MARK: CRC / Adler

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ parts: [UInt8]...) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for p in parts { for b in p { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) } }
        return c ^ 0xFFFF_FFFF
    }

    // MARK: Запис (stb_image_write)

    private static let lengthc: [Int] = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258,259]
    private static let lengtheb: [Int] = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]
    private static let distc: [Int] = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,32768]
    private static let disteb: [Int] = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]

    @inline(__always) private static func zhash(_ d: [UInt8], _ i: Int) -> Int {
        var h = UInt32(d[i]) &+ (UInt32(d[i + 1]) << 8) &+ (UInt32(d[i + 2]) << 16)
        h ^= h << 3; h = h &+ (h >> 5)
        h ^= h << 4; h = h &+ (h >> 17)
        h ^= h << 25; h = h &+ (h >> 6)
        return Int(h & 16383)
    }
    @inline(__always) private static func bitrev(_ code: Int, _ n: Int) -> Int {
        var r = 0, c = code
        for _ in 0..<n { r = (r << 1) | (c & 1); c >>= 1 }
        return r
    }
    @inline(__always) private static func countm(_ d: [UInt8], _ a: Int, _ b: Int, _ limit: Int) -> Int {
        let lim = min(limit, 258)
        var i = 0
        while i < lim, d[a + i] == d[b + i] { i += 1 }
        return i
    }

    static func zlibCompress(_ data: [UInt8], quality q: Int = 8) -> [UInt8] {
        let quality = max(q, 5)
        var out: [UInt8] = [0x78, 0x5E]
        var bitbuf: UInt32 = 0, bitcount = 0
        func add(_ code: Int, _ bits: Int) {
            bitbuf |= UInt32(code) << UInt32(bitcount); bitcount += bits
            while bitcount >= 8 { out.append(UInt8(bitbuf & 0xFF)); bitbuf >>= 8; bitcount -= 8 }
        }
        func huffa(_ b: Int, _ c: Int) { add(bitrev(b, c), c) }
        func huff(_ n: Int) {
            if n <= 143 { huffa(0x30 + n, 8) } else if n <= 255 { huffa(0x190 + n - 144, 9) }
            else if n <= 279 { huffa(n - 256, 7) } else { huffa(0xC0 + n - 280, 8) }
        }
        func huffb(_ n: Int) { if n <= 143 { huffa(0x30 + n, 8) } else { huffa(0x190 + n - 144, 9) } }
        add(1, 1); add(1, 2)
        var table = [[Int]](repeating: [], count: 16384)
        let n = data.count
        var i = 0
        while i < n - 3 {
            var h = zhash(data, i)
            var best = 3, bestloc = -1
            for p in table[h] where p > i - 32768 {
                let d = countm(data, p, i, n - i)
                if d >= best { best = d; bestloc = p }
            }
            if table[h].count == 2 * quality { table[h].removeFirst(quality) }
            table[h].append(i)
            if bestloc >= 0 {
                h = zhash(data, i + 1)
                for p in table[h] where p > i - 32767 {
                    let e = countm(data, p, i + 1, n - i - 1)
                    if e > best { bestloc = -1; break }
                }
            }
            if bestloc >= 0 {
                let d = i - bestloc
                var j = 0
                while best > lengthc[j + 1] - 1 { j += 1 }
                huff(j + 257)
                if lengtheb[j] != 0 { add(best - lengthc[j], lengtheb[j]) }
                j = 0
                while d > distc[j + 1] - 1 { j += 1 }
                add(bitrev(j, 5), 5)
                if disteb[j] != 0 { add(d - distc[j], disteb[j]) }
                i += best
            } else {
                huffb(Int(data[i])); i += 1
            }
        }
        while i < n { huffb(Int(data[i])); i += 1 }
        huff(256)
        while bitcount != 0 { add(0, 1) }
        if out.count > n + 2 + ((n + 32766) / 32767) * 5 {
            out.removeSubrange(2...)
            var j = 0
            while j < n {
                let bl = min(n - j, 32767)
                out += [n - j == bl ? 1 : 0, UInt8(bl & 0xFF), UInt8(bl >> 8), UInt8(~bl & 0xFF), UInt8((~bl >> 8) & 0xFF)]
                out += data[j..<(j + bl)]; j += bl
            }
        }
        var s1: UInt32 = 1, s2: UInt32 = 0
        var bl = n % 5552, j = 0
        while j < n {
            for k in 0..<bl { s1 += UInt32(data[j + k]); s2 += s1 }
            s1 %= 65521; s2 %= 65521; j += bl; bl = 5552
        }
        out += [UInt8((s2 >> 8) & 0xFF), UInt8(s2 & 0xFF), UInt8((s1 >> 8) & 0xFF), UInt8(s1 & 0xFF)]
        return out
    }

    @inline(__always) private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a & 0xFF }
        if pb <= pc { return b & 0xFF }
        return c & 0xFF
    }

    private static func encodeLine(_ px: [UInt8], _ stride: Int, _ y: Int, _ n: Int, _ ftype: Int, _ out: inout [UInt8]) {
        let typ = y != 0 ? ftype : [0, 1, 0, 5, 6][ftype]
        let z = y * stride
        if typ == 0 { for i in 0..<stride { out[i] = px[z + i] }; return }
        for i in 0..<stride {
            let cur = Int(px[z + i])
            let left = i >= n ? Int(px[z + i - n]) : 0
            let up = (typ == 2 || typ == 3 || typ == 4) ? Int(px[z + i - stride]) : 0
            let ul = (typ == 4 && i >= n) ? Int(px[z + i - stride - n]) : 0
            let v: Int
            switch typ {
            case 1: v = cur - left
            case 2: v = cur - up
            case 3: v = cur - ((left + up) >> 1)
            case 4: v = cur - paeth(left, up, ul)
            case 5: v = cur - (left >> 1)
            default: v = cur - paeth(left, 0, 0)
            }
            out[i] = UInt8(truncatingIfNeeded: v)
        }
    }

    /// RGBA8888 -> PNG (точно як stbi_write_png з 4 каналами).
    public static func encode(_ w: Int, _ h: Int, _ rgba: [UInt8]) -> [UInt8] {
        let n = 4, stride = w * n
        var filt = [UInt8](); filt.reserveCapacity((stride + 1) * h)
        var lines = [[UInt8]](repeating: [UInt8](repeating: 0, count: stride), count: 5)
        for y in 0..<h {
            var best = 0, bestv = Int.max
            for f in 0..<5 {
                encodeLine(rgba, stride, y, n, f, &lines[f])
                var est = 0
                for b in lines[f] { est += b >= 128 ? 256 - Int(b) : Int(b) }
                if est < bestv { bestv = est; best = f }
            }
            filt.append(UInt8(best)); filt += lines[best]
        }
        let z = zlibCompress(filt, quality: 8)
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ t: String, _ d: [UInt8]) {
            var w = [UInt8]()
            let tb = Array(t.utf8)
            w += be32(UInt32(d.count)); w += tb; w += d; w += be32(crc32(tb, d))
            out += w
        }
        chunk("IHDR", be32(UInt32(w)) + be32(UInt32(h)) + [8, 6, 0, 0, 0])
        chunk("IDAT", z)
        chunk("IEND", [])
        return out
    }

    /// Палітровий PNG (8 біт, тип 3): індекси w×h і палітра RGB (до 256 кольорів). Рядки без фільтра —
    /// для палітри це найкраще стискається. Утричі-вчетверо менше за RGBA.
    public static func encodeIndexed(_ w: Int, _ h: Int, _ indices: [UInt8], palette: [UInt8]) -> [UInt8] {
        var raw = [UInt8](); raw.reserveCapacity((w + 1) * h)
        for y in 0..<h { raw.append(0); raw += indices[(y * w)..<(y * w + w)] }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ t: String, _ d: [UInt8]) {
            let tb = Array(t.utf8)
            out += be32(UInt32(d.count)); out += tb; out += d; out += be32(crc32(tb, d))
        }
        let colors = max(1, min(256, palette.count / 3))
        chunk("IHDR", be32(UInt32(w)) + be32(UInt32(h)) + [8, 3, 0, 0, 0])
        chunk("PLTE", Array(palette.prefix(colors * 3)))
        chunk("IDAT", zlibCompress(raw, quality: 8))
        chunk("IEND", [])
        return out
    }

    static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    // MARK: Читання

    public struct Image { public let w: Int; public let h: Int; public let rgba: [UInt8]
        public init(w: Int, h: Int, rgba: [UInt8]) { self.w = w; self.h = h; self.rgba = rgba } }

    public static func decode(_ d: [UInt8]) -> Image? {
        guard d.count > 8, Array(d[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else { return nil }
        var p = 8
        var w = 0, h = 0, depth = 0, ctype = 0, interlace = 0
        var pal: [UInt8] = [], trns: [UInt8] = []
        var idat: [UInt8] = []
        while p + 8 <= d.count {
            let len = Int(UInt32(d[p]) << 24 | UInt32(d[p + 1]) << 16 | UInt32(d[p + 2]) << 8 | UInt32(d[p + 3]))
            let t = String(decoding: d[(p + 4)..<(p + 8)], as: UTF8.self)
            let s = p + 8
            guard s + len <= d.count else { return nil }
            let body = d[s..<(s + len)]
            switch t {
            case "IHDR":
                guard len >= 13 else { return nil }
                let b = Array(body)
                w = Int(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
                h = Int(UInt32(b[4]) << 24 | UInt32(b[5]) << 16 | UInt32(b[6]) << 8 | UInt32(b[7]))
                depth = Int(b[8]); ctype = Int(b[9]); interlace = Int(b[12])
            case "PLTE": pal = Array(body)
            case "tRNS": trns = Array(body)
            case "IDAT": idat += body
            case "IEND": p = d.count; continue
            default: break
            }
            p = s + len + 4
        }
        guard w > 0, h > 0, w < 1 << 24, h < 1 << 24, [1, 2, 4, 8, 16].contains(depth) else { return nil }
        let chans: Int
        switch ctype { case 0: chans = 1; case 2: chans = 3; case 3: chans = 1; case 4: chans = 2; case 6: chans = 4; default: return nil }
        guard idat.count > 2, let raw = Inflate.inflate(Array(idat[2...])) else { return nil }
        let bitsPP = chans * depth
        let bpp = max(1, bitsPP / 8)
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        var src = 0

        func sample(_ row: [UInt8], _ x: Int, _ c: Int) -> Int {
            switch depth {
            case 16: return Int(row[(x * chans + c) * 2]) << 8 | Int(row[(x * chans + c) * 2 + 1])
            case 8: return Int(row[x * chans + c])
            default:
                let bit = (x * chans + c) * depth
                return (Int(row[bit >> 3]) >> (8 - depth - (bit & 7))) & ((1 << depth) - 1)
            }
        }
        func to8(_ v: Int) -> UInt8 {
            switch depth {
            case 16: return UInt8(v >> 8)
            case 8: return UInt8(v)
            case 4: return UInt8(v * 0x11)
            case 2: return UInt8(v * 0x55)
            default: return UInt8(v * 0xFF)
            }
        }
        func trnsKey(_ c: Int) -> Int? {
            guard !trns.isEmpty else { return nil }
            let off = ctype == 0 ? 0 : c * 2
            guard off + 1 < trns.count else { return nil }
            return Int(trns[off]) << 8 | Int(trns[off + 1])
        }
        func put(_ row: [UInt8], _ x: Int, _ o: Int) {
            switch ctype {
            case 0:
                let v = sample(row, x, 0)
                let g = to8(v)
                rgba[o] = g; rgba[o + 1] = g; rgba[o + 2] = g
                rgba[o + 3] = (trnsKey(0) == v) ? 0 : 255
            case 2:
                let r = sample(row, x, 0), g = sample(row, x, 1), b = sample(row, x, 2)
                rgba[o] = to8(r); rgba[o + 1] = to8(g); rgba[o + 2] = to8(b)
                if let kr = trnsKey(0), let kg = trnsKey(1), let kb = trnsKey(2), kr == r, kg == g, kb == b { rgba[o + 3] = 0 } else { rgba[o + 3] = 255 }
            case 3:
                let i = sample(row, x, 0)
                rgba[o] = pal.u8(i * 3); rgba[o + 1] = pal.u8(i * 3 + 1); rgba[o + 2] = pal.u8(i * 3 + 2)
                rgba[o + 3] = i < trns.count ? trns[i] : 255
            case 4:
                let g = to8(sample(row, x, 0))
                rgba[o] = g; rgba[o + 1] = g; rgba[o + 2] = g; rgba[o + 3] = to8(sample(row, x, 1))
            default:
                for c in 0..<4 { rgba[o + c] = to8(sample(row, x, c)) }
            }
        }
        /// Один прохід (для Adam7 — підзображення з кроком dx/dy).
        func pass(_ x0: Int, _ y0: Int, _ dx: Int, _ dy: Int) -> Bool {
            let pw = (w - x0 + dx - 1) / dx, ph = (h - y0 + dy - 1) / dy
            guard pw > 0, ph > 0 else { return true }
            let stride = (pw * bitsPP + 7) / 8
            var prev = [UInt8](repeating: 0, count: stride)
            var cur = [UInt8](repeating: 0, count: stride)
            for py in 0..<ph {
                guard src + 1 + stride <= raw.count else { return false }
                let f = raw[src]; src += 1
                for i in 0..<stride {
                    let x = Int(raw[src + i])
                    let a = i >= bpp ? Int(cur[i - bpp]) : 0
                    let b = Int(prev[i])
                    let c = i >= bpp ? Int(prev[i - bpp]) : 0
                    let v: Int
                    switch f {
                    case 0: v = x
                    case 1: v = x + a
                    case 2: v = x + b
                    case 3: v = x + ((a + b) >> 1)
                    case 4: v = x + paeth(a, b, c)
                    default: return false
                    }
                    cur[i] = UInt8(truncatingIfNeeded: v)
                }
                src += stride
                for px in 0..<pw { put(cur, px, ((y0 + py * dy) * w + (x0 + px * dx)) * 4) }
                swap(&prev, &cur)
            }
            return true
        }
        if interlace == 1 {
            let passes = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
            for (x0, y0, dx, dy) in passes { guard pass(x0, y0, dx, dy) else { return nil } }
        } else {
            guard pass(0, 0, 1, 1) else { return nil }
        }
        return Image(w: w, h: h, rgba: rgba)
    }

}

/// Розпакування DEFLATE (RFC 1951).
enum Inflate {
    private struct Huff {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []
        init(_ lengths: [Int]) {
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offs = [Int](repeating: 0, count: 16)
            for i in 1..<16 { offs[i] = offs[i - 1] + counts[i - 1] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (s, l) in lengths.enumerated() where l != 0 { symbols[offs[l]] = s; offs[l] += 1 }
        }
    }
    private static let lbase = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258]
    private static let lext = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]
    private static let dbase = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577]
    private static let dext = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]

    static func inflate(_ src: [UInt8]) -> [UInt8]? {
        var out: [UInt8] = []
        var pos = 0, bitbuf = 0, bitcnt = 0
        func bits(_ n: Int) -> Int? {
            while bitcnt < n {
                guard pos < src.count else { return nil }
                bitbuf |= Int(src[pos]) << bitcnt; pos += 1; bitcnt += 8
            }
            let v = bitbuf & ((1 << n) - 1)
            bitbuf >>= n; bitcnt -= n
            return v
        }
        func decode(_ h: Huff) -> Int? {
            var code = 0, first = 0, index = 0
            for len in 1..<16 {
                guard let b = bits(1) else { return nil }
                code |= b
                let count = h.counts[len]
                if code - count < first { return h.symbols[index + (code - first)] }
                index += count; first += count; first <<= 1; code <<= 1
            }
            return nil
        }
        var fixedL: Huff?, fixedD: Huff?
        while true {
            guard let last = bits(1), let type = bits(2) else { return nil }
            if type == 0 {
                bitbuf = 0; bitcnt = 0
                guard pos + 4 <= src.count else { return nil }
                let len = Int(src[pos]) | Int(src[pos + 1]) << 8
                pos += 4
                guard pos + len <= src.count else { return nil }
                out += src[pos..<(pos + len)]; pos += len
            } else {
                var lh: Huff, dh: Huff
                if type == 1 {
                    if fixedL == nil {
                        var l = [Int](repeating: 8, count: 288)
                        for i in 144..<256 { l[i] = 9 }
                        for i in 256..<280 { l[i] = 7 }
                        fixedL = Huff(l); fixedD = Huff([Int](repeating: 5, count: 30))
                    }
                    lh = fixedL!; dh = fixedD!
                } else if type == 2 {
                    guard let hl = bits(5), let hd = bits(5), let hc = bits(4) else { return nil }
                    let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                    var cl = [Int](repeating: 0, count: 19)
                    for i in 0..<(hc + 4) { guard let v = bits(3) else { return nil }; cl[order[i]] = v }
                    let ch = Huff(cl)
                    var lens: [Int] = []
                    let total = hl + 257 + hd + 1
                    while lens.count < total {
                        guard let s = decode(ch) else { return nil }
                        if s < 16 { lens.append(s) }
                        else if s == 16 { guard let r = bits(2), let p = lens.last else { return nil }; lens += [Int](repeating: p, count: 3 + r) }
                        else if s == 17 { guard let r = bits(3) else { return nil }; lens += [Int](repeating: 0, count: 3 + r) }
                        else { guard let r = bits(7) else { return nil }; lens += [Int](repeating: 0, count: 11 + r) }
                    }
                    guard lens.count == total else { return nil }
                    lh = Huff(Array(lens[0..<(hl + 257)])); dh = Huff(Array(lens[(hl + 257)...]))
                } else { return nil }
                while true {
                    guard let s = decode(lh) else { return nil }
                    if s < 256 { out.append(UInt8(s)); continue }
                    if s == 256 { break }
                    let li = s - 257
                    guard li < 29, let e = bits(lext[li]) else { return nil }
                    let len = lbase[li] + e
                    guard let ds = decode(dh), ds < 30, let de = bits(dext[ds]) else { return nil }
                    let dist = dbase[ds] + de
                    guard dist <= out.count else { return nil }
                    let start = out.count - dist
                    for k in 0..<len { out.append(out[start + k]) }
                }
            }
            if last == 1 { break }
        }
        return out
    }
}
