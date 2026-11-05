// SPDX-License-Identifier: MIT
// Розпакування .bin -> manifest.xml + PNG + файли (порт завантажувача 0x140024bb0 і запису 0x1400281a0 WatchfaceCompiler 0.9.8).

import Foundation

public final class FaceUnpacker {
    let b: [UInt8]
    let options: FaceCompilerOptions
    let log: FaceCompilerLog

    struct Theme {
        var flags: UInt32
        var preview: UInt32
        var entryOffset: Int
        var extra: [UInt32]
        var tables: [(Int, Int)]
        var items: [[UnpackItem]] = Array(repeating: [], count: 10)
        var previewImage: UnpackItem?
    }

    let ncol: Int
    let colors: [UInt32]
    let esize: Int
    var themes: [Theme] = []
    var globalItems: [UnpackItem] = []
    var registry: [UInt32: UnpackItem] = [:]

    public init(data: Data, options: FaceCompilerOptions = .init(), log: FaceCompilerLog = .init()) throws {
        let b = [UInt8](data)
        self.b = b
        self.options = options
        self.log = log
        let n = Int(b.u8(0x1D))
        let ncol = n != 0 ? n : Int(b.u32(0x18))
        self.ncol = ncol
        colors = (0..<ncol).map { b.u32(0xA8 + 4 * $0) }
        let esize = b.u32(4) != 0 ? 0xA0 : 0x58
        self.esize = esize
        var off = 0xA8 + 4 * ncol
        for _ in 0..<Int(b.u8(0x1C)) {
            let k = esize == 0xA0 ? Int((b.u32(off + 0x9C) >> 2) & 0xFF) : 0
            let tables = (0..<10).map { (Int(b.u32(off + 8 + 8 * $0)), Int(b.u32(off + 12 + 8 * $0))) }
            themes.append(Theme(flags: b.u32(off), preview: b.u32(off + 4), entryOffset: off,
                                extra: (0..<k).map { b.u32(off + esize + 4 * $0) }, tables: tables))
            off += esize + 4 * k
        }
        for t in themes.indices {
            let p = Int(themes[t].preview)
            if p != 0, themes[t].preview != 0xFFFF_FFFF {
                let n = Int(b.u32(p + 8))
                themes[t].previewImage = try UnpackItem(face: self, type: 2, id: 0, theme: t, data: b.slice(p, 12 + n))
            }
            let eo = themes[t].entryOffset
            if esize == 0xA0, b.u32(eo + 0x58) == 0xFFFF_FFFF {
                let o = Int(b.u32(eo + 0x64)), s = Int(b.u32(eo + 0x68))
                globalItems.append(try UnpackItem(face: self, type: 6, id: b.u32(eo + 0x5C), theme: t, data: b.slice(o, s)))
            }
        }
        for t in themes.indices {
            for ty in 0..<10 {
                let (c, o) = themes[t].tables[ty]
                for i in 0..<c {
                    let r = o + 16 * i
                    let iid = b.u32(r), ro = Int(b.u32(r + 8)), rs = Int(b.u32(r + 12))
                    if rs == 0 || ro == 0 { continue }
                    let typ = Int(iid >> 24)
                    guard [0, 2, 3, 4, 5, 6, 7, 8, 9].contains(typ) else { throw FaceCompilerError("Unknown item: \(hexUpper(iid))") }
                    let it = try UnpackItem(face: self, type: typ, id: iid, theme: t, data: b.slice(ro, rs))
                    themes[t].items[ty].append(it)
                    if registry[iid] == nil { registry[iid] = it }
                }
            }
        }
    }

    func refName(_ rid: UInt32) throws -> String {
        if rid == 0 { return "@" }
        guard let it = registry[rid] else { throw FaceCompilerError("Unknown resource with uid=\(String(rid, radix: 16))") }
        return "@" + it.name
    }

