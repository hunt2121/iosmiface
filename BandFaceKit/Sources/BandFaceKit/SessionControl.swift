// SPDX-License-Identifier: MIT

/// Навантаження кадру керування сесією (тип 2): код + параметри TLV
/// «ключ (1 байт), довжина (LE16), значення».
public struct SessionControl: Equatable, Sendable {
    public enum Code: UInt8, Sendable {
        case openRequest = 1
        case openResponse = 2
        case closeRequest = 3
        case closeResponse = 4
    }

    public enum ParameterKey: UInt8, Sendable {
        case version = 1
        case maxFrameSize = 2
        case window = 3
        case timeoutMs = 4
    }

    public var code: UInt8
    public var parameters: [(key: UInt8, value: [UInt8])]

    public init(code: Code, parameters: [(key: UInt8, value: [UInt8])] = []) {
        self.code = code.rawValue
        self.parameters = parameters
    }

    public init?(payload: [UInt8]) {
        guard let first = payload.first else { return nil }
        code = first
        var params: [(key: UInt8, value: [UInt8])] = []
        var i = 1
        while i + 3 <= payload.count {
            let key = payload[i]
            let len = Int(payload.le16(at: i + 1))
            i += 3
            guard i + len <= payload.count else { return nil }
            params.append((key: key, value: Array(payload[i..<(i + len)])))
            i += len
        }
        parameters = params
    }

    public var payload: [UInt8] {
        var out: [UInt8] = [code]
        for p in parameters {
            out.append(p.key)
            out.appendLE16(UInt16(p.value.count))
            out.append(contentsOf: p.value)
        }
        return out
    }

    public func parameter(_ key: ParameterKey) -> [UInt8]? {
        parameters.first { $0.key == key.rawValue }?.value
    }

    /// Версія з параметра 1 у вигляді «a.b.c».
    public var version: String? {
        guard let v = parameter(.version), v.count == 3 else { return nil }
        return "\(v[0]).\(v[1]).\(v[2])"
    }

    public var maxFrameSize: Int? {
        guard let v = parameter(.maxFrameSize), v.count == 2 else { return nil }
        return Int(v.le16(at: 0))
    }

    public var window: Int? {
        guard let v = parameter(.window), v.count == 2 else { return nil }
        return Int(v.le16(at: 0))
    }

    public var timeoutMs: Int? {
        guard let v = parameter(.timeoutMs), v.count == 2 else { return nil }
        return Int(v.le16(at: 0))
    }

    /// Запит на відкриття, що працює з Band 10:
    /// версія 1.0.0, макс. кадр 0xFC00, вікно 32, тайм-аут 10000 мс (22 байти).
    public static let openRequest = SessionControl(code: .openRequest, parameters: [
        (ParameterKey.version.rawValue, [0x01, 0x00, 0x00]),
        (ParameterKey.maxFrameSize.rawValue, [0x00, 0xFC]),
        (ParameterKey.window.rawValue, [0x20, 0x00]),
        (ParameterKey.timeoutMs.rawValue, [0x10, 0x27]),
    ])

    public static let closeRequest = SessionControl(code: .closeRequest)

    public static func == (lhs: SessionControl, rhs: SessionControl) -> Bool {
        lhs.payload == rhs.payload
    }
}
