// SPDX-License-Identifier: MIT
//
// Повідомлення «Команда» (protobuf) і конструктори команд, потрібних для встановлення циферблата.
//
// Команда:
//   1  varint   тип (1 — автентифікація, 2 — система, 4 — циферблати, 22 — завантаження даних)
//   2  varint   підтип
//   3  message  автентифікація
//   4  message  система
//   6  message  циферблат
//   24 message  завантаження даних
//   100 varint  статус відповіді (не завжди)

import Foundation

public struct Command: Sendable, Equatable {
    public enum Kind {
        public static let auth: UInt64 = 1
        public static let system: UInt64 = 2
        public static let watchface: UInt64 = 4
        public static let dataUpload: UInt64 = 22
    }

    public enum Field {
        public static let type = 1
        public static let subtype = 2
        public static let auth = 3
        public static let system = 4
        public static let watchface = 6
        public static let dataUpload = 24
        public static let status = 100
    }

    public let type: UInt64
    public let subtype: UInt64
    public let root: ProtoMessage

    public init(body: [UInt8]) throws {
        let message = try ProtoMessage(body)
        guard let type = message.varint(Field.type) else {
            throw BandError.malformedResponse("command without type")
        }
        self.type = type
        self.subtype = message.varint(Field.subtype) ?? 0
        self.root = message
    }

    public var status: UInt64? { root.varint(Field.status) }

    public func matches(_ type: UInt64, _ subtypes: UInt64...) -> Bool {
        self.type == type && subtypes.contains(subtype)
    }

    public var name: String { "\(type)/\(subtype)" }

    // MARK: - Конструктори

    static func build(_ type: UInt64, _ subtype: UInt64, _ fill: (inout ProtoWriter) -> Void = { _ in }) -> [UInt8] {
        var w = ProtoWriter()
        w.varint(Field.type, type)
        w.varint(Field.subtype, subtype)
        fill(&w)
        return w.output
    }

    /// Крок 1 автентифікації, 1/26: 3.30.1 = nonce телефону.
    public static func authPhoneNonce(_ nonce: [UInt8]) -> [UInt8] {
        build(Kind.auth, 26) { w in
            w.message(Field.auth) { a in
                a.message(30) { $0.bytes(1, nonce) }
            }
        }
    }

    /// Крок 3 автентифікації, 1/27: 3.32.1 = підтвердження, 3.32.2 = зашифрована інформація про телефон.
    public static func authConfirm(confirmation: [UInt8], encryptedPhoneInfo: [UInt8]) -> [UInt8] {
        build(Kind.auth, 27) { w in
            w.message(Field.auth) { a in
                a.message(32) { m in
                    m.bytes(1, confirmation)
                    m.bytes(2, encryptedPhoneInfo)
                }
            }
        }
    }

    /// Інформація про телефон (відкритий текст до шифрування CCM).
    /// Смисл полів 1, 2 і 4 не з'ясовано; значення перевірені на Band 10.
    public static func phoneInfo(model: String = "iPhone", region: String = "UK") -> [UInt8] {
        var w = ProtoWriter()
        w.varint(1, UInt64(0))
        w.float(2, 34.0)
        w.string(3, model)
        w.varint(4, UInt64(224))
        w.string(5, region)
        return w.output
    }

    /// 2/2 — інформація про пристрій.
    public static func deviceInfoRequest() -> [UInt8] { build(Kind.system, 2) }

    /// 2/1 — заряд батареї.
    public static func batteryRequest() -> [UInt8] { build(Kind.system, 1) }

    /// 4/0 — список циферблатів.
    public static func watchfaceListRequest() -> [UInt8] { build(Kind.watchface, 0) }

    /// 4/1 — активувати циферблат (6.2 = ID).
    public static func activateWatchface(id: String) -> [UInt8] {
        build(Kind.watchface, 1) { w in w.message(Field.watchface) { $0.string(2, id) } }
    }

    /// 4/2 — видалити циферблат (6.2 = ID).
    public static func deleteWatchface(id: String) -> [UInt8] {
        build(Kind.watchface, 2) { w in w.message(Field.watchface) { $0.string(2, id) } }
    }

    /// 4/4 — запит на встановлення (6.6.1 = ID, 6.6.2 = розмір).
    public static func installRequest(id: String, size: Int) -> [UInt8] {
        build(Kind.watchface, 4) { w in
            w.message(Field.watchface) { f in
                f.message(6) { m in
                    m.string(1, id)
                    m.varint(2, UInt64(size))
                }
            }
        }
    }

    /// Тип даних «циферблат» для запиту на завантаження.
    public static let uploadTypeWatchface: UInt64 = 16

    /// 22/0 — запит на завантаження (24.1.1 = тип, 24.1.2 = MD5, 24.1.3 = розмір).
    public static func uploadRequest(type: UInt64 = uploadTypeWatchface, md5: [UInt8], size: Int) -> [UInt8] {
        build(Kind.dataUpload, 0) { w in
            w.message(Field.dataUpload) { d in
                d.message(1) { m in
                    m.varint(1, type)
                    m.bytes(2, md5)
                    m.varint(3, UInt64(size))
                }
            }
        }
    }
}

// MARK: - Розбір відповідей

public struct DeviceInfo: Sendable, Equatable {
    public var serialNumber: String?
    public var firmwareVersion: String?
    public var model: String?

    public init(command: Command) {
        serialNumber = command.root.string(at: [4, 3, 1])
        firmwareVersion = command.root.string(at: [4, 3, 2])
        model = command.root.string(at: [4, 3, 4])
    }
}

public struct WatchfaceEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var isActive: Bool
    public var canDelete: Bool

    init?(message: ProtoMessage) {
        guard let id = message.string(1) else { return nil }
        self.id = id
        name = message.string(2) ?? ""
        isActive = message.bool(3) ?? false
        canDelete = message.bool(4) ?? false
    }

    /// Розбирає відповідь 4/0 (6.1.1 — повторюване повідомлення).
    public static func list(from command: Command) -> [WatchfaceEntry] {
        // Основний варіант: 6 → 1 (список) → 1 (повторювані записи).
        if let container = command.root.message(at: [6, 1]) {
            let entries = container.messages(1).compactMap(WatchfaceEntry.init(message:))
            if !entries.isEmpty { return entries }
        }
        // Запасний варіант: записи безпосередньо в 6.1.
        return command.root.message(6)?.messages(1).compactMap(WatchfaceEntry.init(message:)) ?? []
    }
}

public struct UploadResponse: Sendable, Equatable {
    /// 24.2.2: 0 — браслет готовий приймати.
    public var status: UInt64
    /// 24.2.4: позиція у файлі, з якої продовжити.
    public var resumePosition: Int
    /// 24.2.5: розмір шматка (Band 10: 4096).
    public var chunkSize: Int

    public init(command: Command) {
        status = command.root.varint(at: [24, 2, 2]) ?? 0
        resumePosition = Int(command.root.varint(at: [24, 2, 4]) ?? 0)
        chunkSize = Int(command.root.varint(at: [24, 2, 5]) ?? 4096)
    }
}