    func putColorGroup(_ e: XNode, _ it: UnpackItem) {
        guard b.u8(0x1D) == 0, b.u32(0x18) != 0 else { return }
        let k = it.id != 0 ? Int((it.id >> 19) & 0x1F) : 0
        if k < colors.count { e.set("colorGroup", hex6(colors[k])) }
    }

    /// manifest.xml (без перетворення кінців рядків). Якщо задано сховище — файли пишуться під час обходу,
    /// як у exe (запис XML ресурсу й збереження його картинки йдуть разом; помилка посередині лишає вже записане).
    public func manifestXML(saving storage: FaceStorage? = nil) throws -> [UInt8] {
        let root = XNode("Watchface")
        root.set("id", b.cstr(0x28, 0x40))
        if b.u32(0x68) != 0xFFFF_FFFF { root.set("name", b.cstr(0x68, 0x40)) } else { root.set("name", "@Translation_\(b.u32(0x6C))") }
        if b.u8(0x1D) != 0 { root.set("recolorTable", colors.map(hex6).joined(separator: ",")) }
        else if b.u32(0x18) != 0 { root.set("colorGroupTable", colors.map(hex6).joined(separator: ",")) }
        let res = root.add("Resources")
        for it in globalItems { try it.xml(res) }
        for (t, th) in themes.enumerated() {
            res.kids.append(.comment("Resources of theme \(t)"))
            if let p = th.previewImage {
                try p.xml(res, name: "preview_\(t)")
                if let storage { try p.save(storage, name: "preview_\(t)") }
            }
            for ty in 1..<10 {
                for it in th.items[ty] {
                    try it.xml(res)
                    if let storage { try it.save(storage) }
                }
            }
        }
        for (t, th) in themes.enumerated() {
            let e = root.add("Theme")
            let aod = esize == 0xA0 ? b.u32(th.entryOffset + 0x9C) & 3 : 0
            e.set("type", (aod != 0 || (t == 1 && b.u8(0x1E) & 4 != 0)) ? "AOD" : "normal")
            e.set("name", esize == 0xA0 ? b.cstr(th.entryOffset + 0x58, 0x40) : [])
            e.set("bgColor", hex6(th.flags))
            if th.previewImage != nil { e.set("preview", "@preview_\(t)") }
            for it in th.items[0] { try it.xml(e) }
            if !th.extra.isEmpty { e.set("colorGroup", th.extra.map { hex6(colors.indices.contains(Int($0)) ? colors[Int($0)] : 0) }.joined(separator: ",")) }
        }
        return XML.print(root)
    }

    /// Записує проєкт: зображення, файли, manifest.xml (як exe — у текстовому режимі Windows, CR LF).
    public func save(to storage: FaceStorage) throws {
        var xml: [UInt8] = []
        for c in try manifestXML(saving: storage) { if c == 0x0A { xml.append(0x0D) }; xml.append(c) }
        try storage.write("manifest.xml", Data(xml))
        log.info("Done!")
    }

    /// Реєстр (для --uidmap): зростання id, лише записи з типом.
    public func uidMap() -> [UInt8] {
        var out = [UInt8]()
        for id in registry.keys.sorted() where id & 0x0F00_0000 != 0 {
            out += Array("\(registry[id]!.name): \(String(id, radix: 16))\r\n".utf8)
        }
        return out
    }
}

// MARK: - Запис ресурсу

final class UnpackItem {
    unowned let face: FaceUnpacker
    let type: Int
    let id: UInt32
    let theme: Int
    let d: [UInt8]   // дані запису (читання за межами дає 0)
    let n: Int

    // загальні поля
    var kind = 0
    // Image / ImageArray
    var fmt: UInt8 = 0, recolor = false, comp = false, w = 0, h = 0
    var rgba: [UInt8] = []
    var frames: [[UInt8]] = []
    // Translation
    var strings: [(String, [UInt8])] = []

    init(face: FaceUnpacker, type: Int, id: UInt32, theme: Int, data: [UInt8]) throws {
        self.face = face; self.type = type; self.id = id; self.theme = theme; d = data; n = data.count
        try parse()
    }

