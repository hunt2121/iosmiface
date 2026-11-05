// SPDX-License-Identifier: MIT
// Ресурси для збирання: читання з XML (конструктори класів exe), залежності (vtable[3]) і серіалізація (vtable[2]).

import Foundation

final class BuildItem {
    unowned let b: FaceBuilder
    let e: XNode
    let type: Int
    var id: UInt32 = 0
    var colorGroup: UInt8 = 0
    var theme = 0
    var name = ""

    /// getId(): (type<<24) | (colorGroup<<19) | (id & 0x7FFFF)
    var realId: UInt32 { ((UInt32(type) << 5 | UInt32(colorGroup)) << 19 | (id & 0x7FFFF)) & 0xFFFF_FFFF }

    // Layout / посилання
    var ref: [UInt8] = []
    var x: Int32 = 0, y: Int32 = 0, param: Int32 = 0
    // Image / ImageArray
    var comp = false, recolor = false, fmt: UInt8 = 0, w = 0, h = 0
    var rgba: [UInt8] = []
    var frames: [[UInt8]] = []
    // Sprite
    var interval: Int32 = 0, repeatCount: Int32 = 0
    // File
    var filename: [UInt8] = [], fileData: [UInt8] = []
    // Translation
    var strs: [[UInt8]] = []
    // Slot
    var slotType = "", slotKind = 0, appWidget: [UInt8]? = nil, slotItems: [[UInt8]] = []
    // Widget
    var tname: [UInt8]? = nil, wname: [UInt8] = [], bg: UInt32? = nil, size: (Int32, Int32)? = nil
    var jump: UInt8? = nil, editbox: [UInt8]? = nil, preview: [UInt8] = [], args: [UInt8]? = nil
    var witems: [([UInt8], Int32, Int32)] = []
    var flex: (Int, Int, Int, Int, Int32)? = nil
    // DataItem
    var kind = 0, src: UInt16 = 0, rr = 0
    var color: UInt32 = 0, fontSize: Int32 = 0, fontId: UInt32 = 0, fontWeight: UInt32 = 0, letterSpace: Int32 = 0
    var talign = 0, longMode = 0, arc = false, lineSpace: Int32 = 0, tw: Int32 = 0, th: Int32 = 0, rot: Int32 = 0
    var radius: Int32 = 0, valign = 0, a0: Int32 = 0, a1: Int32 = 0, string: [UInt8] = [], contents: [UInt16] = []
    var total: Int32 = 0, dec: Int32 = 0, dalign = 0, lz = false, tz = false, decoff: Int32 = 0, space: Int32 = 0
    var unit: [UInt8] = [], vals: [Int32] = []
    var vs: (Bool, Int32) = (false, 0), vr: (Bool, Int32) = (false, 0)
    var px: Int32 = 0, py: Int32 = 0, bgRef: [UInt8] = [], round = false, ind: [UInt8] = []
    var rad: Int32 = 0, bw: Int32 = 0, indr: Int32 = 0, sx: Int32 = 0, sy: Int32 = 0, ex: Int32 = 0, ey: Int32 = 0
    var ox: Int32 = 0, oy: Int32 = 0

    static let factory: [String: Int] = ["Layout": 0, "Image": 2, "ImageArray": 3, "Translation": 6, "File": 5,
                                         "Sprite": 4, "Slot": 8, "Widget": 9]
    static let diKinds: [String: Int] = ["DataItemText": 0, "DataItemImageNumber": 1, "DataItemImageValues": 2,
                                         "DataItemPointer": 3, "DataItemArcProgressBar": 4, "DataItemLineProgressBar": 5]

    /// Фабрика 0x140041ba0.
    static func create(_ b: FaceBuilder, _ e: XNode) throws -> BuildItem {
        if let t = factory[e.tag] { return try BuildItem(b, e, type: t) }
        if e.tag.hasPrefix("DataItem") { return try BuildItem(b, e, type: 7) }
        throw FaceCompilerError("Unknown entry: " + e.tag)
    }

