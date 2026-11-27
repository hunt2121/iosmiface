// SPDX-License-Identifier: MIT
import Foundation
import zlib

public enum RpkError: Error, LocalizedError, Sendable {
    case invalidFile(String)
    case rejected(String)
    case unconfirmed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidFile(let reason): return "Некорректный RPK: \(reason)"
        case .rejected(let reason), .unconfirmed(let reason): return reason
        }
    }
}

/// Reads only the manifest; the original signed archive is transmitted unchanged.
public struct RpkFile: Sendable {
    public let data: [UInt8]
    public let id: String
    public let name: String
    public let versionName: String
    public let versionCode: UInt32
    public var size: Int { data.count }
    public var md5: [UInt8] { BandCrypto.md5(data) }

    public init(data: Data) throws {
        guard data.count >= 22, data.count <= 64 * 1024 * 1024 else {
            throw RpkError.invalidFile("размер должен быть не больше 64 МБ")
        }
        let original = [UInt8](data)
        let manifest = try RpkZIP.manifest(in: original)
        struct Manifest: Decodable { let package: String; let name: String; let versionName: String?; let versionCode: UInt32? }
        let parsed: Manifest
        do { parsed = try JSONDecoder().decode(Manifest.self, from: Data(manifest)) }
        catch { throw RpkError.invalidFile("не удалось прочитать manifest.json") }
        guard !parsed.package.isEmpty, parsed.package.utf8.count <= 255,
              parsed.package.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil,
              !parsed.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RpkError.invalidFile("в manifest.json нет корректного package или name")
        }
        self.data = original; id = parsed.package; name = parsed.name
        versionName = parsed.versionName ?? ""; versionCode = parsed.versionCode ?? 1
    }
}

// Bounded ZIP central-directory reader. Supports stored/deflate entries and data
// descriptors, including signed archives with a signing block before the directory.
// ZIP64, split archives and encrypted manifests are deliberately rejected.
enum RpkZIP {
    static func manifest(in bytes: [UInt8]) throws -> [UInt8] {
        func fail(_ message: String) -> RpkError { .invalidFile(message) }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count >= 22 else { throw fail("обрезанный ZIP") }
        let floor = max(0, bytes.count - 65557)
        guard let end = stride(from: bytes.count - 22, through: floor, by: -1).first(where: {
            u32($0) == 0x06054b50 && $0 + 22 + u16($0 + 20) == bytes.count
        }) else { throw fail("не найден каталог ZIP") }
        let count = u16(end + 10), length = u32(end + 12), start = u32(end + 16)
        guard u16(end + 4) == 0, u16(end + 6) == 0, u16(end + 8) == count,
              count < 65535, start <= end, length <= end - start else { throw fail("ZIP64 или многотомный ZIP не поддерживается") }
        var at = start
        var result: [UInt8]?
        for _ in 0..<count {
            guard at + 46 <= start + length, u32(at) == 0x02014b50 else { throw fail("повреждён каталог ZIP") }
            let flags = u16(at + 8), method = u16(at + 10), crc = UInt32(u32(at + 16))
            let packed = u32(at + 20), size = u32(at + 24), nameLength = u16(at + 28)
            let next = at + 46 + nameLength + u16(at + 30) + u16(at + 32)
            guard next <= start + length else { throw fail("обрезанная запись ZIP") }
            let name = String(bytes: bytes[(at + 46)..<(at + 46 + nameLength)], encoding: .utf8)
            if name == "manifest.json" {
                guard result == nil else { throw fail("несколько manifest.json") }
                guard flags & 1 == 0, [0, 8].contains(method), size > 0, size <= 1024 * 1024, packed <= 2 * 1024 * 1024 else {
                    throw fail("неподдерживаемый или слишком большой manifest.json")
                }
                let local = u32(at + 42)
                guard local + 30 <= start, u32(local) == 0x04034b50,
                      u16(local + 8) == method, u16(local + 6) & 1 == 0 else { throw fail("неверный заголовок manifest.json") }
                let dataStart = local + 30 + u16(local + 26) + u16(local + 28)
                guard dataStart <= start, packed <= start - dataStart else { throw fail("обрезанный manifest.json") }
                let localName = bytes[(local + 30)..<(local + 30 + u16(local + 26))]
                guard Array(localName) == Array("manifest.json".utf8) else { throw fail("имя manifest.json не совпадает") }
                let compressed = Array(bytes[dataStart..<(dataStart + packed)])
                let output = method == 0 ? compressed : try inflate(compressed, size: size)
                guard output.count == size, Checksum.crc32(output) == crc else { throw fail("контрольная сумма manifest.json не совпадает") }
                result = output
            }
            at = next
        }
        guard at == start + length, let result else { throw fail("manifest.json отсутствует") }
        return result
    }

    private static func inflate(_ source: [UInt8], size: Int) throws -> [UInt8] {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw RpkError.invalidFile("ошибка ZIP-декодера")
        }
        defer { inflateEnd(&stream) }
        var input = source, output = [UInt8](repeating: 0, count: size)
        let status = input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                stream.next_in = inputBuffer.baseAddress; stream.avail_in = uInt(inputBuffer.count)
                stream.next_out = outputBuffer.baseAddress; stream.avail_out = uInt(outputBuffer.count)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == size, stream.total_in == source.count else {
            throw RpkError.invalidFile("повреждён сжатый manifest.json")
        }
        return output
    }
}
