// SPDX-License-Identifier: MIT
//
// Розбір заголовка файлу циферблата (.face / .bin) і декодування прев'ю.
// Браслету файл передається без змін; тут читаються лише ID, назва і прев'ю.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct FaceFile: Sendable {
    public static let signature: [UInt8] = [0x5A, 0xA5]

    public let data: [UInt8]
    /// ID циферблата — рядок ASCII-цифр (наприклад, «266235369»).
    public let id: String
    /// Назва, якщо вона не локалізована.
    public let name: String?
    public let previewOffset: Int?

    public init(data: Data) throws {
        try self.init(bytes: [UInt8](data))
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= 0x7C else { throw BandError.invalidFaceFile("file too short") }
        guard Array(bytes[0..<2]) == FaceFile.signature else {
            throw BandError.invalidFaceFile("bad signature")
        }
        data = bytes

        let idBytes = FaceFile.zeroTerminated(bytes, from: 0x28, maxLength: 0x40)
        guard !idBytes.isEmpty, idBytes.allSatisfy({ (0x30...0x39).contains($0) }),
              let id = String(bytes: idBytes, encoding: .ascii)
        else { throw BandError.invalidFaceFile("bad watchface id") }
        self.id = id

        if Array(bytes[0x68..<0x6C]) == [0xFF, 0xFF, 0xFF, 0xFF] {
            name = nil // локалізована назва: таблиця за зміщенням 0x74 / довжиною 0x78
        } else {
            let nameBytes = FaceFile.zeroTerminated(bytes, from: 0x68, maxLength: 0x40)
            name = String(bytes: nameBytes, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
        }

        let offset = Int(bytes.le32(at: 0x20))
        previewOffset = (offset == 0 || offset + 12 > bytes.count) ? nil : offset
    }

    public var size: Int { data.count }

    public var md5: [UInt8] { BandCrypto.md5(data) }

    private static func zeroTerminated(_ bytes: [UInt8], from start: Int, maxLength: Int) -> [UInt8] {
        let end = min(start + maxLength, bytes.count)
        var out: [UInt8] = []
        for i in start..<end {
            if bytes[i] == 0 { break }
            out.append(bytes[i])
        }
        return out
    }

    // MARK: - Прев'ю

    public func decodePreview() throws -> PreviewImage? {
        guard let offset = previewOffset else { return nil }
        return try PreviewImage(fileBytes: data, offset: offset)
    }
}