    private init(copy o: BuildItem) {
        b = o.b; e = o.e; type = o.type; id = o.id; colorGroup = o.colorGroup; theme = o.theme; name = o.name
        comp = o.comp; recolor = o.recolor; fmt = o.fmt; w = o.w; h = o.h; rgba = o.rgba; frames = o.frames
    }
    func clone(colorGroup c: UInt8) -> BuildItem { let n = BuildItem(copy: self); n.colorGroup = c; return n }

    func required(_ k: String) throws -> [UInt8] {
        guard let v = e.raw(k) else { throw FaceCompilerError("Error on line \(e.line): field \(k) is required!") }
        return v
    }

    init(_ b: FaceBuilder, _ e: XNode, type: Int) throws {
        self.b = b; self.e = e; self.type = type
        switch type {
        case 0:
            ref = e.raw("ref") ?? []
            x = e.int("x"); y = e.int("y"); param = e.int("param")
        case 2:
            name = e.string("name") ?? ""
            comp = e.string("compressMethod") == "RLEReversed"
            recolor = e.bool("recolorEnable")
            fmt = parseFormat(e.raw("format"))
            let s = e.raw("src") ?? []
            (w, h, rgba) = try loadImage(s)
            if let cg = e.raw("colorGroup") {
                let c = try parseColor(cg) & 0xFF_FFFF
                guard let i = b.colors.firstIndex(of: c) else { throw FaceCompilerError("Color \(str(cg)) is not specified in Watchface colorGroupTable!") }
                colorGroup = UInt8(truncatingIfNeeded: i)
            }
        case 3:
            name = e.string("name") ?? ""
            comp = e.string("compressMethod") == "RLEReversed"
            recolor = e.bool("recolorEnable")
            fmt = parseFormat(e.raw("format"))
            for c in e.all("Image") {
                let s = c.raw("src") ?? []
                let (fw, fh, px) = try loadImage(s)
                if !frames.isEmpty, fw != w || fh != h {
                    throw FaceCompilerError("Image \(str(s)) not found has size \(fw)x\(fh), but \(w)x\(h) expected")
                }
                if frames.isEmpty { w = fw; h = fh }
                frames.append(px)
            }
            if frames.isEmpty { throw FaceCompilerError("ImageArray \(name) at line \(e.line) should contain at least 1 image!") }
        case 4:
            name = e.string("name") ?? ""; ref = e.raw("ref") ?? []
            interval = e.int("interval"); repeatCount = e.int("repeatCount")
        case 5:
            name = e.string("name") ?? ""; filename = e.raw("filename") ?? []
            guard let d = b.storage.read(str(filename)) else { throw FaceCompilerError("File \(str(filename)) open fail") }
            fileData = [UInt8](d)
        case 6:
            name = e.string("name") ?? ""
            strs = Array(repeating: [], count: FaceTables.languages.count)
            for c in e.all("Item") {
                let lang = c.string("language") ?? ""
                guard let i = FaceTables.languages.firstIndex(of: lang) else {
                    b.log.warn("Language \(lang) in \(name) is unknown!"); continue
                }
                strs[i] = c.raw("str") ?? []
            }
        case 8:
            name = str(try required("name")); slotType = str(try required("type"))
            if slotType == "appWidget" { slotKind = 3; appWidget = try required("appWidgetID") }
            else {
                slotKind = ["widget": 0, "time": 1, "dualTime": 6][slotType] ?? 0
                for c in e.all("Item") {
                    guard let r = c.raw("ref") else { throw FaceCompilerError("Error on line \(c.line): field ref is required!") }
                    slotItems.append(r)
                }
            }
        case 9:
            name = str(try required("name"))
            let wn = e.raw("widgetName") ?? []
            if wn.first == 0x40 { tname = wn } else { wname = wn }
            if e.has("bg") { bg = try parseColor(e.raw("bg")) }
            if e.has("w"), e.has("h") { size = (e.int("w"), e.int("h")) }
            if let ja = e.string("jumpApp") {
                if let v = Lookup.jumpByName[ja] { jump = v }
                else if !b.quirks, ja.hasPrefix("unknown:0x"), let v = UInt32(ja.dropFirst(10), radix: 16) { jump = UInt8(v & 0xFF) }
                else { b.log.warn("jumpApp=\(ja) is unknown on line \(e.line)") }
            }
            editbox = e.raw("editbox")
            preview = e.raw("preview") ?? []
            for c in e.all("Item") {
                guard let r = c.raw("ref") else { throw FaceCompilerError("Error on line \(c.line): field ref is required!") }
                witems.append((r, c.int("x"), c.int("y")))
            }
            args = e.raw("args")
            let keys = ["flex_direction", "justify_content", "align_content", "align_items", "gap"]
            if keys.contains(where: { e.has($0) }) {
                flex = (["row": 0, "column": 1][e.string("flex_direction") ?? ""] ?? 0,
                        parseFlex(e.string("justify_content")), parseFlex(e.string("align_content")),
                        parseFlex(e.string("align_items")), e.int("gap"))
            }
        case 7:
            try loadDataItem()
        default:
            break
        }
        if name.isEmpty { name = defaultName(theme: -1) }
    }

