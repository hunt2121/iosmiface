// SPDX-License-Identifier: MIT
// Тест-вектори згенеровано незалежною реалізацією Tools/generate_vectors.py.

import XCTest
@testable import BandFaceKit

private func hex(_ s: String) -> [UInt8] { Hex.decode(s)! }

final class ChecksumTests: XCTestCase {
    func testCRC16ARC() {
        XCTAssertEqual(Checksum.crc16ARC(Array("123456789".utf8)), 0xBB3D)
        XCTAssertEqual(Checksum.crc16ARC([]), 0)
    }

    func testCRC32() {
        XCTAssertEqual(Checksum.crc32(Array("123456789".utf8)), 0xCBF4_3926)
    }
}

final class FrameTests: XCTestCase {
    func testSessionOpenFrame() {
        let frame = Frame(type: .session, sequence: 0, payload: SessionControl.openRequest.payload)
        XCTAssertEqual(SessionControl.openRequest.payload.count, 22)
        XCTAssertEqual(frame.encoded(), hex("a5a5020016001d4d0101030001000002020000fc03020020000402001027"))
    }

    func testCloseAndAckFrames() {
        XCTAssertEqual(Frame(type: .session, sequence: 0, payload: SessionControl.closeRequest.payload).encoded(),
                       hex("a5a502000100400103"))
        XCTAssertEqual(Frame.ack(7).encoded(), hex("a5a5010700000000"))
    }

    func testParserSplitsMergesAndResyncs() {
        let a = Frame(type: .data, sequence: 1, payload: [1, 1, 8, 2, 16, 2]).encoded()
        let b = Frame.ack(9).encoded()
        var corrupted = Frame(type: .data, sequence: 2, payload: [1, 1, 0xAA]).encoded()
        corrupted[corrupted.count - 1] ^= 0xFF // невірна CRC

        var parser = FrameParser()
        let stream = [0x00, 0x13] + a + corrupted + b
        var frames: [Frame] = []
        // По 3 байти, як дрібні сповіщення BLE.
        var i = 0
        while i < stream.count {
            frames += parser.append(Array(stream[i..<min(i + 3, stream.count)]))
            i += 3
        }
        XCTAssertEqual(frames, [
            Frame(type: .data, sequence: 1, payload: [1, 1, 8, 2, 16, 2]),
            Frame.ack(9),
        ])
    }

    func testSessionControlParsing() {
        let response = SessionControl(code: .openResponse, parameters: [
            (key: 1, value: [3, 0, 65]),
            (key: 2, value: [0x00, 0x80]),
        ])
        let parsed = SessionControl(payload: response.payload)!
        XCTAssertEqual(parsed.code, 2)
        XCTAssertEqual(parsed.parameters.map(\.key), [1, 2])
        XCTAssertEqual(parsed.parameters.map(\.value), [[3, 0, 65], [0x00, 0x80]])
    }
}

final class ProtobufTests: XCTestCase {
    func testCommandEncodings() {
        XCTAssertEqual(Command.authPhoneNonce(Array(0x10...0x1F)),
                       hex("0801101a1a15f201120a10101112131415161718191a1b1c1d1e1f"))
        XCTAssertEqual(Command.deviceInfoRequest(), hex("08021002"))
        XCTAssertEqual(Command.installRequest(id: "266235369", size: 103_424),
                       hex("080410043211320f0a093236363233353336391080a806"))
        XCTAssertEqual(Command.uploadRequest(md5: BandCrypto.md5(Array("hello".utf8)), size: 5),
                       hex("08161000c201180a16081012105d41402abc4b2a76b9719d911017c5921805"))
        XCTAssertEqual(Command.phoneInfo(), hex("080015000008421a066950686f6e6520e0012a02554b"))
    }