/// Розпаковане зображення у форматі RGBA8888 (без премноження альфи).
public struct PreviewImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public enum PixelFormat: UInt8, Sendable {
        case bgra8888 = 0
        case rgb565LE = 1
        case rgb565LEAlt = 4
        case rgb565BE = 7
        case palette256 = 16
    }

    public enum Compression: UInt8, Sendable {
        case none = 0
        case rleB = 4
        case rleA = 8
    }

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// Читає 12-байтовий заголовок прев'ю за `offset` і декодує дані після нього.
    public init(fileBytes bytes: [UInt8], offset: Int) throws {
        guard offset + 12 <= bytes.count else { throw BandError.invalidPreview("header out of range") }
        guard let format = PixelFormat(rawValue: bytes[offset]) else {
            throw BandError.invalidPreview("unknown pixel format \(bytes[offset])")
        }
        guard let compression = Compression(rawValue: bytes[offset + 1]) else {
            throw BandError.invalidPreview("unknown compression \(bytes[offset + 1])")
        }
        let width = Int(bytes.le16(at: offset + 4))
        let height = Int(bytes.le16(at: offset + 6))
        let size = Int(bytes.le32(at: offset + 8))
        let start = offset + 12
        guard width > 0, height > 0, width <= 4096, height <= 4096 else {
            throw BandError.invalidPreview("bad dimensions")
        }
        guard start + size <= bytes.count else { throw BandError.invalidPreview("data out of range") }

        var raw = Array(bytes[start..<(start + size)])
        switch compression {
        case .none: break
        case .rleA: raw = try RLE.decode(raw, variant: .a)
        case .rleB: raw = try RLE.decode(raw, variant: .b)
        }
        try self.init(raw: raw, format: format, width: width, height: height)
    }

    public init(raw: [UInt8], format: PixelFormat, width: Int, height: Int) throws {
        let count = width * height
        var out = [UInt8](repeating: 0, count: count * 4)

        func put565(_ i: Int, _ v: UInt16) {
            let r = UInt8((v >> 11) & 0x1F), g = UInt8((v >> 5) & 0x3F), b = UInt8(v & 0x1F)
            out[i * 4 + 0] = (r << 3) | (r >> 2)
            out[i * 4 + 1] = (g << 2) | (g >> 4)
            out[i * 4 + 2] = (b << 3) | (b >> 2)
            out[i * 4 + 3] = 0xFF
        }

        switch format {
        case .bgra8888:
            guard raw.count >= count * 4 else { throw BandError.invalidPreview("not enough pixel data") }
            for i in 0..<count {
                out[i * 4 + 0] = raw[i * 4 + 2]
                out[i * 4 + 1] = raw[i * 4 + 1]
                out[i * 4 + 2] = raw[i * 4 + 0]
                out[i * 4 + 3] = raw[i * 4 + 3]
            }
        case .rgb565LE, .rgb565LEAlt:
            guard raw.count >= count * 2 else { throw BandError.invalidPreview("not enough pixel data") }
            for i in 0..<count { put565(i, UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8)) }
        case .rgb565BE:
            guard raw.count >= count * 2 else { throw BandError.invalidPreview("not enough pixel data") }
            for i in 0..<count { put565(i, (UInt16(raw[i * 2]) << 8) | UInt16(raw[i * 2 + 1])) }
        case .palette256:
            let paletteSize = 256 * 4
            guard raw.count >= paletteSize + count else { throw BandError.invalidPreview("not enough pixel data") }
            for i in 0..<count {
                let p = Int(raw[paletteSize + i]) * 4
                out[i * 4 + 0] = raw[p + 2]
                out[i * 4 + 1] = raw[p + 1]
                out[i * 4 + 2] = raw[p + 0]
                out[i * 4 + 3] = raw[p + 3]
            }
        }
        self.init(width: width, height: height, rgba: out)
    }

    #if canImport(CoreGraphics)
    public func makeCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
    #endif
}

/// Розпаковування RLE у прев'ю.
///
/// Дані: `E0 21 A5 5A`, далі LE32 (молодші 4 біти — розмір елемента E, 0 означає 1;
/// решта — розмір розпакованих даних), далі блоки «байт керування + дані».
public enum RLE {
    public static let magic: [UInt8] = [0xE0, 0x21, 0xA5, 0x5A]

    public enum Variant: Sendable {
        /// Стиснення 8: старший біт 1 — повтор n+1 раз; 0 — n+1 елементів як є.
        case a
        /// Стиснення 4: старший біт 1 — n елементів як є; 0 — повтор n разів.
        case b
    }

    public static func decode(_ data: [UInt8], variant: Variant) throws -> [UInt8] {
        guard data.count >= 8, Array(data[0..<4]) == magic else {
            throw BandError.invalidPreview("bad RLE header")
        }
        let word = data.le32(at: 4)
        let elementSize = max(Int(word & 0x0F), 1)
        let total = Int(word >> 4)
        var out: [UInt8] = []
        out.reserveCapacity(total)
        var i = 8

        while i < data.count && out.count < total {
            let control = data[i]
            i += 1
            let high = control & 0x80 != 0
            let n = Int(control & 0x7F)

            let isRun: Bool
            let count: Int
            switch variant {
            case .a: isRun = high; count = n + 1
            case .b: isRun = !high; count = n
            }

            if isRun {
                guard i + elementSize <= data.count else { throw BandError.invalidPreview("truncated RLE") }
                let element = data[i..<(i + elementSize)]
                i += elementSize
                for _ in 0..<count { out.append(contentsOf: element) }
            } else {
                let length = count * elementSize
                guard i + length <= data.count else { throw BandError.invalidPreview("truncated RLE") }
                out.append(contentsOf: data[i..<(i + length)])
                i += length
            }
        }
        if out.count > total { out.removeLast(out.count - total) }
        return out
    }
}