    /// 0x140029f50: ім'я ресурсу без атрибута name — «Short_theme_id» (або «Short_id» поза темою), id ще 0.
    func defaultName(theme t: Int) -> String {
        let id = UInt32(type) << 24 | (self.id & 0x7FFFF)
        return t == -1 ? "\(shortName)_\(hexUpper(id))" : "\(shortName)_\(t)_\(hexUpper(id))"
    }

    var shortName: String {
        switch type {
        case 0: return "Layout"
        case 2: return "Image"
        case 3: return "ImageArray"
        case 4: return "Sprite"
        case 5: return "File"
        case 6: return "Translation"
        case 8: return "Slot"
        case 9: return "Widget"
        default: return ["Text", "ImageNumber", "ImageValues", "Pointer", "ArcProgress", "LineProgress"][min(kind, 5)]
        }
    }

    func parseFormat(_ s: [UInt8]?) -> UInt8 {
        guard let s, !s.isEmpty else { return 0 }
        switch str(s) {
        case "RGBA32", "argb8888": return 0
        case "RGB565A8": return 6
        case "indexed8": return 0x10
        default: b.log.warn("Unknown image format: \(str(s)), assuming RGBA32"); return 0
        }
    }

    func parseFlex(_ s: String?) -> Int {
        guard let s else { return 0 }
        if let v = ["left": 0, "center": 1, "right": 2][s] { return v }
        if !b.quirks, let v = ["flex-start": 0, "flex-end": 2][s] { return v }   // виправлення: exe пише flex-*
        return 0
    }

    func loadImage(_ src: [UInt8]) throws -> (Int, Int, [UInt8]) {
        guard let d = b.storage.read(str(src)), let img = ImageDecoder.decode([UInt8](d)) else {
            throw FaceCompilerError("Image not found: " + str(src))
        }
        return (img.w, img.h, img.rgba)
    }

    // MARK: DataItem