    static let short: [Int: String] = [0: "Layout", 2: "Image", 3: "ImageArray", 4: "Sprite", 5: "File", 6: "Translation", 8: "Slot", 9: "Widget"]
    static let diShort = ["Text", "ImageNumber", "ImageValues", "Pointer", "ArcProgress", "LineProgress"]

    var shortName: String { type == 7 ? (kind < 6 ? UnpackItem.diShort[kind] : "DataItem") : (UnpackItem.short[type] ?? "Layout") }
    /// «{Short}_{theme}_{id & 0xFF07FFFF:X}»
    var name: String { "\(shortName)_\(theme)_\(hexUpper(id & 0xFF07_FFFF))" }
    /// Ім'я файлів — повний id.
    func fileName(_ nm: String? = nil) -> String {
        if let nm, id == 0 { return nm }
        return "\(shortName)_\(theme)_\(hexUpper(id))"
    }
    func ref(_ rid: UInt32) throws -> String { try face.refName(rid) }

    static func d10(_ v: Int16) -> Int { Int(v) / 10 }

    func parse() throws {
        switch type {
        case 2:
            fmt = d.u8(0); recolor = d.u8(1) & 1 != 0
            w = Int(d.u16(4)); h = Int(d.u16(6))
            let len = Int(d.u32(8))
            let body = d.slice(12, len)
            var raw = body
            if body.count >= 8, body.u32(0) == RLE.magic {
                let x = body.u32(4)
                raw = RLE.decompress(body, from: 8, outSize: Int((x >> 4) & 0xFF_FFFF), elem: Int(x & 0xF)); comp = true
            }
            guard PixelFormat.name(fmt) != nil else { throw FaceCompilerError("Unknown color format: \(fmt) (\(hexUpper(UInt32(fmt), width: 2)))") }
            rgba = try PixelFormat.decode(fmt, raw, w, h)
        case 3:
            fmt = d.u8(0); let cnt = Int(d.u8(1)); recolor = d.u8(2) & 1 != 0
            w = Int(d.u16(4)); h = Int(d.u16(6)); let total = Int(d.u32(8))
            var p = 12
            var sizes: [Int]
            if d.u8(2) & 4 != 0 { sizes = (0..<cnt).map { Int(d.u32(12 + 4 * $0)) }; p += 4 * cnt }
            else { sizes = cnt > 0 ? Array(repeating: total / cnt, count: cnt) : [] }
            comp = false
            for s in sizes {
                let blob = d.slice(p, s)
                var raw = blob
                if blob.count >= 8, blob.u32(0) == RLE.magic {
                    let x = blob.u32(4)
                    raw = RLE.decompress(blob, from: 8, outSize: Int((x >> 4) & 0xFF_FFFF), elem: Int(x & 0xF)); comp = true
                } else { comp = false }
                frames.append(try PixelFormat.decode(fmt, raw, w, h))
                p += s
            }
        case 6:
            let mask = d.u64(0)
            let cnt = mask.nonzeroBitCount
            let lens = (0..<cnt).map { Int(d.u32(8 + 4 * $0)) }
            var p = 8 + 4 * cnt, k = 0
            for bit in 0..<64 where (mask >> UInt64(bit)) & 1 != 0 {
                let s = d.slice(p, lens[k]); p += lens[k]; k += 1
                strings.append((bit < FaceTables.languages.count ? FaceTables.languages[bit] : "lang\(bit)", s))
            }
        case 7:
            kind = Int(d.u8(3) >> 4)
            if kind > 5 { throw FaceCompilerError("Unknown data format: \(kind)") }
        default: break
        }
    }

    // MARK: XML

