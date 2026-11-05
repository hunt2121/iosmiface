// SPDX-License-Identifier: MIT
// Збирання manifest.xml + ресурсів -> .bin (порт WatchfaceCompiler 0.9.8: читач 0x140025c70, фабрика 0x140041ba0,
// XML-конструктори класів, обхід залежностей 0x1400244f0, серіалізатор 0x140027190).

import Foundation

public final class FaceBuilder {
    let storage: FaceStorage
    let options: FaceCompilerOptions
    let log: FaceCompilerLog
    var quirks: Bool { options.exeQuirks }

    // стан як у exe
    var header = [UInt8](repeating: 0, count: 0xA8)
    var colors: [UInt32] = []
    var registry: [UInt32: String] = [:]      // id -> ім'я (std::map, зростання id)
    var byName: [String: UInt32] = [:]        // ім'я -> найменший id
    var usedIds: Set<UInt32> = []
    var counters: [Int: UInt32] = [:]
    var lists: [Int: [BuildItem]] = [:]       // глобальні списки за типом
    var themes: [BuildTheme] = []

    public init(storage: FaceStorage, options: FaceCompilerOptions = .init(), log: FaceCompilerLog = .init()) {
        self.storage = storage; self.options = options; self.log = log
    }

    // MARK: Реєстр імен

    /// LOOKUP_ID (0x140041630): "" -> 0; перший символ відкидається без перевірки.
    func lookup(_ ref: [UInt8], _ want: Int = -1) throws -> UInt32 {
        if ref.isEmpty { return 0 }
        let key = str(Array(ref.dropFirst()))
        guard let id = byName[key] else { throw FaceCompilerError("Unknown resource with name=" + key) }
        if want != -1, Int(id >> 24) != want { throw FaceCompilerError("\(key) is not allowed to reference somewhere") }
        return id
    }

    /// Призначення id (0x140042010).
    func assign(_ it: BuildItem) -> UInt32 {
        let t = it.type
        if t != 0, let found = byName[it.name] {
            let id = UInt32(t) << 24 | (found & 0x7FFFF)
            if usedIds.contains(id) { log.warn("Found another element with same name: " + it.name) } else { usedIds.insert(id) }
            return id
        }
        let n = counters[t, default: 0]; counters[t] = n &+ 1
        let id = UInt32(t) << 24 | n
        if registry[id] == nil {
            registry[id] = it.name
            if let cur = byName[it.name] { if id < cur { byName[it.name] = id } } else { byName[it.name] = id }
        }
        return id
    }

    // MARK: Обхід залежностей теми (0x1400244f0)

    func walk(_ ti: BuildTheme, _ it: BuildItem) throws {
        for dep in try it.deps() {
            let ty = Int(dep >> 24)
            guard ty < 10 else { throw FaceCompilerError("Unknown resource with uid=\(String(dep, radix: 16))") }
            let g = lists[ty]?.first { $0.realId == dep }
            if !ti.tables[ty].contains(where: { $0.realId == dep }) {
                guard let g else { throw FaceCompilerError("Unknown resource with uid=\(String(dep, radix: 16))") }
                ti.tables[ty].append(g)
                try walk(ti, g)
            }
        }
        if it.type == 2 || it.type == 3 {
            for c in ti.colorGroups where c != 0 {
                let nid = UInt32(it.type) << 24 | (c & 0xFF) << 19 | (it.id & 0x7FFFF)
                if let g = lists[it.type]?.first(where: { $0.realId == nid }) { ti.tables[it.type].append(g) }
                else { ti.tables[it.type].append(it.clone(colorGroup: UInt8(c & 0xFF))) }
            }
        }
    }

    // MARK: Читання маніфесту (0x140025c70)