    func loadDataItem() throws {
        name = e.string("name") ?? ""
        guard let k = BuildItem.diKinds[e.tag] else { throw FaceCompilerError("Unknown data format: " + e.tag) }
        kind = k
        switch e.string("renderRule") ?? "" {
        case "hideWhenUnitMismatch": rr = 2
        case "hideWhenOutRange": rr = 4
        default: rr = 0
        }
        if k != 0 { src = try Lookup.sourceId(e.raw("source")) }
        func val(_ key: String) throws -> (Bool, Int32) {
            if let s = e.raw(key + "Source") { return (true, Int32(try Lookup.sourceId(s))) }
            return (false, e.int(key))
        }
        switch k {
        case 0:
            color = try parseColor(e.raw("color"))
            let op = min(max(e.int("opacity", 100), 0), 100)
            color = (color & 0xFF_FFFF) | (((UInt32(bitPattern: 25500 - op * 255) / 100) & 0xFF) << 24)
            fontSize = e.int("fontSize", 10)
            fontId = font(e.string("fontId"), Lookup.fontIdByName, "fontId")
            fontWeight = font(e.string("fontWeight"), Lookup.fontWeightByName, "fontWeight")
            letterSpace = e.int("letterSpace")
            if let a = e.string("align") { talign = ["left": 0, "center": 1, "right": 2][a] ?? 1 } else { talign = 0 }
            if let m = e.string("longMode") { longMode = ["wrap": 0, "scroll": 2, "scroll_circular": 3, "clip": 4][m] ?? 1 } else { longMode = 1 }
            if let st = e.string("style") { arc = st != "normal" } else { arc = false }
            if !arc {
                lineSpace = e.int("lineSpace"); tw = e.int("w"); th = e.int("h"); rot = e.int("rotation") &* 10
            } else {
                radius = e.int("radius")
                if let va = e.string("verticalAlign") { valign = ["top": 0, "center": 1, "bottom": 2][va] ?? 0 } else { valign = 0 }
                a0 = e.int("startAngle") &* 10; a1 = e.int("span") &* 10
            }
            string = try required("string")
            contents = try e.all("Content").map { try Lookup.sourceId($0.raw("source")) }
        case 1:
            ref = try required("ref")
            total = e.int("totalDigits"); dec = e.int("decimalDigits")
            if let a = e.string("align") { dalign = ["left": 1, "center": 2, "right": 0][a] ?? 1 } else { dalign = 1 }
            lz = e.bool("leadingZero"); tz = e.bool("trailingZero")
            decoff = e.int("decimalOffsetX"); space = e.int("space"); rot = e.int("rotation") &* 10
            unit = e.raw("unitIcon") ?? []
        case 2:
            guard let r = e.raw("ref") else { throw FaceCompilerError("Error on line \(e.line): field ref is required!") }
            ref = r; rot = e.int("rotation") &* 10
            vals = e.all("Param").map { $0.int("value") }
        default:
            param = e.int("param", 1000)
            ref = try required("ref")
            vs = try val("valueStart"); vr = try val("valueRange")
            if k == 3 {
                px = e.int("pivotX"); py = e.int("pivotY"); a0 = e.int("angleStart") &* 10; a1 = e.int("angleRange") &* 10
            } else {
                bgRef = e.raw("bg") ?? []
                round = e.string("endingStyle") != "normal"
                ind = e.raw("indicatorImage") ?? []
                if k == 4 {
                    a0 = e.int("angleStart") &* 10; a1 = e.int("angleRange") &* 10; px = e.int("pivotX"); py = e.int("pivotY")
                    rad = e.int("barRadius"); bw = e.int("barWidth"); indr = e.int("indicatorRadius")
                } else {
                    sx = e.int("startX"); sy = e.int("startY"); ex = e.int("endX"); ey = e.int("endY")
                    bw = e.int("barWidth"); ox = e.int("offsetX"); oy = e.int("offsetY")
                }
            }
        }
    }

    func font(_ s: String?, _ table: [String: UInt32], _ what: String) -> UInt32 {
        guard let s else { return 0 }
        if let v = table[s] { return v }
        if !b.quirks, let v = toInt(Array(s.utf8)) { return UInt32(bitPattern: v) }   // виправлення: exe пише число, якщо назви немає
        b.log.warn("Unknown \(what)=\(s) on line \(e.line)")
        return 0
    }

    // MARK: Залежності (vtable[3]) з перевіркою типів

    func deps() throws -> [UInt32] {
        func L(_ r: [UInt8], _ t: Int) throws -> UInt32 { try b.lookup(r, t) }
        switch type {
        case 0: return ref.isEmpty ? [] : [try L(ref, -1)]
        case 4: return [try L(ref, 3)]
        case 8: return try slotItems.map { try L($0, -1) }
        case 9:
            var out: [UInt32] = []
            if let t = tname { out.append(try L(t, 6)) }
            if !preview.isEmpty { out.append(try L(preview, 2)) }
            if let eb = editbox { out.append(try L(eb, 2)) }
            if let a = args { out.append(try L(a, 5)) }
            out += try witems.map { try L($0.0, -1) }
            return out
        case 7:
            switch kind {
            case 1: return [try L(ref, 3)] + (unit.isEmpty ? [] : [try L(unit, 2)])
            case 2: return [try L(ref, 3)]
            case 3: return [try L(ref, 2)]
            case 4, 5:
                var out: [UInt32] = []
                if !bgRef.isEmpty { out.append(try L(bgRef, 2)) }
                out.append(try L(ref, 2))
                if !ind.isEmpty { out.append(try L(ind, 2)) }
                return out
            default: return []
            }
        default: return []
        }
    }