    func testReaderPaths() throws {
        var w = ProtoWriter()
        w.varint(1, UInt64(2))
        w.varint(2, UInt64(1))
        w.message(4) { s in s.message(2) { b in b.message(1) { $0.varint(1, UInt64(52)) } } }
        w.varint(100, UInt64(0))
        let command = try Command(body: w.output)
        XCTAssertEqual(command.name, "2/1")
        XCTAssertEqual(command.root.varint(at: [4, 2, 1, 1]), 52)
        XCTAssertEqual(command.status, 0)
    }

    func testWatchfaceList() throws {
        var w = ProtoWriter()
        w.varint(1, UInt64(4))
        w.varint(2, UInt64(0))
        w.message(6) { f in
            f.message(1) { list in
                list.message(1) { $0.string(1, "111"); $0.string(2, "A"); $0.varint(3, UInt64(1)); $0.varint(4, UInt64(0)) }
                list.message(1) { $0.string(1, "222"); $0.string(2, "B"); $0.varint(3, UInt64(0)); $0.varint(4, UInt64(1)) }
            }
        }
        let entries = WatchfaceEntry.list(from: try Command(body: w.output))
        XCTAssertEqual(entries.map(\.id), ["111", "222"])
        XCTAssertEqual(entries[1].canDelete, true)
        XCTAssertEqual(entries[0].isActive, true)
    }

    func testMalformedIsRejected() {
        XCTAssertThrowsError(try ProtoMessage([0x0A, 0x05, 0x01]))
        XCTAssertThrowsError(try ProtoMessage([0x08, 0xFF]))
    }
}

final class CryptoTests: XCTestCase {
    let authKey = Array<UInt8>(0x00...0x0F)
    let phoneNonce = Array<UInt8>(0x10...0x1F)
    let bandNonce = Array<UInt8>(0x20...0x2F)

    func testKeyDerivation() {
        let keys = SessionKeys(authKey: authKey, phoneNonce: phoneNonce, bandNonce: bandNonce)
        XCTAssertEqual(keys.decryptionKey, hex("d738074e6570abb50d001db70f497a37"))
        XCTAssertEqual(keys.encryptionKey, hex("923e295e02aecb7619a8e1b9f574c988"))
        XCTAssertEqual(keys.encryptionNonce, hex("23869a15"))
        XCTAssertEqual(keys.expectedBandHMAC(phoneNonce: phoneNonce, bandNonce: bandNonce),
                       hex("17aa8eecac21d9d71cba6ea653d126d77abc2f4d0357f1cce01d433d40e42235"))
        XCTAssertEqual(keys.phoneConfirmation(phoneNonce: phoneNonce, bandNonce: bandNonce),
                       hex("7e6e4d786282c1af4441b2ed315da93c8ae2c820a72df584d62315d73913a9dc"))
    }

    func testPhoneInfoCCM() {
        let keys = SessionKeys(authKey: authKey, phoneNonce: phoneNonce, bandNonce: bandNonce)
        XCTAssertEqual(keys.encryptPhoneInfo(Command.phoneInfo()),
                       hex("806dad1c238704c043431e48e043c1b650bf3ae4bdfb7cb2cfc2"))
    }

    func testCommandCTR() {
        let keys = SessionKeys(authKey: authKey, phoneNonce: phoneNonce, bandNonce: bandNonce)
        XCTAssertEqual(keys.encryptCommand(hex("08021002")), hex("b7e6503e"))
        // 40 байтів — перевіряє інкремент лічильника між блоками.
        let cipher = hex("050b16c236898af83e1fc7de57b5f584774d53576f9aac8ad27f4f799215ef5b170fb6f62adc0a25")
        XCTAssertEqual(keys.decryptCommand(cipher), Array(0..<40))
    }

    func testCounterIncrementCarries() {
        var block = [UInt8](repeating: 0xFF, count: 16)
        BandCrypto.incrementBigEndian(&block)
        XCTAssertEqual(block, [UInt8](repeating: 0, count: 16))
        var b2: [UInt8] = [UInt8](repeating: 0, count: 14) + [0x00, 0xFF]
        BandCrypto.incrementBigEndian(&b2)
        XCTAssertEqual(b2.suffix(2), [0x01, 0x00])
    }
}