    func xml(_ parent: XNode, name nm: String? = nil) throws {
        switch type {
        case 0:
            let e = parent.add("Layout").set("ref", try ref(d.u32(0))).set("x", int: Int(d.i16(4))).set("y", int: Int(d.i16(6)))
            if d.u32(8) != 0 { e.set("param", uint: d.u32(8)) }
        case 2:
            let nm = nm ?? name
            let e = parent.add("Image").set("name", nm).set("src", fileName(nm) + ".png")
            e.set("compressMethod", comp ? "RLEReversed" : "none").set("format", PixelFormat.name(fmt)!).set("recolorEnable", bool: recolor)
            face.putColorGroup(e, self)
        case 3:
            let e = parent.add("ImageArray").set("name", name)
            e.set("compressMethod", comp ? "RLEReversed" : "none").set("format", PixelFormat.name(fmt) ?? "RGBA32").set("recolorEnable", bool: recolor)
            for i in frames.indices { e.add("Image").set("src", "\(fileName())/\(i).png") }
            face.putColorGroup(e, self)
        case 4:
            parent.add("Sprite").set("name", name).set("ref", try ref(d.u32(0)))
                .set("interval", uint: UInt32(d.u16(6))).set("repeatCount", uint: d.u32(8))
        case 5:
            let nl = Int(d.u32(0) >> 24)
            let fn = d.cstr(20, nl)
            parent.add("File").set("name", name).set("filename", fn.isEmpty ? Array(name.utf8) : fn)
        case 6:
            let e = parent.add("Translation").set("name", name)
            for (lang, s) in strings { e.add("Item").set("language", lang).set("str", s) }
        case 7: try dataItemXML(parent)
        case 8:
            let e = parent.add("Slot").set("name", name)
            let k = d.u16(2) & 0xF0
            let st = k == 0 ? "widget" : (k == 0x30 ? "appWidget" : "unknown")
            e.set("type", st)
            if st == "appWidget" {
                let v = d.u16(4)
                e.set("appWidgetID", Lookup.appWidgetById[v] ?? "0x" + hexUpper(UInt32(v)))
                return
            }
            for i in 0..<Int(d.u8(0)) { e.add("Item").set("ref", try ref(d.u32(4 + 4 * i))) }
        case 9: try widgetXML(parent)
        default: break
        }
    }

    func widgetXML(_ parent: XNode) throws {
        let e = parent.add("Widget").set("name", name)
        if d.u32(0) == 0xFFFF_FFFF { e.set("widgetName", try ref(d.u32(4))) } else { e.set("widgetName", d.cstr(0, 0x20)) }
        e.set("groupType", "general")
        let fl = Int(d.u16(0x2A))
        let bg = d.u32(0x20)
        if fl & 1 != 0, bg != 0 { e.set("bg", hex6(bg)) }
        if fl & 2 != 0 {
            let j = UInt8((fl >> 4) & 0xFF)
            e.set("jumpApp", Lookup.jumpById[j] ?? "unknown:0x" + hexUpper(UInt32(j)))
        }
        if d.u32(0x24) != 0 { e.set("preview", try ref(d.u32(0x24))) }
        let cnt = Int(d.u8(0x28))
        var p = 0x2C
        var items: [(UInt32, Int, Int)] = []
        for _ in 0..<cnt { items.append((d.u32(p + 4), Int(d.i16(p)), Int(d.i16(p + 2)))); p += 8 }
        if fl & 4 != 0 { e.set("editbox", try ref(d.u32(p))); p += 4 }
        if fl & 0x1000 != 0 { e.set("w", int: Int(d.u16(p + 2))).set("h", int: Int(d.u16(p))); p += 4 }
        if fl & 0x2000 != 0 { e.set("args", try ref(d.u32(p))); p += 4 }
        if fl & 0x4000 != 0 {
            let v = d.u32(p)
            var gap = Int((v >> 11) & 0x1FF)
            if v & 0x10_0000 != 0 { gap = -gap }
            let names = [0: "flex-start", 1: "center", 2: "flex-end"]
            e.set("flex_direction", v & 3 == 1 ? "column" : "row")
            e.set("justify_content", names[Int((v >> 2) & 7)] ?? "flex-start")
            e.set("align_content", names[Int((v >> 5) & 7)] ?? "flex-start")
            e.set("align_items", names[Int((v >> 8) & 7)] ?? "flex-start")
            e.set("gap", int: gap)
        }
        for (r, x, y) in items { e.add("Item").set("ref", try ref(r)).set("x", int: x).set("y", int: y) }
    }

