// SPDX-License-Identifier: MIT
package com.bandface.kit

import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object BandCrypto {
    /** Один блок AES-128 (ECB без доповнення). */
    fun aesEncryptBlock(key: ByteArray, block: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
        return cipher.doFinal(block)
    }

    /** AES-128-CTR; лічильник — увесь 16-байтовий блок як big-endian число. */
    fun aesCTR(key: ByteArray, iv: ByteArray, data: ByteArray): ByteArray {
        require(iv.size == 16)
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
        val counter = iv.copyOf()
        val out = ByteArray(data.size)
        var offset = 0
        while (offset < data.size) {
            val stream = cipher.doFinal(counter)
            val n = minOf(16, data.size - offset)
            for (k in 0 until n) out[offset + k] = (data[offset + k].toInt() xor stream[k].toInt()).toByte()
            offset += n
            var i = counter.size - 1
            while (i >= 0) {
                counter[i] = (counter[i] + 1).toByte()
                if (counter[i] != 0.toByte()) break
                i--
            }
        }
        return out
    }

    /** AES-128-CCM (RFC 3610) без додаткових даних. Повертає шифротекст ‖ тег. */
    fun aesCCMEncrypt(key: ByteArray, nonce: ByteArray, plaintext: ByteArray, tagLength: Int = 4): ByteArray {
        require(nonce.size in 7..13)
        require(tagLength in 4..16 && tagLength % 2 == 0)
        val l = 15 - nonce.size

        fun lengthField(value: Int): ByteArray =
            ByteArray(l) { idx -> (value shr (8 * (l - 1 - idx))).toByte() }

        val flagsB0 = ((((tagLength - 2) / 2) shl 3) or (l - 1)).toByte()
        var mac = aesEncryptBlock(key, byteArrayOf(flagsB0) + nonce + lengthField(plaintext.size))
        var offset = 0
        while (offset < plaintext.size) {
            val block = ByteArray(16)
            val n = minOf(16, plaintext.size - offset)
            for (k in 0 until n) block[k] = plaintext[offset + k]
            for (k in 0 until 16) mac[k] = (mac[k].toInt() xor block[k].toInt()).toByte()
            mac = aesEncryptBlock(key, mac)
            offset += n
        }

        val flagsA = (l - 1).toByte()
        fun counterBlock(i: Int): ByteArray = byteArrayOf(flagsA) + nonce + lengthField(i)

        val out = ByteArray(plaintext.size + tagLength)
        offset = 0
        var counter = 1
        while (offset < plaintext.size) {
            val s = aesEncryptBlock(key, counterBlock(counter))
            val n = minOf(16, plaintext.size - offset)
            for (k in 0 until n) out[offset + k] = (plaintext[offset + k].toInt() xor s[k].toInt()).toByte()
            offset += n
            counter++
        }
        val s0 = aesEncryptBlock(key, counterBlock(0))
        for (k in 0 until tagLength) out[plaintext.size + k] = (mac[k].toInt() xor s0[k].toInt()).toByte()
        return out
    }

    fun hmacSHA256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(if (key.isEmpty()) ByteArray(1) else key, "HmacSHA256"))
        return mac.doFinal(data)
    }

    fun md5(data: ByteArray): ByteArray = MessageDigest.getInstance("MD5").digest(data)

    /** HKDF-SHA256 (RFC 5869). */
    fun hkdfSHA256(inputKey: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val prk = hmacSHA256(salt, inputKey)
        var okm = ByteArray(0)
        var previous = ByteArray(0)
        var counter = 1
        while (okm.size < length) {
            previous = hmacSHA256(prk, previous + info + byteArrayOf(counter.toByte()))
            okm += previous
            counter++
        }
        return okm.copyOf(length)
    }
}

/** Ключі однієї сесії, виведені з auth key і двох nonce. */
class SessionKeys(authKey: ByteArray, phoneNonce: ByteArray, bandNonce: ByteArray) {
    /** Браслет → телефон. */
    val decryptionKey: ByteArray
    /** Телефон → браслет. */
    val encryptionKey: ByteArray
    val encryptionNonce: ByteArray

    init {
        val material = BandCrypto.hkdfSHA256(authKey, phoneNonce + bandNonce, "miwear-auth".toByteArray(), 64)
        decryptionKey = material.copyOfRange(0, 16)
        encryptionKey = material.copyOfRange(16, 32)
        encryptionNonce = material.copyOfRange(36, 40)
    }

    fun expectedBandHMAC(phoneNonce: ByteArray, bandNonce: ByteArray): ByteArray =
        BandCrypto.hmacSHA256(decryptionKey, bandNonce + phoneNonce)

    fun phoneConfirmation(phoneNonce: ByteArray, bandNonce: ByteArray): ByteArray =
        BandCrypto.hmacSHA256(encryptionKey, phoneNonce + bandNonce)

    fun encryptPhoneInfo(plaintext: ByteArray): ByteArray =
        BandCrypto.aesCCMEncrypt(encryptionKey, encryptionNonce + ByteArray(8), plaintext, 4)

    fun encryptCommand(body: ByteArray): ByteArray = BandCrypto.aesCTR(encryptionKey, encryptionKey, body)

    fun decryptCommand(body: ByteArray): ByteArray = BandCrypto.aesCTR(decryptionKey, decryptionKey, body)
}
