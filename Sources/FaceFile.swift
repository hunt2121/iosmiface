import Foundation

/// Розбір заголовка .face (формат Xiaomi, як у XiaomiFWHelper із Gadgetbridge).
struct FaceFile {
    let data: Data
    let id: String
    let name: String?

    enum ParseError: LocalizedError {
        case tooSmall, badMagic, noId, idNotNumeric(String)

        var errorDescription: String? {
            switch self {
            case .tooSmall: return "файл замалий для циферблата"
            case .badMagic: return "це не файл циферблата Xiaomi (немає заголовка 5A A5)"
            case .noId: return "у заголовку немає ідентифікатора циферблата"
            case .idNotNumeric(let s): return "ідентифікатор «\(s)» не є числом"
            }
        }
    }

    init(data: Data) throws {
        guard data.count > 0x80 else { throw ParseError.tooSmall }
        let b = [UInt8](data)
        guard b[0] == 0x5A, b[1] == 0xA5 else { throw ParseError.badMagic }

        func cString(at offset: Int) -> String? {
            guard offset < b.count else { return nil }
            var end = offset
            while end < b.count && b[end] != 0 { end += 1 }
            guard end > offset else { return nil }
            return String(bytes: b[offset..<end], encoding: .utf8)
        }

        guard let id = cString(at: 0x28) else { throw ParseError.noId }
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw ParseError.idNotNumeric(id)
        }

        // Якщо назва локалізована (0xFFFFFFFF за зміщенням 0x68), таблицю не розбираємо.
        let localized = b[0x68...0x6B].allSatisfy { $0 == 0xFF }
        self.name = localized ? nil : cString(at: 0x68)
        self.id = id
        self.data = data
    }
}
