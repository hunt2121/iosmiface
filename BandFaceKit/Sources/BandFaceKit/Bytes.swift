// SPDX-License-Identifier: MIT
// BandFaceKit — відкрита реалізація протоколу встановлення циферблатів на Xiaomi Smart Band 10.

import Foundation

/// Помилки бібліотеки.
public enum BandError: Error, Equatable, Sendable {
    case timeout
    case notConnected
    case bluetoothUnavailable
    case serviceNotFound
    case characteristicNotFound
    case sessionOpenFailed
    case sessionNotOpen
    case notAuthenticated
    case invalidAuthKey
    case authKeyMismatch
    case malformedResponse(String)
    case malformedProtobuf
    case installRejected(status: UInt64)
    case uploadRejected(status: UInt64)
    case invalidFaceFile(String)
    case invalidPreview(String)
    case authKeyNotFound
    case database(String)
    case cancelled
    case disconnected
}

extension Array where Element == UInt8 {
    @inlinable mutating func appendLE16(_ v: UInt16) {
        append(UInt8(truncatingIfNeeded: v))
        append(UInt8(truncatingIfNeeded: v >> 8))
    }

    @inlinable mutating func appendLE32(_ v: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: v >> UInt32(shift)))
        }
    }

    @inlinable func le16(at i: Int) -> UInt16 {
        UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }

    @inlinable func le32(at i: Int) -> UInt32 {
        UInt32(self[i])
            | (UInt32(self[i + 1]) << 8)
            | (UInt32(self[i + 2]) << 16)
            | (UInt32(self[i + 3]) << 24)
    }

    /// Шістнадцятковий рядок через пробіл, для журналу.
    public var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

public enum Hex {
    /// Розбирає шістнадцятковий рядок; пробіли, двокрапки і префікс 0x ігноруються.
    public static func decode(_ string: String) -> [UInt8]? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }
        s.removeAll { $0 == " " || $0 == ":" || $0 == "-" }
        guard s.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}

/// Порівняння без витоку часу.
@inlinable func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[i] ^ b[i] }
    return diff == 0
}

func randomBytes(_ count: Int) -> [UInt8] {
    // SystemRandomNumberGenerator на платформах Apple криптографічно стійкий.
    var rng = SystemRandomNumberGenerator()
    return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
}
