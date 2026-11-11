// SPDX-License-Identifier: MIT
// Порт WatchfaceCompiler 0.9.8: спільні типи, байтові помічники, розбір чисел і кольорів як у exe.

import Foundation

/// Критична помилка компілятора (exe: «Critical error: …»).
public struct FaceCompilerError: Error, LocalizedError, CustomStringConvertible, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

/// Налаштування порту.
public struct FaceCompilerOptions: Sendable {
    /// Відтворювати відомі помилки exe (для побайтової звірки з еталоном). Типово — виправлена поведінка.
    public var exeQuirks: Bool
    /// Кольорові варіанти: копіювати в кожен колір і ті картинки, що не змінюються (так робить exe).
    /// false — лише справжні варіанти; файл значно менший, але Smart Band 10 тоді перезавантажується при виборі кольору.
    public var colorCopies: Bool
    public init(exeQuirks: Bool = false, colorCopies: Bool = true) { self.exeQuirks = exeQuirks; self.colorCopies = colorCopies }
}

/// Журнал повідомлень (exe пише в консоль через spdlog).
public final class FaceCompilerLog: @unchecked Sendable {
    public enum Level: String, Sendable { case info, warning }
    public private(set) var lines: [(Level, String)] = []
    public var onLine: ((Level, String) -> Void)?
    public init() {}
    func info(_ s: String) { lines.append((.info, s)); onLine?(.info, s) }
    func warn(_ s: String) { lines.append((.warning, s)); onLine?(.warning, s) }
    public var warnings: [String] { lines.filter { $0.0 == .warning }.map { $0.1 } }
}

// MARK: - Сховище файлів проєкту

/// Доступ до файлів проєкту циферблата (шляхи відносні, з «/»).
public protocol FaceStorage: AnyObject {
    func read(_ path: String) -> Data?
    func write(_ path: String, _ data: Data) throws
}

/// Файли в пам'яті — для застосунку.
public final class MemoryStorage: FaceStorage {
    public var files: [String: Data]
    public init(_ files: [String: Data] = [:]) { self.files = files }
    public func read(_ path: String) -> Data? { files[MemoryStorage.normalize(path)] }
    public func write(_ path: String, _ data: Data) throws { files[MemoryStorage.normalize(path)] = data }
    static func normalize(_ p: String) -> String {
        var parts: [Substring] = []
        for c in p.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true) {
            if c == "." { continue }
            if c == "..", !parts.isEmpty { parts.removeLast(); continue }
            parts.append(c)
        }
        return parts.joined(separator: "/")
    }
}

