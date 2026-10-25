import Foundation
import UIKit

/// Прев'ю циферблата з файлу .face (порт XiaomiFWHelper.getWatchfacePreview і XiaomiBitmapUtils
/// із Gadgetbridge, AGPL-3.0).
enum FacePreview {
    // MARK: - Розбір .face

    static func image(fromFace data: Data) -> UIImage? {
        let b = [UInt8](data)
        guard b.count > 0x24 else { return nil }
        let offset = Int(le32(b, 0x20))
        guard offset != 0, offset + 12 <= b.count else { return nil }

        let format = Int(b[offset])
        let compression = Int(b[offset + 1])
        let width = Int(le16(b, offset + 4))
        let height = Int(le16(b, offset + 6))
        let size = Int(le32(b, offset + 8))
        let start = offset + 12
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              size > 0, start + size <= b.count else { return nil }
        var pixels = Array(b[start..<start + size])

        switch compression {
        case 0: break
        case 4: guard let d = decompressRLE(pixels, v2: true) else { return nil }; pixels = d
        case 8: guard let d = decompressRLE(pixels, v2: false) else { return nil }; pixels = d
        default: return nil
        }
        return decode(pixels, format: format, width: width, height: height)
    }

    private static func le16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    /// LVGL RLE: V1 (стиснення 8) і V2 (стиснення 4) відрізняються значенням біта 0x80.
    private static func decompressRLE(_ data: [UInt8], v2: Bool) -> [UInt8]? {
        guard data.count >= 8, data[0] == 0xE0, data[1] == 0x21, data[2] == 0xA5, data[3] == 0x5A else { return nil }
        let chunk = max(1, Int(data[4] & 0x0F))
        let outSize = Int((le32(data, 4) >> 4) & 0x0FFF_FFFF)
        var out = [UInt8]()
        out.reserveCapacity(outSize)
        var i = 8
        while i < data.count {
            let control = data[i]; i += 1
            let n = Int(control & 0x7F)
            let literal = v2 ? (control & 0x80) != 0 : (control & 0x80) == 0
            let count = v2 ? n : n + 1
            if literal {
                let len = chunk * count
                guard i + len <= data.count, out.count + len <= outSize else { return nil }
                out.append(contentsOf: data[i..<i + len]); i += len
            } else {
                guard i + chunk <= data.count, out.count + chunk * count <= outSize else { return nil }
                let piece = data[i..<i + chunk]; i += chunk
                for _ in 0..<count { out.append(contentsOf: piece) }
            }
        }
        return out
    }

    private static func decode(_ p: [UInt8], format: Int, width: Int, height: Int) -> UIImage? {
        let count = width * height
        var rgba = [UInt8](repeating: 0, count: count * 4)

        switch format {
        case 0: // ARGB8888, little-endian (байти B G R A)
            guard p.count >= count * 4 else { return nil }
            for k in 0..<count {
                rgba[k * 4] = p[k * 4 + 2]; rgba[k * 4 + 1] = p[k * 4 + 1]
                rgba[k * 4 + 2] = p[k * 4];  rgba[k * 4 + 3] = p[k * 4 + 3]
            }
        case 1, 4, 7: // RGB565 (7 — big-endian)
            guard p.count >= count * 2 else { return nil }
            for k in 0..<count {
                let c = format == 7
                    ? UInt16(p[k * 2]) << 8 | UInt16(p[k * 2 + 1])
                    : UInt16(p[k * 2]) | UInt16(p[k * 2 + 1]) << 8
                rgba[k * 4] = UInt8((c & 0xF800) >> 8)
                rgba[k * 4 + 1] = UInt8((c & 0x07E0) >> 3)
                rgba[k * 4 + 2] = UInt8((c & 0x001F) << 3)
                rgba[k * 4 + 3] = 255
            }
        case 16: // палітра 256 × ARGB8888 LE + індекси
            guard p.count >= 1024 + count else { return nil }
            for k in 0..<count {
                let e = Int(p[1024 + k]) * 4
                rgba[k * 4] = p[e + 2]; rgba[k * 4 + 1] = p[e + 1]
                rgba[k * 4 + 2] = p[e];  rgba[k * 4 + 3] = p[e + 3]
            }
        default:
            return nil
        }

        let space = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