    func dataItemXML(_ parent: XNode) throws {
        let src = d.u16(0)
        let total = Int(d.u8(2) & 0xF), dec = Int(d.u8(2) >> 4)
        let align = Int(d.u8(3) & 3), lz = d.u8(3) & 4 != 0, tz = d.u8(3) & 8 != 0
        let rr = d.u16(4), param = d.u16(6)
        func rrName(_ v: UInt16) -> String { v == 2 ? "hideWhenUnitMismatch" : (v == 4 ? "hideWhenOutRange" : "alwaysShow") }
        func vals(_ e: XNode, unsigned: Bool, _ o: Int) {
            for (key, off) in [("valueStart", o), ("valueRange", o + 4)] {
                if d.u8(off) != 0 { e.set(key + "Source", Lookup.sourceName(d.u16(off))) }
                else {
                    let v = d.i32(off) >> 8
                    if unsigned { e.set(key, uint: UInt32(bitPattern: v)) } else { e.set(key, int: Int(v)) }
                }
            }
        }
        let nm = name
        switch kind {
        case 0:
            let color = d.u32(8), w0 = d.u32(0xC), w1 = d.u32(0x10)
            let e = parent.add("DataItemText").set("name", nm).set("color", hex6(color))
            e.set("opacity", int: 100 - Int(color >> 24) * 100 / 255)
            let fid = (w0 >> 8) & 0x3F, fw = (w0 >> 14) & 0xF
            if let s = Lookup.fontIdById[fid] { e.set("fontId", s) } else { e.set("fontId", uint: fid) }
            if let s = Lookup.fontWeightById[fw] { e.set("fontWeight", s) } else { e.set("fontWeight", uint: fw) }
            e.set("letterSpace", uint: (w0 >> 18) & 0xFF)
            e.set("align", [1: "center", 2: "right"][Int(w1 & 7)] ?? "left")
            e.set("longMode", [0: "wrap", 2: "scroll", 3: "scroll_circular", 4: "clip"][Int((w1 >> 3) & 7)] ?? "dots")
            if (w1 >> 6) & 3 == 0 {
                e.set("style", "normal").set("lineSpace", int: Int(Int8(bitPattern: d.u8(0x14))))
                e.set("w", uint: (d.u32(0x14) >> 8) & 0x3FF).set("h", uint: (d.u32(0x14) >> 18) & 0x3FF)
                e.set("rotation", int: UnpackItem.d10(d.i16(0x18)))
            } else {
                e.set("style", "arc").set("radius", uint: d.u32(0x14) & 0x3FF)
                e.set("veritcalAlign", [1: "center", 2: "bottom"][Int((d.u32(0x14) >> 10) & 3)] ?? "top")
                e.set("startAngle", int: UnpackItem.d10(d.i16(0x18))).set("span", int: UnpackItem.d10(d.i16(0x1A)))
            }
            let len = Int(d.u8(0x2C)), ns = Int((d.u32(0x2C) >> 8) & 0xF)
            e.set("string", d.slice(0x30, len))
            for i in 0..<ns { e.add("Content").set("source", Lookup.sourceName(d.u16(0x30 + len + 2 * i))) }
        case 1:
            let e = parent.add("DataItemImageNumber").set("name", nm).set("source", Lookup.sourceName(src))
            e.set("ref", try ref(d.u32(8))).set("totalDigits", int: total).set("decimalDigits", int: dec)
            e.set("align", align == 0 ? "right" : (align == 2 ? "center" : "left")).set("leadingZero", bool: lz).set("trailingZero", bool: tz)
            e.set("renderRule", rrName(rr)).set("rotation", int: UnpackItem.d10(d.i16(14)))
            e.set("decimalOffsetX", int: Int(Int8(bitPattern: d.u8(12)))).set("space", int: Int(Int8(bitPattern: d.u8(13))))
            if d.u32(16) != 0 { e.set("unitIcon", try ref(d.u32(16))) }
        case 2:
            let e = parent.add("DataItemImageValues").set("name", nm).set("source", Lookup.sourceName(src))
            e.set("ref", try ref(d.u32(8))).set("renderRule", rrName(rr)).set("rotation", int: UnpackItem.d10(d.i16(14)))
            for i in 0..<max(0, (n - 16) / 4) { e.add("Param").set("value", uint: d.u32(16 + 4 * i)) }
        case 3:
            let e = parent.add("DataItemPointer").set("name", nm).set("source", Lookup.sourceName(src))
            e.set("ref", try ref(d.u32(8))).set("param", uint: UInt32(param)).set("renderRule", rrName(rr))
            vals(e, unsigned: false, 12)
            e.set("pivotX", int: Int(d.i16(20))).set("pivotY", int: Int(d.i16(22)))
            e.set("angleStart", int: UnpackItem.d10(d.i16(24))).set("angleRange", int: UnpackItem.d10(d.i16(26)))
        case 4:
            let e = parent.add("DataItemArcProgressBar").set("name", nm).set("source", Lookup.sourceName(src))
            e.set("ref", try ref(d.u32(8)))
            if d.u32(12) != 0 { e.set("bg", try ref(d.u32(12))) }
            e.set("endingStyle", d.u32(16) & 1 != 0 ? "round" : "normal").set("renderRule", rrName(rr))
            vals(e, unsigned: true, 20)
            e.set("angleStart", int: UnpackItem.d10(d.i16(32))).set("angleRange", int: UnpackItem.d10(d.i16(34)))
            e.set("pivotX", int: Int(d.i16(28))).set("pivotY", int: Int(d.i16(30)))
            e.set("barRadius", int: Int(d.i16(36))).set("barWidth", int: Int(d.i16(38)))
            if n > 0x28, d.u32(40) != 0 { e.set("indicatorImage", try ref(d.u32(40))).set("indicatorRadius", int: Int(d.i16(44))) }
        case 5:
            let e = parent.add("DataItemLineProgressBar").set("name", nm).set("source", Lookup.sourceName(src))
            e.set("ref", try ref(d.u32(8)))
            // exe друкує bg з неініціалізованого поля (фактично ніколи); порт — якщо задано
            if d.u32(12) != 0, !face.options.exeQuirks { e.set("bg", try ref(d.u32(12))) }
            e.set("renderRule", rrName(rr))
            vals(e, unsigned: true, 20)
            e.set("startX", int: Int(d.i16(28))).set("startY", int: Int(d.i16(30))).set("endX", int: Int(d.i16(32))).set("endY", int: Int(d.i16(34)))
            e.set("barWidth", int: Int(d.i16(38)))
            if d.u32(16) & 2 != 0 {
                let ind = n > 0x28 ? d.u32(40) : 0
                e.set("indicatorImage", try ref(ind)).set("offsetX", int: n > 0x28 ? Int(d.i16(44)) : 0).set("offsetY", int: n > 0x28 ? Int(d.i16(46)) : 0)
            }
        default: break
        }
    }

    // MARK: Файли

    func save(_ s: FaceStorage, name nm: String? = nil) throws {
        switch type {
        case 2:
            try s.write(fileName(nm ?? name) + ".png", Data(PNG.encode(w, h, rgba)))
        case 3:
            // exe кладе кадри в теку з маскованим id (назва ресурсу), хоча src указує на повний id (помилка exe)
            let dir = face.options.exeQuirks ? name : fileName()
            for (i, f) in frames.enumerated() { try s.write("\(dir)/\(i).png", Data(PNG.encode(w, h, f))) }
        case 5:
            let h0 = d.u32(0)
            let size = Int(h0 & 0xFF_FFFF), nl = Int(h0 >> 24)
            let fn = d.cstr(20, nl)
            try s.write(fn.isEmpty ? name : str(fn), Data(d.slice(20 + nl, min(size, max(0, n - 20 - nl)))))
        default: break
        }
    }
}
