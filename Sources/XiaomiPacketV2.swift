import Foundation

/// Кадри Xiaomi "SPP V2" поверх BLE (характеристики 0x5E/0x5F).
/// Порт XiaomiSppPacketV2 із Gadgetbridge (AGPL-3.0).
enum XiaomiChannel {
    case protobuf       // сирий канал 1
    case data           // сирий канал 2
    case activity       // сирий канал 5
    case unknown

    var raw: UInt8 {
        switch self {
        case .protobuf: return 1
        case .data: return 2
        case .activity: return 5
        case .unknown: return 0xF
        }
    }

    static func from(raw: UInt8) -> XiaomiChannel {
        switch raw {
        case 1: return .protobuf
        case 2: return .data
        case 5: return .activity
        default: return .unknown
        }
    }
}

enum XiaomiPacketV2 {
    static let preamble: [UInt8] = [0xA5, 0xA5]
    static let typeAck: UInt8 = 1
    static let typeSessionConfig: UInt8 = 2
    static let typeData: UInt8 = 3

    static let opPlaintext: UInt8 = 1
    static let opEncrypted: UInt8 = 2

    enum Parsed {
        case ack(seq: UInt8)
        case sessionConfig(seq: UInt8, opcode: UInt8)
        case data(seq: UInt8, channel: XiaomiChannel, opcode: UInt8, payload: Data)
    }

    enum ParseResult {
        case incomplete
        case invalid
        case complete(packet: Parsed?, size: Int)
    }

    /// CRC-16/ARC (poly 0x8005, reflected), як у Gadgetbridge.
    static func checksum(_ payload: Data) -> UInt16 {
        var crc: UInt32 = 0
        for b in payload {
            for j in 0..<8 {
                crc <<= 1
                if (((crc >> 16) & 1) ^ ((UInt32(b) >> UInt32(j)) & 1)) == 1 {
                    crc ^= 0x8005
                }
            }
        }
        var low = UInt16(truncatingIfNeeded: crc)
        var reversed: UInt16 = 0
        for _ in 0..<16 {
            reversed = (reversed << 1) | (low & 1)
            low >>= 1
        }
        return reversed
    }

    private static func frame(type: UInt8, seq: UInt8, payload: Data) -> Data {
        var out = Data(preamble)
        out.append(type & 0xF)
        out.append(seq)
        let len = UInt16(payload.count)
        out.append(UInt8(len & 0xFF)); out.append(UInt8(len >> 8))
        let crc = checksum(payload)
        out.append(UInt8(crc & 0xFF)); out.append(UInt8(crc >> 8))
        out.append(payload)
        return out
    }

    static func ack(seq: UInt8) -> Data {
        frame(type: typeAck, seq: seq, payload: Data())
    }

    /// START_SESSION_REQUEST із такими ж параметрами, як у офіційного застосунку.
    static func startSessionRequest() -> Data {
        let payload: [UInt8] = [
            0x01,                               // opcode: start session request
            0x01, 0x03, 0x00, 0x01, 0x00, 0x00, // version 1.0.0
            0x02, 0x02, 0x00, 0x00, 0xFC,       // max packet size 0xFC00
            0x03, 0x02, 0x00, 0x20, 0x00,       // tx window 32
            0x04, 0x02, 0x00, 0x10, 0x27        // send timeout 10000 ms
        ]
        return frame(type: typeSessionConfig, seq: 0, payload: Data(payload))
    }

    static func dataPacket(seq: UInt8, channel: XiaomiChannel, opcode: UInt8, payload: Data) -> Data {
        var body = Data([channel.raw & 0xF, opcode])
        body.append(payload)
        return frame(type: typeData, seq: seq, payload: body)
    }

    /// Розбирає один кадр з початку буфера.
    static func parse(_ buf: [UInt8]) -> ParseResult {
        if buf.count < 8 { return .incomplete }
        guard buf[0] == preamble[0], buf[1] == preamble[1] else { return .invalid }

        let type = buf[2] & 0xF
        let seq = buf[3]
        let payloadLen = Int(buf[4]) | Int(buf[5]) << 8
        let givenCRC = UInt16(buf[6]) | UInt16(buf[7]) << 8
        let size = 8 + payloadLen
        if buf.count < size { return .incomplete }

        let payload = Data(buf[8..<size])
        guard checksum(payload) == givenCRC else { return .invalid }

        switch type {
        case typeAck:
            return .complete(packet: .ack(seq: seq), size: size)
        case typeSessionConfig:
            guard let op = payload.first else { return .complete(packet: nil, size: size) }
            return .complete(packet: .sessionConfig(seq: seq, opcode: op), size: size)
        case typeData:
            guard payload.count >= 2 else { return .complete(packet: nil, size: size) }
            let channel = XiaomiChannel.from(raw: payload[payload.startIndex] & 0xF)
            let opcode = payload[payload.startIndex + 1]
            let body = Data(payload.dropFirst(2))
            return .complete(packet: .data(seq: seq, channel: channel, opcode: opcode, payload: body), size: size)
        default:
            return .complete(packet: nil, size: size)
        }
    }
}
