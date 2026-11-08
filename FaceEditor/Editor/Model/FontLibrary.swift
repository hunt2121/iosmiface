// SPDX-License-Identifier: MIT
// Бібліотека шрифтів користувача: .ttf / .otf / .ttc із «Файлів». Копіюються в теку застосунку,
// реєструються для цього процесу й доступні для цифр і написів у будь-якому проєкті.

import Foundation
import UIKit
import CoreText

enum FontLibrary {
    struct Entry: Identifiable, Hashable {
        /// PostScript-назва — за нею шрифт зберігається в параметрах елемента
        let name: String
        let family: String
        let style: String
        let file: String
        var id: String { name }
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var registered = Set<String>()

    /// Усі шрифти з бібліотеки (реєструє їх при першому зверненні)
    static func all() -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var out: [Entry] = []
        for url in files where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
            register(url)
            guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { continue }
            for d in descs {
                let name = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String ?? url.lastPathComponent
                let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String ?? name
                let style = CTFontDescriptorCopyAttribute(d, kCTFontStyleNameAttribute) as? String ?? ""
                out.append(Entry(name: name, family: family, style: style, file: url.lastPathComponent))
            }
        }
        return out.sorted { ($0.family, $0.style) < ($1.family, $1.style) }
    }

    private static func register(_ url: URL) {
        guard !registered.contains(url.path) else { return }
        registered.insert(url.path)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Додати файл шрифту (з «Файлів»). Повертає додані шрифти (у .ttc їх може бути кілька).
    @discardableResult static func add(_ src: URL) throws -> [Entry] {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        var dst = folder.appendingPathComponent(src.lastPathComponent)
        var i = 2
        while FileManager.default.fileExists(atPath: dst.path) {
            dst = folder.appendingPathComponent(src.deletingPathExtension().lastPathComponent + " \(i)." + src.pathExtension); i += 1
        }
        try FileManager.default.copyItem(at: src, to: dst)
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(dst as CFURL) as? [CTFontDescriptor], !descs.isEmpty else {
            try? FileManager.default.removeItem(at: dst)
            throw NSError(domain: "BandFace", code: 1, userInfo: [NSLocalizedDescriptionKey: loc("Це не файл шрифту")])
        }
        register(dst)
        return all().filter { $0.file == dst.lastPathComponent }
    }

    /// Видалити файл (з усіма шрифтами в ньому)
    static func remove(_ e: Entry) {
        let url = folder.appendingPathComponent(e.file)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        registered.remove(url.path)
        try? FileManager.default.removeItem(at: url)
    }

    static func font(_ name: String, size: CGFloat) -> UIFont? {
        if UIFont(name: name, size: size) == nil { _ = all() }
        return UIFont(name: name, size: size)
    }

    /// Які символи є: цифри, латиниця, кирилиця (українські літери) — щоб одразу видно, чи підійде шрифт
    static func coverage(_ name: String) -> String {
        guard let f = font(name, size: 20) else { return "" }
        let ct = f as CTFont
        func has(_ s: String) -> Bool {
            let u = Array(s.utf16)
            var g = [CGGlyph](repeating: 0, count: u.count)
            return CTFontGetGlyphsForCharacters(ct, u, &g, u.count) && !g.contains(0)
        }
        var parts: [String] = []
        if has("0123456789") { parts.append(loc("цифри")) }
        if has("AaZz") { parts.append(loc("латиниця")) }
        if has("АаЯяЇїЄєҐґІі") { parts.append(loc("кирилиця")) }
        return parts.isEmpty ? loc("немає звичних символів") : parts.joined(separator: " · ")
    }
}

/// Набори цифр (П-2): готові стилі й збережені користувачем — вигляд без розміру
enum DigitSets {
    struct DigitSet: Identifiable { let name: String; let style: Generator; let builtIn: Bool; var id: String { name } }

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("digitsets.json")
    }

    private struct Stored: Codable { var name: String; var style: Generator }

    private static func g(_ f: (inout Generator) -> Void) -> Generator {
        var g = Generator(kind: .digits); g.color = "#FFFFFF"; g.weight = 700; g.style = "rounded"; f(&g); return g
    }

    static var builtIns: [DigitSet] { [
        DigitSet(name: loc("Класичний"), style: g { _ in }, builtIn: true),
        DigitSet(name: loc("Неон"), style: g { $0.color = "#7DF9FF"; $0.outline = 2; $0.outlineColor = "#0A84FF" }, builtIn: true),
        DigitSet(name: loc("Захід сонця"), style: g { $0.color = "#FFD60A"; $0.color2 = "#FF375F"; $0.weight = 800 }, builtIn: true),
        DigitSet(name: loc("З тінню"), style: g { $0.shadowX = 2; $0.shadowY = 3; $0.weight = 800 }, builtIn: true),
        DigitSet(name: loc("Вузький"), style: g { $0.style = "condensed"; $0.widthPct = 80; $0.weight = 600 }, builtIn: true),
        DigitSet(name: loc("Контур"), style: g { $0.color = "#000000"; $0.outline = 2; $0.outlineColor = "#FFFFFF"; $0.weight = 800 }, builtIn: true),
    ] }

    static func user() -> [DigitSet] {
        guard let d = try? Data(contentsOf: file), let l = try? JSONDecoder().decode([Stored].self, from: d) else { return [] }
        return l.map { DigitSet(name: $0.name, style: $0.style, builtIn: false) }
    }

    static func all() -> [DigitSet] { builtIns + user() }

    private static func save(_ l: [DigitSet]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(l.map { Stored(name: $0.name, style: $0.style) }) { try? d.write(to: file) }
    }

    static func add(_ name: String, style: Generator) {
        var l = user().filter { $0.name.lowercased() != name.lowercased() }
        var s = Generator(kind: .digits); s.applyStyle(style)
        l.append(DigitSet(name: name, style: s, builtIn: false))
        save(l)
    }

    static func remove(_ name: String) { save(user().filter { $0.name != name }) }
}