/// Файли в теці на диску.
public final class DirectoryStorage: FaceStorage {
    public let root: URL
    public init(_ root: URL) { self.root = root }
    public func read(_ path: String) -> Data? { try? Data(contentsOf: root.appendingPathComponent(path)) }
    public func write(_ path: String, _ data: Data) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

// MARK: - Байти

extension Array where Element == UInt8 {
    @inline(__always) func u8(_ o: Int) -> UInt8 { o >= 0 && o < count ? self[o] : 0 }
    @inline(__always) func u16(_ o: Int) -> UInt16 { UInt16(u8(o)) | UInt16(u8(o + 1)) << 8 }
    @inline(__always) func i16(_ o: Int) -> Int16 { Int16(bitPattern: u16(o)) }
    @inline(__always) func u32(_ o: Int) -> UInt32 { UInt32(u16(o)) | UInt32(u16(o + 2)) << 16 }
    @inline(__always) func i32(_ o: Int) -> Int32 { Int32(bitPattern: u32(o)) }
    @inline(__always) func u64(_ o: Int) -> UInt64 { UInt64(u32(o)) | UInt64(u32(o + 4)) << 32 }
    /// Відрізок; за межами масиву — нулі (exe читає за кінець запису без перевірки).
    func slice(_ o: Int, _ n: Int) -> [UInt8] {
        guard n > 0 else { return [] }
        if o >= 0, o + n <= count { return Array(self[o..<(o + n)]) }
        return (0..<n).map { u8(o + $0) }
    }
    /// C-рядок у межах n байт.
    func cstr(_ o: Int, _ n: Int) -> [UInt8] {
        var r: [UInt8] = []
        var i = o
        while i < o + n, i < count, self[i] != 0 { r.append(self[i]); i += 1 }
        return r
    }
}

struct ByteWriter {
    var bytes: [UInt8] = []
    mutating func u8(_ v: Int) { bytes.append(UInt8(truncatingIfNeeded: v)) }
    mutating func u16(_ v: Int) { u8(v); u8(v >> 8) }
    mutating func u32(_ v: Int) { u16(v); u16(v >> 16) }
    mutating func u32(_ v: UInt32) { u32(Int(v)) }
    mutating func u64(_ v: UInt64) { u32(Int(v & 0xFFFF_FFFF)); u32(Int(v >> 32)) }
    mutating func zeros(_ n: Int) { bytes.append(contentsOf: [UInt8](repeating: 0, count: max(0, n))) }
    mutating func append(_ b: [UInt8]) { bytes.append(contentsOf: b) }
}

/// Байти UTF-8 -> String без втрат для коректного UTF-8 (для повідомлень).
func str(_ b: [UInt8]) -> String { String(decoding: b, as: UTF8.self) }

// MARK: - Числа як у tinyxml2 (XMLUtil::ToInt через MSVC sscanf)

private func isSpace(_ c: UInt8) -> Bool { c == 0x20 || (c >= 0x09 && c <= 0x0D) }

/// %d / %x з переповненням за модулем 2^32; nil — якщо не число.
func toInt(_ s: [UInt8]?) -> Int32? {
    guard let s else { return nil }
    var i = 0
    while i < s.count, isSpace(s[i]) { i += 1 }
    if i + 1 < s.count, s[i] == 0x30, s[i + 1] | 0x20 == 0x78 {
        // "%x" після «0x»: шістнадцяткові цифри (без цифр — 0)
        var j = i + 2
        var v: UInt32 = 0, n = 0
        while j < s.count, let d = hexDigit(s[j]) { v = v &* 16 &+ UInt32(d); j += 1; n += 1 }
        return n > 0 ? Int32(bitPattern: v) : Int32(0)
    }
    var neg = false
    if i < s.count, s[i] == 0x2B || s[i] == 0x2D { neg = s[i] == 0x2D; i += 1 }
    var v: UInt32 = 0, n = 0
    while i < s.count, s[i] >= 0x30, s[i] <= 0x39 { v = v &* 10 &+ UInt32(s[i] - 0x30); i += 1; n += 1 }
    guard n > 0 else { return nil }
    return Int32(bitPattern: neg ? 0 &- v : v)
}

func hexDigit(_ c: UInt8) -> Int? {
    switch c {
    case 0x30...0x39: return Int(c - 0x30)
    case 0x41...0x46: return Int(c - 0x41 + 10)
    case 0x61...0x66: return Int(c - 0x61 + 10)
    default: return nil
    }
}

func toBool(_ s: [UInt8]?) -> Bool? {
    guard let s else { return nil }
    if let v = toInt(s) { return v != 0 }
    switch str(s) {
    case "true", "True", "TRUE": return true
    case "false", "False", "FALSE": return false
    default: return nil
    }
}

/// Колір «#RRGGBB» (0x14004c740): nil -> 0x80000000; результат 0x80RRGGBB.
func parseColor(_ s: [UInt8]?) throws -> UInt32 {
    guard let s else { return 0x8000_0000 }
    guard s.first == 0x23 else { throw FaceCompilerError("Color must contain #") }
    var v: UInt32 = 0
    for c in s.dropFirst() {
        guard let d = hexDigit(c) else { throw FaceCompilerError("unknown symbol") }
        v = v &* 16 &+ UInt32(d)
    }
    return (v & 0xFF_FFFF) | 0x8000_0000
}

/// Список кольорів через кому (0x14004c830).
func parseColorList(_ s: [UInt8]?) throws -> [UInt32] {
    guard let s else { return [] }
    return try s.split(separator: 0x2C).compactMap { part -> UInt32? in
        let t = Array(part).trimmingSpaces()
        return t.isEmpty ? nil : (try parseColor(t) & 0xFF_FFFF)
    }
}

extension Array where Element == UInt8 {
    func trimmingSpaces() -> [UInt8] {
        var a = startIndex, b = endIndex
        while a < b, isSpace(self[a]) { a += 1 }
        while b > a, isSpace(self[b - 1]) { b -= 1 }
        return Array(self[a..<b])
    }
}

func hex6(_ v: UInt32) -> String {
    let s = String(v & 0xFF_FFFF, radix: 16, uppercase: true)
    return "#" + String(repeating: "0", count: max(0, 6 - s.count)) + s
}

func hexUpper(_ v: UInt32, width: Int = 0) -> String {
    let s = String(v, radix: 16, uppercase: true)
    return String(repeating: "0", count: max(0, width - s.count)) + s
}

// MARK: - Довідники (std::map)

enum Lookup {
    static let sourceByName: [String: UInt16] = {
        var m: [String: UInt16] = [:]
        for (n, v) in FaceTables.sources where m[n] == nil { m[n] = v }
        return m
    }()
    /// id -> назва: перша за алфавітним порядком std::map (побайтове порівняння)
    static let sourceById: [UInt16: String] = firstByName(FaceTables.sources.map { ($0.0, UInt32($0.1)) }).mapKeys { UInt16($0) }
    static let jumpByName: [String: UInt8] = {
        var m: [String: UInt8] = [:]
        for (v, n) in FaceTables.jumpApps where m[n] == nil { m[n] = v }
        return m
    }()
    static let jumpById: [UInt8: String] = firstByName(FaceTables.jumpApps.map { ($0.1, UInt32($0.0)) }).mapKeys { UInt8($0) }
    static let appWidgetByName: [String: UInt16] = Dictionary(FaceTables.appWidgets, uniquingKeysWith: { a, _ in a })
    static let appWidgetById: [UInt16: String] = firstByName(FaceTables.appWidgets.map { ($0.0, UInt32($0.1)) }).mapKeys { UInt16($0) }
    static let fontIdByName: [String: UInt32] = Dictionary(FaceTables.fontIds, uniquingKeysWith: { a, _ in a })
    static let fontIdById: [UInt32: String] = firstByName(FaceTables.fontIds)
    static let fontWeightByName: [String: UInt32] = Dictionary(FaceTables.fontWeights, uniquingKeysWith: { a, _ in a })
    static let fontWeightById: [UInt32: String] = firstByName(FaceTables.fontWeights)

