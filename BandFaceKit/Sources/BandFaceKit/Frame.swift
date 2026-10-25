// SPDX-License-Identifier: MIT

/// Тип кадру (молодші 4 біти байта 2).
public enum FrameType: UInt8, Sendable {
    case ack = 1
    case session = 2
    case data = 3
}

/// Кадр транспортного рівня: A5 A5 | тип | номер | довжина LE16 | CRC-16 LE16 | навантаження.
public struct Frame: Equatable, Sendable {
    public static let preamble: [UInt8] = [0xA5, 0xA5]
    public static let headerLength = 8
    /// Верхня межа довжини навантаження, яку приймає розбирач (захист від сміття в буфері).
    public static let maxPayloadLength = 0xFC00

    public var type: FrameType
    public var sequence: UInt8
    public var payload: [UInt8]
    /// Старші 4 біти байта типу (прапорці; телефон надсилає 0).
    public var flags: UInt8 = 0

    public init(type: FrameType, sequence: UInt8, payload: [UInt8] = []) {
        self.type = type
        self.sequence = sequence
        self.payload = payload
    }

    public static func ack(_ sequence: UInt8) -> Frame {
        Frame(type: .ack, sequence: sequence)
    }

    public func encoded() -> [UInt8] {
        var out = Frame.preamble
        out.reserveCapacity(Frame.headerLength + payload.count)
        out.append(type.rawValue) // прапорці у старших бітах = 0
        out.append(sequence)
        out.appendLE16(UInt16(payload.count))
        out.appendLE16(payload.isEmpty ? 0 : Checksum.crc16ARC(payload))
        out.append(contentsOf: payload)
        return out
    }
}

/// Накопичує байти зі сповіщень BLE і виділяє з них цілі кадри.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func reset() { buffer.removeAll() }

    /// Дописує байти і повертає всі кадри, які вдалося зібрати.
    public mutating func append(_ bytes: [UInt8]) -> [Frame] {
        buffer.append(contentsOf: bytes)
        var frames: [Frame] = []

        while true {
            guard let start = preambleIndex() else {
                // Зберігаємо останній байт: він може бути першою половиною преамбули.
                if buffer.last == 0xA5 { buffer = [0xA5] } else { buffer.removeAll() }
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= Frame.headerLength else { break }

            let length = Int(buffer.le16(at: 4))
            if length > Frame.maxPayloadLength {
                buffer.removeFirst(1)
                continue
            }
            guard buffer.count >= Frame.headerLength + length else { break }

            let payload = Array(buffer[Frame.headerLength..<(Frame.headerLength + length)])
            let crc = buffer.le16(at: 6)
            let expected: UInt16 = payload.isEmpty ? 0 : Checksum.crc16ARC(payload)
            guard crc == expected else {
                // Невірна сума: шукаємо наступну преамбулу після цієї.
                buffer.removeFirst(1)
                continue
            }

            let typeNibble = buffer[2] & 0x0F
            let flagsNibble = buffer[2] >> 4
            let sequence = buffer[3]
            buffer.removeFirst(Frame.headerLength + length)

            if let type = FrameType(rawValue: typeNibble) {
                var frame = Frame(type: type, sequence: sequence, payload: payload)
                frame.flags = flagsNibble
                frames.append(frame)
            }
        }
        return frames
    }

    private func preambleIndex() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for i in 0..<(buffer.count - 1) where buffer[i] == 0xA5 && buffer[i + 1] == 0xA5 {
            return i
        }
        return nil
    }
}

/// Канал у кадрі даних (молодші 4 біти першого байта).
public enum DataChannel: UInt8, Sendable {
    case protobuf = 1
    case file = 2
}

/// Код операції у кадрі даних.
public enum DataOpcode: UInt8, Sendable {
    case plain = 1
    case encrypted = 2
}

/// Навантаження кадру даних: канал, код операції, тіло.
public struct DataPacket: Equatable, Sendable {
    public var channel: UInt8
    public var opcode: UInt8
    public var body: [UInt8]

    public init(channel: DataChannel, opcode: DataOpcode, body: [UInt8]) {
        self.channel = channel.rawValue
        self.opcode = opcode.rawValue
        self.body = body
    }

    public init?(payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        channel = payload[0] & 0x0F
        opcode = payload[1]
        body = Array(payload[2...])
    }

    public var payload: [UInt8] { [channel, opcode] + body }
}
