import Foundation
import CryptoKit
import CommonCrypto

/// Криптографія протоколу Xiaomi (порт із Gadgetbridge, XiaomiAuthService).
enum XiaomiCrypto {
    static func hmacSHA256(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    /// 64 байти: decKey(16) | encKey(16) | decNonce(4) | encNonce(4) | ...
    static func deriveSessionKeys(secretKey: Data, phoneNonce: Data, watchNonce: Data) -> Data {
        let hmacKey = hmacSHA256(key: phoneNonce + watchNonce, data: secretKey)
        let label = Data("miwear-auth".utf8)
        var out = Data()
        var tmp = Data()
        var counter: UInt8 = 1
        while out.count < 64 {
            tmp = hmacSHA256(key: hmacKey, data: tmp + label + Data([counter]))
            out.append(tmp)
            counter &+= 1
        }
        return out.prefix(64)
    }

    /// AES-128 ECB (вхід має бути кратний 16 байтам).
    static func aesECB(key: Data, input: Data) -> Data {
        precondition(key.count == 16 && !input.isEmpty && input.count % 16 == 0)
        let outLen = input.count + kCCBlockSizeAES128
        var out = Data(count: outLen)
        var moved = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    CCCrypt(CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionECBMode),
                            keyPtr.baseAddress, key.count,
                            nil,
                            inPtr.baseAddress, input.count,
                            outPtr.baseAddress, outLen,
                            &moved)
                }
            }
        }
        precondition(Int(status) == kCCSuccess, "AES failed")
        return out.prefix(moved)
    }

    private static func xor(_ a: Data, _ b: Data) -> Data {
        var out = Data(count: min(a.count, b.count))
        for i in 0..<out.count { out[i] = a[a.startIndex + i] ^ b[b.startIndex + i] }
        return out
    }

    /// AES-CTR, лічильник big-endian на весь 128-бітний блок (як Java AES/CTR/NoPadding).
    static func aesCTR(key: Data, iv: Data, data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        precondition(iv.count == 16)
        let blocks = (data.count + 15) / 16
        var counter = [UInt8](iv)
        var counters = Data()
        for _ in 0..<blocks {
            counters.append(contentsOf: counter)
            var i = 15
            while i >= 0 {
                counter[i] &+= 1
                if counter[i] != 0 { break }
                i -= 1
            }
        }
        let stream = aesECB(key: key, input: counters)
        return xor(data, stream)
    }

    /// AES-CCM (тег 4 байти, nonce 12 байт). Повертає шифртекст + тег.
    static func aesCCMEncrypt(key: Data, nonce: Data, plaintext: Data, tagLength: Int = 4) -> Data {
        precondition(nonce.count == 12 && !plaintext.isEmpty)
        let n = plaintext.count

        // CBC-MAC
        let flags = UInt8(((tagLength - 2) / 2) << 3 | 2)
        var b0 = Data([flags]) + nonce
        b0.append(contentsOf: [UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
        var x = aesECB(key: key, input: b0)
        var padded = plaintext
        if padded.count % 16 != 0 { padded.append(Data(count: 16 - padded.count % 16)) }
        var off = 0
        while off < padded.count {
            x = aesECB(key: key, input: xor(x, padded.subdata(in: off..<off + 16)))
            off += 16
        }
        let tag = x.prefix(tagLength)

        // CTR
        func counterBlock(_ i: Int) -> Data {
            Data([2]) + nonce + Data([UInt8((i >> 16) & 0xFF), UInt8((i >> 8) & 0xFF), UInt8(i & 0xFF)])
        }
        let blocks = (n + 15) / 16
        var counters = counterBlock(0)
        for i in 1...blocks { counters.append(counterBlock(i)) }
        let stream = aesECB(key: key, input: counters)
        let s0 = stream.prefix(16)
        let cipher = xor(plaintext, stream.suffix(from: stream.startIndex + 16))
        return cipher + xor(tag, s0)
    }

    /// V2: AES-CTR, де і ключ, і IV — це сесійний ключ.
    static func v2Crypt(key: Data, data: Data) -> Data {
        aesCTR(key: key, iv: key, data: data)
    }

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}