final class FileTransferTests: XCTestCase {
    let file: [UInt8] = (0..<10_000).map { UInt8(truncatingIfNeeded: $0 * 7) }

    func testStreamAndParts() {
        let md5 = BandCrypto.md5(file)
        XCTAssertEqual(md5, hex("06a474d076d55fe5bdaafbb83017ffca"))
        let stream = FileTransfer.stream(file: file, md5: md5)
        XCTAssertEqual(stream.count, 10_026)
        XCTAssertEqual(Array(stream.suffix(4)), hex("608c8607"))

        let parts = FileTransfer.parts(stream: stream, chunkSize: 4096)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(Array(parts[0].prefix(12)), hex("03000100001006a474d076d5"))
        XCTAssertTrue(parts.dropLast().allSatisfy { $0.count == 4096 })
        XCTAssertEqual(parts.last?.count, 1846)
        XCTAssertEqual(parts.last?[2], 3)
        XCTAssertEqual(parts.flatMap { $0.dropFirst(4) }, stream)
    }

    func testResume() {
        let stream = FileTransfer.stream(file: file, md5: BandCrypto.md5(file), resumePosition: 5000)
        XCTAssertEqual(stream.count, 5026)
        XCTAssertEqual(Array(stream.suffix(4)), hex("99445ab8"))
    }
}

final class FaceFileTests: XCTestCase {
    static func makeFace(id: String = "266235369", name: String? = "Test", preview: [UInt8]? = nil) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x5A
        bytes[1] = 0xA5
        for (i, b) in id.utf8.enumerated() { bytes[0x28 + i] = b }
        if let name {
            for (i, b) in name.utf8.enumerated() { bytes[0x68 + i] = b }
        } else {
            for i in 0..<4 { bytes[0x68 + i] = 0xFF }
        }
        if let preview {
            let offset = bytes.count
            bytes[0x20] = UInt8(offset & 0xFF)
            bytes[0x21] = UInt8(offset >> 8)
            bytes += preview
        }
        return bytes
    }

    func testHeader() throws {
        let face = try FaceFile(bytes: Self.makeFace())
        XCTAssertEqual(face.id, "266235369")
        XCTAssertEqual(face.name, "Test")
        XCTAssertNil(face.previewOffset)

        let localized = try FaceFile(bytes: Self.makeFace(name: nil))
        XCTAssertNil(localized.name)

        XCTAssertThrowsError(try FaceFile(bytes: [0x00, 0x00] + [UInt8](repeating: 0, count: 0x100)))
    }

    func testRLEVariants() throws {
        let raw = hex("0102010201020102010203040506")
        XCTAssertEqual(try RLE.decode(hex("e021a55ae20000008401020103040506"), variant: .a), raw)
        XCTAssertEqual(try RLE.decode(hex("e021a55ae20000000501028203040506"), variant: .b), raw)
    }

    func testPreviewRGB565WithRLE() throws {
        // 7 пікселів × 1 рядок, RGB565 LE, RLE варіант A.
        let rle = hex("e021a55ae20000008401020103040506")
        var header: [UInt8] = [1, 8, 0, 0]
        header.appendLE16(7)
        header.appendLE16(1)
        header.appendLE32(UInt32(rle.count))
        let face = try FaceFile(bytes: Self.makeFace(preview: header + rle))
        let image = try XCTUnwrap(try face.decodePreview())
        XCTAssertEqual(image.width, 7)
        XCTAssertEqual(image.rgba.count, 7 * 4)
        XCTAssertEqual(image.rgba[3], 0xFF)
    }
}

