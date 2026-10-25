// SPDX-License-Identifier: MIT
//
// Криптографія протоколу. Блоковий шифр AES-128 береться із системної CommonCrypto,
// HMAC-SHA256 і MD5 — з CryptoKit. Режими CTR і CCM зібрано поверх одного блоку AES,
// бо CryptoKit їх не надає.

import CommonCrypto
import CryptoKit
import Foundation

public enum BandCrypto {
    // MARK: AES

    /// Шифрує один 16-байтовий блок AES-128 (ECB без доповнення).
    static func aesEncryptBlock(key: [UInt8], block: [UInt8]) -> [UInt8] {
        precondition(key.count == kCCKeySizeAES128 && block.count == kCCBlockSizeAES128)
        var out = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode),
            key, key.count,
            nil,
            block, block.count,
            &out, out.count,
            &moved
        )
        precondition(status == CCCryptorStatus(kCCSuccess) && moved == kCCBlockSizeAES128, "AES failed: \(status)")
        return out
    }

    /// AES-128-CTR. Лічильник — увесь 16-байтовий блок як ціле big-endian.
    /// Шифрування і дешифрування — та сама операція.
    public static func aesCTR(key: [UInt8], iv: [UInt8], data: [UInt8]) -> [UInt8] {
        precondition(iv.count == 16)
        var counter = iv
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        var offset = 0
        while offset < data.count {
            let keystream = aesEncryptBlock(key: key, block: counter)
            let n = min(16, data.count - offset)
            for k in 0..<n { out.append(data[offset + k] ^ keystream[k]) }
            offset += n
            incrementBigEndian(&counter)
        }
        return out
    }

    static func incrementBigEndian(_ block: inout [UInt8]) {
        var i = block.count - 1
        while i >= 0 {
            block[i] &+= 1
            if block[i] != 0 { return }
            i -= 1
        }
    }

    /// AES-128-CCM (RFC 3610) без додаткових даних. Повертає шифротекст ‖ тег.
    public static func aesCCMEncrypt(key: [UInt8], nonce: [UInt8], plaintext: [UInt8], tagLength: Int = 4) -> [UInt8] {
        precondition((7...13).contains(nonce.count))
        precondition(tagLength >= 4 && tagLength <= 16 && tagLength % 2 == 0)
        let lengthFieldSize = 15 - nonce.count // L

        func lengthField(_ value: Int) -> [UInt8] {
            (0..<lengthFieldSize).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }

        // CBC-MAC над B0 і відкритим текстом.
        let flagsB0 = UInt8(((tagLength - 2) / 2) << 3) | UInt8(lengthFieldSize - 1)
        var mac = aesEncryptBlock(key: key, block: [flagsB0] + nonce + lengthField(plaintext.count))
        var offset = 0
        while offset < plaintext.count {
            var block = [UInt8](repeating: 0, count: 16)
            let n = min(16, plaintext.count - offset)
            for k in 0..<n { block[k] = plaintext[offset + k] }
            for k in 0..<16 { mac[k] ^= block[k] }
            mac = aesEncryptBlock(key: key, block: mac)
            offset += n
        }

        // Шифрування лічильником A_i.
        let flagsA = UInt8(lengthFieldSize - 1)
        func counterBlock(_ i: Int) -> [UInt8] { [flagsA] + nonce + lengthField(i) }

        var out = [UInt8]()
        out.reserveCapacity(plaintext.count + tagLength)
        offset = 0
        var counter = 1
        while offset < plaintext.count {
            let s = aesEncryptBlock(key: key, block: counterBlock(counter))
            let n = min(16, plaintext.count - offset)
            for k in 0..<n { out.append(plaintext[offset + k] ^ s[k]) }
            offset += n
            counter += 1
        }
        let s0 = aesEncryptBlock(key: key, block: counterBlock(0))
        for k in 0..<tagLength { out.append(mac[k] ^ s0[k]) }
        return out
    }

    // MARK: Хеші

    public static func hmacSHA256(key: [UInt8], data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    public static func md5(_ data: [UInt8]) -> [UInt8] {
        Array(Insecure.MD5.hash(data: data))
    }

    /// HKDF-SHA256 (RFC 5869).
    public static func hkdfSHA256(inputKey: [UInt8], salt: [UInt8], info: [UInt8], length: Int) -> [UInt8] {
        let prk = hmacSHA256(key: salt, data: inputKey)
        var okm: [UInt8] = []
        var previous: [UInt8] = []
        var counter: UInt8 = 1
        while okm.count < length {
            previous = hmacSHA256(key: prk, data: previous + info + [counter])
            okm.append(contentsOf: previous)
            counter += 1
        }
        return Array(okm.prefix(length))
    }
}

/// Ключі однієї сесії, виведені з auth key і двох nonce.
public struct SessionKeys: Sendable, Equatable {
    /// Браслет → телефон.
    public let decryptionKey: [UInt8]
    /// Телефон → браслет.
    public let encryptionKey: [UInt8]
    /// Nonce для CCM на кроці 3 (байти 36–40; байти 32–36 протоколу не потрібні).
    public let encryptionNonce: [UInt8]

    public static let info = Array("miwear-auth".utf8)

    public init(authKey: [UInt8], phoneNonce: [UInt8], bandNonce: [UInt8]) {
        let material = BandCrypto.hkdfSHA256(
            inputKey: authKey,
            salt: phoneNonce + bandNonce,
            info: SessionKeys.info,
            length: 64
        )
        decryptionKey = Array(material[0..<16])
        encryptionKey = Array(material[16..<32])
        encryptionNonce = Array(material[36..<40])
    }

    /// Очікуваний HMAC браслета з кроку 2: HMAC-SHA256(Kd, W ‖ P).
    public func expectedBandHMAC(phoneNonce: [UInt8], bandNonce: [UInt8]) -> [UInt8] {
        BandCrypto.hmacSHA256(key: decryptionKey, data: bandNonce + phoneNonce)
    }

    /// Підтвердження телефону для кроку 3: HMAC-SHA256(Ke, P ‖ W).
    public func phoneConfirmation(phoneNonce: [UInt8], bandNonce: [UInt8]) -> [UInt8] {
        BandCrypto.hmacSHA256(key: encryptionKey, data: phoneNonce + bandNonce)
    }

    /// Шифрує інформацію про телефон для кроку 3: AES-128-CCM, nonce = Ne ‖ 8 нулів, тег 4 байти.
    public func encryptPhoneInfo(_ plaintext: [UInt8]) -> [UInt8] {
        BandCrypto.aesCCMEncrypt(
            key: encryptionKey,
            nonce: encryptionNonce + [UInt8](repeating: 0, count: 8),
            plaintext: plaintext,
            tagLength: 4
        )
    }

    /// Шифрує тіло команди телефону (AES-128-CTR, IV = Ke).
    public func encryptCommand(_ body: [UInt8]) -> [UInt8] {
        BandCrypto.aesCTR(key: encryptionKey, iv: encryptionKey, data: body)
    }

    /// Дешифрує тіло команди браслета (AES-128-CTR, IV = Kd).
    public func decryptCommand(_ body: [UInt8]) -> [UInt8] {
        BandCrypto.aesCTR(key: decryptionKey, iv: decryptionKey, data: body)
    }
}
