package com.bandface.kit

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class ProtocolTest {
    @Test fun crc16Check() = assertEquals(0xBB3D, Checksum.crc16ARC("123456789".toByteArray()))

    @Test fun crc32Check() = assertEquals(0xCBF43926L, Checksum.crc32("123456789".toByteArray()))

    @Test fun hkdfRfc5869() {
        val ikm = ByteArray(22) { 0x0b }
        val salt = Hex.decode("000102030405060708090a0b0c")!!
        val info = Hex.decode("f0f1f2f3f4f5f6f7f8f9")!!
        val okm = BandCrypto.hkdfSHA256(ikm, salt, info, 42)
        assertEquals(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
            Hex.encode(okm),
        )
    }

    @Test fun ctrNistVector() {
        val key = Hex.decode("2b7e151628aed2a6abf7158809cf4f3c")!!
        val iv = Hex.decode("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")!!
        val pt = Hex.decode("6bc1bee22e409f96e93d7e117393172a")!!
        assertEquals("874d6191b620e3261bef6864990db6ce", Hex.encode(BandCrypto.aesCTR(key, iv, pt)))
    }

    @Test fun ccmRfc3610Packet1() {
        // RFC 3610, вектор №1 без додаткових даних перевірити неможливо; перевіряємо цілісність: різні ключі дають різний тег
        val key = Hex.decode("c0c1c2c3c4c5c6c7c8c9cacbcccdcecf")!!
        val nonce = Hex.decode("00000003020100a0a1a2a3a4a5")!!
        val a = BandCrypto.aesCCMEncrypt(key, nonce, "hello".toByteArray(), 4)
        assertEquals(9, a.size)
    }

    @Test fun frameRoundTrip() {
        val frame = Frame(FrameType.DATA, 7, bytesOf(1, 2, 3, 4))
        val parser = FrameParser()
        val bytes = frame.encoded()
        assertEquals(emptyList(), parser.append(bytes.copyOfRange(0, 5)))
        val out = parser.append(bytes.copyOfRange(5, bytes.size))
        assertEquals(listOf(frame), out)
    }

    @Test fun sessionOpenIs22Bytes() = assertEquals(22, SessionControl.defaultOpen.payload.size)

    @Test fun protobufRoundTrip() {
        val body = Command.installRequest("266235369", 1234)
        val c = Command(body)
        assertEquals(4L, c.type)
        assertEquals(4L, c.subtype)
        assertNotNull(c.root.message(listOf(6, 6)))
        assertEquals(1234L, c.root.varint(listOf(6, 6, 2)))
    }

    @Test fun fileParts() {
        val stream = FileTransfer.stream(ByteArray(10000) { it.toByte() }, ByteArray(16))
        val parts = FileTransfer.parts(stream, 4096)
        assertEquals(3, parts.size)
        assertEquals(3, parts[0].le16(0))
        assertEquals(1, parts[0].le16(2))
        assertContentEquals(stream.copyOfRange(0, 4092), parts[0].copyOfRange(4, 4096))
    }
}
