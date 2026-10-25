// SPDX-License-Identifier: MIT
//
// Мінімальний кодувальник і розбирач Protocol Buffers: varint, length-delimited, fixed32, fixed64.
// Схема повідомлень описана номерами полів у Commands.swift.

import Foundation

public enum ProtoValue: Equatable, Sendable {
    case varint(UInt64)
    case fixed64(UInt64)
    case lengthDelimited([UInt8])
    case fixed32(UInt32)
}

public struct ProtoField: Equatable, Sendable {
    public var number: Int
    public var value: ProtoValue
}

// MARK: - Запис

public struct ProtoWriter: Sendable {
    public private(set) var output: [UInt8] = []

    public init() {}

    static func encodeVarint(_ value: UInt64, into out: inout [UInt8]) {
        var v = value
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
    }

    private mutating func tag(_ field: Int, _ wireType: UInt64) {
        ProtoWriter.encodeVarint((UInt64(field) << 3) | wireType, into: &output)
    }

    public mutating func varint(_ field: Int, _ value: UInt64) {
        tag(field, 0)
        ProtoWriter.encodeVarint(value, into: &output)
    }

    public mutating func varint(_ field: Int, _ value: Int) {
        varint(field, UInt64(bitPattern: Int64(value)))
    }

    public mutating func bool(_ field: Int, _ value: Bool) {
        varint(field, value ? UInt64(1) : 0)
    }

    public mutating func bytes(_ field: Int, _ value: [UInt8]) {
        tag(field, 2)
        ProtoWriter.encodeVarint(UInt64(value.count), into: &output)
        output.append(contentsOf: value)
    }

    public mutating func string(_ field: Int, _ value: String) {
        bytes(field, Array(value.utf8))
    }

    public mutating func float(_ field: Int, _ value: Float) {
        tag(field, 5)
        output.appendLE32(value.bitPattern)
    }

    public mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        bytes(field, nested.output)
    }
}

// MARK: - Читання

public struct ProtoMessage: Equatable, Sendable {
    public let fields: [ProtoField]

    public init(fields: [ProtoField]) {
        self.fields = fields
    }

    public init(_ data: [UInt8]) throws {
        var fields: [ProtoField] = []
        var i = 0

        func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard i < data.count, shift < 64 else { throw BandError.malformedProtobuf }
                let b = data[i]
                i += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
        }

        while i < data.count {
            let key = try readVarint()
            let number = Int(key >> 3)
            guard number > 0 else { throw BandError.malformedProtobuf }
            switch key & 7 {
            case 0:
                fields.append(ProtoField(number: number, value: .varint(try readVarint())))
            case 1:
                guard i + 8 <= data.count else { throw BandError.malformedProtobuf }
                var v: UInt64 = 0
                for k in 0..<8 { v |= UInt64(data[i + k]) << (8 * UInt64(k)) }
                i += 8
                fields.append(ProtoField(number: number, value: .fixed64(v)))
            case 2:
                let len = try readVarint()
                guard len <= UInt64(data.count - i) else { throw BandError.malformedProtobuf }
                let end = i + Int(len)
                fields.append(ProtoField(number: number, value: .lengthDelimited(Array(data[i..<end]))))
                i = end
            case 5:
                guard i + 4 <= data.count else { throw BandError.malformedProtobuf }
                fields.append(ProtoField(number: number, value: .fixed32(data.le32(at: i))))
                i += 4
            default:
                throw BandError.malformedProtobuf // групи (3, 4) протокол не використовує
            }
        }
        self.fields = fields
    }

    public func first(_ number: Int) -> ProtoValue? {
        fields.first { $0.number == number }?.value
    }

    public func all(_ number: Int) -> [ProtoValue] {
        fields.filter { $0.number == number }.map(\.value)
    }

    public func varint(_ number: Int) -> UInt64? {
        if case .varint(let v)? = first(number) { return v }
        return nil
    }

    public func bool(_ number: Int) -> Bool? {
        varint(number).map { $0 != 0 }
    }

    public func bytes(_ number: Int) -> [UInt8]? {
        if case .lengthDelimited(let v)? = first(number) { return v }
        return nil
    }

    public func string(_ number: Int) -> String? {
        bytes(number).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    public func float(_ number: Int) -> Float? {
        if case .fixed32(let v)? = first(number) { return Float(bitPattern: v) }
        return nil
    }

    public func message(_ number: Int) -> ProtoMessage? {
        bytes(number).flatMap { try? ProtoMessage($0) }
    }

    public func messages(_ number: Int) -> [ProtoMessage] {
        all(number).compactMap {
            if case .lengthDelimited(let b) = $0 { return try? ProtoMessage(b) }
            return nil
        }
    }

    /// Вкладене повідомлення за шляхом номерів полів.
    public func message(at path: [Int]) -> ProtoMessage? {
        var current: ProtoMessage? = self
        for number in path { current = current?.message(number) }
        return current
    }

    /// Значення за шляхом: усі номери, крім останнього, — вкладені повідомлення.
    public func value(at path: [Int]) -> ProtoValue? {
        guard let last = path.last else { return nil }
        return message(at: Array(path.dropLast()))?.first(last)
    }

    public func varint(at path: [Int]) -> UInt64? {
        if case .varint(let v)? = value(at: path) { return v }
        return nil
    }

    public func bytes(at path: [Int]) -> [UInt8]? {
        if case .lengthDelimited(let v)? = value(at: path) { return v }
        return nil
    }

    public func string(at path: [Int]) -> String? {
        bytes(at: path).flatMap { String(bytes: $0, encoding: .utf8) }
    }
}