    func load() throws {
        log.info("Reading manifest.xml...")
        guard let data = storage.read("manifest.xml") else { throw FaceCompilerError("Error opening manifest.xml! Aborting...") }
        let doc: XNode?
        do { doc = try XML.parse([UInt8](data)) } catch let e as XML.ParseError { throw FaceCompilerError("Error opening manifest.xml: " + e.message) }
        guard let w = doc, w.tag == "Watchface" else { throw FaceCompilerError("Watchface should have id parameter!") }
        header = [UInt8](repeating: 0, count: 0xA8)
        put32(&header, 0, 0x1234_A55A); put32(&header, 4, 0x10000); put32(&header, 8, 0x10000); put32(&header, 0x10, 0x800)
        colors = []
        if w.has("recolorTable") { colors += try parseColorList(w.raw("recolorTable")) }
        header[0x1D] = UInt8(truncatingIfNeeded: colors.count)
        if w.has("colorGroupTable") { colors += try parseColorList(w.raw("colorGroupTable")) }
        put32(&header, 0x18, UInt32(colors.count))
        registry = [:]; byName = [:]; usedIds = []; counters = [:]; lists = [:]; themes = []
        for e in w.first("Resources")?.elements ?? [] {
            let it = try BuildItem.create(self, e)
            lists[it.type, default: []].append(it)
            it.id = assign(it)
        }
        let themeEls = w.all("Theme")
        if themeEls.isEmpty { throw FaceCompilerError("No themes found in watchface!") }
        for (t, te) in themeEls.enumerated() {
            let ti = BuildTheme()
            put32(&ti.entry, 0, try parseColor(te.raw("bgColor")))
            if te.string("type") == "AOD" {
                put32(&ti.entry, 0x9C, (get32(ti.entry, 0x9C) & ~2) | 1); header[0x1E] |= 4
            }
            var cgt = te.raw("colorGroupTable")
            if cgt == nil, !quirks { cgt = te.raw("colorGroup") }    // виправлення: exe пише «colorGroup», а читає «colorGroupTable»
            if let cgt {
                for c in try parseColorList(cgt) {
                    guard let i = colors.firstIndex(of: c) else { throw FaceCompilerError("Color #\(hexUpper(c, width: 6)) is not specified in Watchface colorGroupTable!") }
                    ti.colorGroups.append(UInt32(i))
                }
                put32(&ti.entry, 0x9C, (get32(ti.entry, 0x9C) & ~0x3FC) | (UInt32(ti.colorGroups.count * 4) & 0x3FC))
            }
            if let nm = te.raw("name") {
                if nm.first == 0x40 { throw FaceCompilerError("translations in theme headers are not supported yet") }
                for (i, c) in nm.prefix(0x40).enumerated() { ti.entry[0x58 + i] = c }
            }
            if let pv = te.raw("preview") {
                guard pv.first == 0x40 else { throw FaceCompilerError("theme preview should be a reference, starts with @. Got: " + str(pv)) }
                let key = str(Array(pv.dropFirst()))
                guard let g = lists[2]?.first(where: { $0.name == key }) else {
                    throw FaceCompilerError("Reference to theme \(t) preview (\(str(pv))) not resolved!")
                }
                ti.preview = g
            }
            themes.append(ti); header[0x1C] = UInt8(truncatingIfNeeded: themes.count)
            for le in te.all("Layout") {
                let it = try BuildItem(self, le, type: 0)
                it.theme = t
                it.id = assign(it)
                ti.tables[0].append(it)
                try walk(ti, it)
            }
            ti.tables[5] += lists[5] ?? []
        }
        guard let wid = w.raw("id") else { throw FaceCompilerError("Watchface should have id parameter!") }
        if wid.count != 9 && wid.count != 12 { throw FaceCompilerError("Watchface id must be 9 or 12 digits long!") }
        if !wid.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) { throw FaceCompilerError("Watchface id must use digits only!") }
        for (i, c) in wid.enumerated() { header[0x28 + i] = c }
        let name = w.raw("name") ?? []
        if name.first == 0x40 { throw FaceCompilerError("translation in watchface header is not supported yet") }
        for (i, c) in name.prefix(0x40).enumerated() { header[0x68 + i] = c }
        let anyAOD = Int((header[0x1E] >> 2) & 1)
        let slots = themes.contains { !$0.tables[8].isEmpty }
        var fl = header[0x1E] & ~2
        if themes.count - anyAOD > 1 || slots || !colors.isEmpty { fl |= 2 }
        header[0x1E] = fl
    }

    // MARK: Серіалізація (0x140027190)

    public func build() throws -> Data {
        log.info("Packing from project directory")
        try load()
        var off = 0xA8 + 4 * colors.count + themes.reduce(0) { $0 + 0xA0 + 4 * $1.colorGroups.count }
        for ti in themes {
            for ty in 0..<10 {
                put32(&ti.entry, 8 + 8 * ty, UInt32(ti.tables[ty].count)); put32(&ti.entry, 12 + 8 * ty, UInt32(off))
                off += 16 * ti.tables[ty].count
            }
        }
        var blobs: [[UInt8]] = []
        for ti in themes {
            if let p = ti.preview {
                let d = try p.serialize()
                put32(&ti.entry, 4, UInt32(off)); blobs.append(d); off += d.count
            }
        }
        put32(&header, 0x20, get32(themes[0].entry, 4))
        var recs = ByteWriter()
        for ti in themes {
            for ty in 0..<10 {
                for it in ti.tables[ty] {
                    let d = try it.serialize()
                    recs.u32(it.realId); recs.u32(0); recs.u32(off); recs.u32(d.count)
                    blobs.append(d); off += d.count
                }
            }
        }
        var out = header
        for c in colors { out += le32(c) }
        for ti in themes { out += ti.entry; for c in ti.colorGroups { out += le32(c) } }
        out += recs.bytes
        for bl in blobs { out += bl }
        log.info("Saved")
        return Data(out)
    }

    /// Реєстр (--uidmap): «name: hex» із CR LF, лише записи з типом.
    public func uidMap() -> [UInt8] {
        var out = [UInt8]()
        for id in registry.keys.sorted() where id & 0x0F00_0000 != 0 {
            out += Array("\(registry[id]!): \(String(id, radix: 16))\r\n".utf8)
        }
        return out
    }
}

final class BuildTheme {
    var entry = [UInt8](repeating: 0, count: 0xA0)
    var tables: [[BuildItem]] = Array(repeating: [], count: 10)
    var colorGroups: [UInt32] = []
    var preview: BuildItem?
}

func put32(_ a: inout [UInt8], _ o: Int, _ v: UInt32) {
    a[o] = UInt8(v & 0xFF); a[o + 1] = UInt8((v >> 8) & 0xFF); a[o + 2] = UInt8((v >> 16) & 0xFF); a[o + 3] = UInt8(v >> 24)
}
func get32(_ a: [UInt8], _ o: Int) -> UInt32 { a.u32(o) }
func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