    // MARK: Серіалізація (vtable[2])

    func L(_ r: [UInt8]) throws -> UInt32 { try b.lookup(r) }

    func serialize() throws -> [UInt8] {
        var o = ByteWriter()
        switch type {
        case 0:
            o.u32(try L(ref)); o.u16(Int(x)); o.u16(Int(y)); o.u32(Int(param)); o.u32(0)
        case 2:
            let raw = try PixelFormat.encode(fmt, rgba, w, h)
            let data = comp ? RLE.block(raw, elem: PixelFormat.bpp(fmt)) : raw
            o.append([fmt, (recolor ? 1 : 0) | (comp ? 4 : 0), 0, 0]); o.u16(w); o.u16(h); o.u32(data.count); o.append(data)
        case 3:
            let E = PixelFormat.bpp(fmt)
            let raws = try frames.map { try PixelFormat.encode(fmt, $0, w, h) }
            let blobs = comp ? raws.map { RLE.block($0, elem: E) } : raws
            var tbl = ByteWriter()
            if comp { for x in blobs { tbl.u32(x.count) } }
            let body = blobs.flatMap { $0 }
            let total = comp ? 12 + tbl.bytes.count + body.count : body.count
            o.append([fmt, UInt8(truncatingIfNeeded: frames.count), (recolor ? 1 : 0) | (comp ? 4 : 0), 0])
            o.u16(w); o.u16(h); o.u32(total); o.append(tbl.bytes); o.append(body)
            // exe: нестиснутий масив пишеться довжиною total (без 12 байт заголовка) — хвіст обрізано
            if b.quirks, !comp { return Array(o.bytes.prefix(total)) }
        case 4:
            o.u32(try L(ref)); o.u16(0); o.u16(Int(interval)); o.u32(Int(repeatCount))
        case 5:
            o.u32((fileData.count & 0xFF_FFFF) | ((filename.count & 0xFF) << 24)); o.zeros(16); o.append(filename); o.append(fileData)
        case 6:
            var mask: UInt64 = 0
            var lens = ByteWriter(), body: [UInt8] = []
            for (i, s) in strs.enumerated() where !s.isEmpty { mask |= 1 << UInt64(i); lens.u32(s.count); body += s }
            o.u64(mask); o.append(lens.bytes); o.append(body)
        case 8:
            if slotType == "appWidget" {
                guard let v = Lookup.appWidgetByName[str(appWidget ?? [])] else {
                    throw FaceCompilerError("appWidgetId '\(str(appWidget ?? []))' is unknown!")
                }
                o.u16(0); o.u16(0x30); o.u16(Int(v)); o.zeros(8)
            } else {
                o.u8(slotItems.count); o.u8(0); o.u16((slotKind << 4) & 0xF0)
                for r in slotItems { o.u32(try L(r)) }
            }
        case 9:
            if let t = tname { o.u32(0xFFFF_FFFF); o.u32(try L(t)); o.zeros(24) }
            else { let nb = Array(wname.prefix(0x1F)); o.append(nb); o.zeros(0x20 - nb.count) }
            var fl = 0, bgv: UInt32 = 0
            if let bg { fl |= 1; bgv = bg }
            if let j = jump { fl = ((fl | 2) & 0xF00F) | (Int(j) << 4) }
            var body = ByteWriter()
            for (r, x, y) in witems { body.u16(Int(x)); body.u16(Int(y)); body.u32(try L(r)) }
            var tail = ByteWriter()
            if let eb = editbox { fl |= 4; tail.u32(try L(eb)) }
            if let sz = size { let (sw, sh) = sz; fl |= 0x1000; tail.u32(Int(((UInt32(bitPattern: sw) & 0xFFFF) << 16) &+ (UInt32(bitPattern: sh) & 0xFFFF))) }
            if let a = args { fl |= 0x2000; tail.u32(try L(a)) }
            if let fx = flex {
                let (d, j, ac, ai, gap) = fx
                let g16 = Int(Int16(truncatingIfNeeded: gap))
                let v = ((abs(g16) & 0xFF) << 11) + ((Int(UInt16(truncatingIfNeeded: gap)) >> 15) << 20)
                    + ((ai & 0xFF) << 8) + ((ac & 0xFF) << 5) + (j & 0xFF) * 4 + (d & 0xFF)
                fl |= 0x4000; tail.u32(v)
            }
            o.u32(bgv); o.u32(preview.isEmpty ? 0 : try L(preview)); o.u8(witems.count); o.u8(0); o.u16(fl)
            o.append(body.bytes); o.append(tail.bytes)
        case 7:
            return try serializeDataItem()
        default: break
        }
        return o.bytes
    }