/// Пристрій для архіву NSKeyedArchiver (клас NSCoding не може бути локальним).
@objc(BandFaceKitTestDevice)
private final class Device: NSObject, NSCoding {
    func encode(with coder: NSCoder) {
        coder.encode("Xiaomi Smart Band 10 ABCD  \0\0", forKey: "name")
        coder.encode("0x00112233445566778899AABBCCDDEEFF", forKey: "encryptKey")
        coder.encode("AA:BB:CC:DD:EE:FF", forKey: "mac")
    }
    override init() {}
    required init?(coder: NSCoder) {}
}

final class AuthKeyStoreTests: XCTestCase {
    func testKeyedArchiveParsing() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode([Device()], forKey: "root")
        archiver.finishEncoding()

        let credentials = try AuthKeyStore.credentials(fromKeyedArchive: archiver.encodedData)
        XCTAssertEqual(credentials.count, 1)
        XCTAssertEqual(credentials[0].name, "Xiaomi Smart Band 10 ABCD")
        XCTAssertEqual(credentials[0].mac, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(credentials[0].authKeyHex, "00112233445566778899aabbccddeeff")
    }
}

final class AuthKeyScannerTests: XCTestCase {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFindsKeyInJSON() throws {
        let folder = try makeFolder()
        let nested = folder.appendingPathComponent("cn/devices", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let json = #"{"list":[{"name":"Xiaomi Smart Band 10","mac":"AA:BB:CC:DD:EE:FF","encryptKey":"00112233445566778899aabbccddeeff"}]}"#
        try json.write(to: nested.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)

        let scan = AuthKeyScanner.scan(folder: folder)
        XCTAssertEqual(scan.credentials.count, 1)
        XCTAssertEqual(scan.credentials.first?.authKeyHex, "00112233445566778899aabbccddeeff")
        XCTAssertEqual(scan.credentials.first?.name, "Xiaomi Smart Band 10")
        XCTAssertEqual(scan.credentials.first?.mac, "AA:BB:CC:DD:EE:FF")
    }

    func testFindsKeyInLogText() throws {
        let folder = try makeFolder()
        let log = "12:00:01 bind ok {\\\"auth_key\\\":\\\"ffeeddccbbaa99887766554433221100\\\"} done\n"
        try log.write(to: folder.appendingPathComponent("device.log"), atomically: true, encoding: .utf8)

        let scan = AuthKeyScanner.scan(folder: folder)
        XCTAssertEqual(scan.credentials.map(\.authKeyHex), ["ffeeddccbbaa99887766554433221100"])
    }

    func testFindsKeyInPlistWithoutExtension() throws {
        let folder = try makeFolder()
        let object: [String: Any] = ["devices": [["name": "Band", "encryptKey": "0x00112233445566778899AABBCCDDEEFF"]]]
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        try data.write(to: folder.appendingPathComponent("cache"))

        let scan = AuthKeyScanner.scan(folder: folder)
        XCTAssertEqual(scan.credentials.first?.authKeyHex, "00112233445566778899aabbccddeeff")
    }

    func testFindsKeyInArbitrarySQLiteTable() throws {
        let folder = try makeFolder()
        let path = folder.appendingPathComponent("any.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE devices (name TEXT, mac TEXT, encrypt_key TEXT);
        INSERT INTO devices VALUES ('Xiaomi Smart Band 10', '11:22:33:44:55:66', '00112233445566778899aabbccddeeff');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let scan = AuthKeyScanner.scan(folder: folder)
        XCTAssertEqual(scan.report.databasesScanned, 1)
        XCTAssertEqual(scan.credentials.count, 1)
        XCTAssertEqual(scan.credentials.first?.name, "Xiaomi Smart Band 10")
        XCTAssertEqual(scan.credentials.first?.mac, "11:22:33:44:55:66")
    }

    func testIgnoresUnrelatedFiles() throws {
        let folder = try makeFolder()
        try "just some text, key = 1234".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let scan = AuthKeyScanner.scan(folder: folder)
        XCTAssertTrue(scan.credentials.isEmpty)
        XCTAssertEqual(scan.report.filesScanned, 1)
    }
}
