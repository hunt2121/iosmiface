import Foundation

/// Мінімальний protobuf-кодер/декодер (лише те, що потрібно протоколу Xiaomi).
/// Схема повідомлень: xiaomi.proto з Gadgetbridge (AGPL-3.0).
struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ value: UInt64) {
        var x = value
        while x >= 0x80 {
            data.append(UInt8(x & 0x7F) | 0x80)
            x >>= 7
        }
        data.append(UInt8(x))
    }

    private mutating func tag(_ field: Int, _ wire: Int) {
        varint(UInt64(field << 3 | wire))
    }

    mutating func uint(_ field: Int, _ value: UInt32) {
        tag(field, 0)
        varint(UInt64(value))
    }

    mutating func float32(_ field: Int, _ value: Float) {
        tag(field, 5)
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    mutating func message(_ field: Int, _ inner: ProtoWriter) {
        bytes(field, inner.data)
    }
}

struct ProtoField {
    let number: Int
    let wire: Int
    let varint: UInt64
    let payload: Data
}

struct ProtoMessage {
    let fields: [ProtoField]

    /// Повертає nil, якщо дані не є коректним protobuf.
    init?(_ data: Data) {
        let bytes = [UInt8](data)
        var i = 0
        var out: [ProtoField] = []

        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while i < bytes.count && shift < 64 {
                let b = bytes[i]
                i += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        while i < bytes.count {
            guard let key = readVarint() else { return nil }
            let number = Int(key >> 3)
            let wire = Int(key & 7)
            switch wire {
            case 0:
                guard let v = readVarint() else { return nil }
                out.append(ProtoField(number: number, wire: wire, varint: v, payload: Data()))
            case 1:
                guard i + 8 <= bytes.count else { return nil }
                out.append(ProtoField(number: number, wire: wire, varint: 0, payload: Data(bytes[i..<i + 8])))
                i += 8
            case 2:
                guard let len = readVarint(), len <= UInt64(bytes.count - i) else { return nil }
                let n = Int(len)
                out.append(ProtoField(number: number, wire: wire, varint: 0, payload: Data(bytes[i..<i + n])))
                i += n
            case 5:
                guard i + 4 <= bytes.count else { return nil }
                out.append(ProtoField(number: number, wire: wire, varint: 0, payload: Data(bytes[i..<i + 4])))
                i += 4
            default:
                return nil
            }
        }
        fields = out
    }

    func uint(_ number: Int) -> UInt64? {
        fields.first { $0.number == number && $0.wire == 0 }?.varint
    }

    func data(_ number: Int) -> Data? {
        fields.first { $0.number == number && $0.wire == 2 }?.payload
    }

    func string(_ number: Int) -> String? {
        data(number).flatMap { String(data: $0, encoding: .utf8) }
    }

    func message(_ number: Int) -> ProtoMessage? {
        data(number).flatMap { ProtoMessage($0) }
    }
}