    func serializeDataItem() throws -> [UInt8] {
        var o = ByteWriter()
        func head(_ b2: Int, _ b3: Int, _ param: Int) { o.u16(Int(src)); o.u8(b2); o.u8(b3); o.u16(rr); o.u16(param) }
        func v(_ x: (Bool, Int32)) { if x.0 { o.u32(Int(UInt32(bitPattern: x.1) & 0xFFFF)) } else { o.u32(Int(UInt32(bitPattern: x.1 << 8))) } }
        let clamp = min(max(Int(UInt16(truncatingIfNeeded: param)), 30), 1000)
        switch kind {
        case 0:
            let w0 = (Int(fontSize) & 0xFF) | ((Int(fontId) << 8) & 0x3F00) | ((Int(fontWeight) << 14) & 0x3C000) | ((Int(letterSpace) << 18) & 0x3FC_0000)
            let w1 = (talign & 7) | ((longMode << 3) & 0x38) | (arc ? 0x40 : 0)
            o.zeros(6); o.u16(1000); o.u32(color); o.u32(w0); o.u32(w1)
            if !arc {
                o.u32((Int(lineSpace) & 0xFF) | ((Int(tw) << 8) & 0x3_FF00) | ((Int(th) << 18) & 0xFFC_0000)); o.u16(Int(rot)); o.u16(0)
            } else {
                o.u32((Int(radius) & 0x3FF) | ((valign << 10) & 0xC00)); o.u16(Int(a0)); o.u16(Int(a1))
            }
            o.zeros(16)
            o.u32((string.count & 0xFF) | ((contents.count << 8) & 0xF00))
            o.append(string)
            for c in contents { o.u16(Int(c)) }
        case 1:
            head((Int(total) & 0xF) | ((Int(dec) << 4) & 0xF0), (dalign & 3) | (lz ? 4 : 0) | (tz ? 8 : 0) | 0x10, 1000)
            o.u32(try L(ref)); o.u8(Int(decoff)); o.u8(Int(space)); o.u16(Int(rot)); o.u32(unit.isEmpty ? 0 : try L(unit))
        case 2:
            head(0, 0x20, 1000)
            o.u32(try L(ref)); o.u8(0); o.u8(vals.isEmpty ? 0 : 2); o.u16(Int(rot))
            for x in vals { o.u32(Int(UInt32(bitPattern: x))) }
        case 3:
            head(0, 0x30, clamp)
            o.u32(try L(ref)); v(vs); v(vr); o.u16(Int(px)); o.u16(Int(py)); o.u16(Int(a0)); o.u16(Int(a1))
            o.u32((vs.0 ? 4 : 0) | (vr.0 ? 8 : 0))
        default:
            let fl = (vs.0 ? 4 : 0) | (vr.0 ? 8 : 0) | (round ? 1 : 0) | (ind.isEmpty ? 0 : 2)
            head(0, kind << 4, clamp)
            o.u32(try L(ref)); o.u32(bgRef.isEmpty ? 0 : try L(bgRef)); o.u32(fl); v(vs); v(vr)
            if kind == 4 {
                o.u16(Int(px)); o.u16(Int(py)); o.u16(Int(a0)); o.u16(Int(a1)); o.u16(Int(rad)); o.u16(Int(bw))
                if !ind.isEmpty { o.u32(try L(ind)); o.u16(Int(indr)); o.zeros(6) }
            } else {
                o.u16(Int(sx)); o.u16(Int(sy)); o.u16(Int(ex)); o.u16(Int(ey)); o.u16(0); o.u16(Int(bw))
                if !ind.isEmpty { o.u32(try L(ind)); o.u16(Int(ox)); o.u16(Int(oy)); o.zeros(4) }
            }
        }
        return o.bytes
    }
}