    static func firstByName(_ pairs: [(String, UInt32)]) -> [UInt32: String] {
        var m: [UInt32: String] = [:]
        for (n, v) in pairs.sorted(by: { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }) where m[v] == nil { m[v] = n }
        return m
    }

    static func sourceName(_ v: UInt16) -> String { sourceById[v] ?? hexUpper(UInt32(v), width: 4) }

    /// Назва джерела -> id (0x1400400d0): рядок із лише шістнадцяткових цифр — число.
    static func sourceId(_ s: [UInt8]?) throws -> UInt16 {
        let s = s ?? []
        if !s.isEmpty, s.allSatisfy({ hexDigit($0) != nil }) {
            var v: UInt64 = 0
            for c in s {
                v = v * 16 + UInt64(hexDigit(c)!)
                if v > 0x7FFF_FFFF { throw FaceCompilerError("stoi argument out of range") }
            }
            return UInt16(truncatingIfNeeded: v)
        }
        guard let v = sourceByName[str(s)] else { throw FaceCompilerError("Source unknown: " + str(s)) }
        return v
    }
}

extension Dictionary where Key == UInt32 {
    func mapKeys<K: Hashable>(_ f: (UInt32) -> K) -> [K: Value] {
        var m: [K: Value] = [:]
        for (k, v) in self { m[f(k)] = v }
        return m
    }
}
