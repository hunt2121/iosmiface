// SPDX-License-Identifier: MIT
// BandFaceKit для Android: відкрита реалізація протоколу встановлення циферблатів на Xiaomi Smart Band 10.
package com.bandface.kit

import java.io.ByteArrayOutputStream

enum class ErrorKind {
    TIMEOUT, NOT_CONNECTED, CHARACTERISTIC_NOT_FOUND, SESSION_OPEN_FAILED, SESSION_NOT_OPEN,
    NOT_AUTHENTICATED, INVALID_AUTH_KEY, AUTH_KEY_MISMATCH, MALFORMED_RESPONSE, MALFORMED_PROTOBUF,
    INSTALL_REJECTED, UPLOAD_REJECTED, INSTALL_ABORTED, ACTIVATION_FAILED, INVALID_FACE_FILE,
    INVALID_PREVIEW, CANCELLED, DISCONNECTED,
}

/** Помилка бібліотеки. `detail` — технічна причина, `status` — код браслета, якщо він є. */
class BandError(val kind: ErrorKind, val detail: String = "", val status: Long = 0) :
    Exception("$kind $detail".trim())

internal fun ByteArray.u(i: Int): Int = this[i].toInt() and 0xFF

internal fun ByteArray.le16(i: Int): Int = u(i) or (u(i + 1) shl 8)

internal fun ByteArray.le32(i: Int): Long =
    u(i).toLong() or (u(i + 1).toLong() shl 8) or (u(i + 2).toLong() shl 16) or (u(i + 3).toLong() shl 24)

fun bytesOf(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }

/** Шістнадцятковий рядок через пробіл, для журналу. */
fun ByteArray.hexString(): String = joinToString(" ") { "%02X".format(it.toInt() and 0xFF) }

/** Збирає байти: однобайтові числа та little-endian 16/32 біти. */
class ByteBuilder {
    private val out = ByteArrayOutputStream()

    fun u8(v: Int): ByteBuilder { out.write(v and 0xFF); return this }
    fun le16(v: Int): ByteBuilder { out.write(v and 0xFF); out.write((v shr 8) and 0xFF); return this }
    fun le32(v: Long): ByteBuilder {
        for (shift in 0 until 32 step 8) out.write(((v shr shift) and 0xFF).toInt())
        return this
    }
    fun bytes(b: ByteArray): ByteBuilder { out.write(b, 0, b.size); return this }
    fun bytes(b: ByteArray, from: Int, to: Int): ByteBuilder { out.write(b, from, to - from); return this }
    fun size(): Int = out.size()
    fun toByteArray(): ByteArray = out.toByteArray()
}

object Hex {
    /** Розбирає шістнадцятковий рядок; пробіли, двокрапки, дефіси і префікс 0x ігноруються. */
    fun decode(string: String): ByteArray? {
        var s = string.trim()
        if (s.startsWith("0x") || s.startsWith("0X")) s = s.substring(2)
        s = s.filter { it != ' ' && it != ':' && it != '-' }
        if (s.length % 2 != 0) return null
        val out = ByteArray(s.length / 2)
        for (i in out.indices) {
            val hi = Character.digit(s[i * 2], 16)
            val lo = Character.digit(s[i * 2 + 1], 16)
            if (hi < 0 || lo < 0) return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    fun encode(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
}

/** Порівняння без витоку часу. */
internal fun constantTimeEqual(a: ByteArray, b: ByteArray): Boolean {
    if (a.size != b.size) return false
    var diff = 0
    for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
    return diff == 0
}

object Checksum {
    /** CRC-16/ARC: поліном 0x8005 (віддзеркалений 0xA001), init 0, refin/refout, без xorout. */
    fun crc16ARC(data: ByteArray): Int {
        var crc = 0
        for (byte in data) {
            crc = crc xor (byte.toInt() and 0xFF)
            repeat(8) {
                crc = if ((crc and 1) != 0) (crc ushr 1) xor 0xA001 else crc ushr 1
            }
        }
        return crc and 0xFFFF
    }

    /** CRC-32 (IEEE 802.3, як у ZIP). */
    fun crc32(data: ByteArray): Long {
        val c = java.util.zip.CRC32()
        c.update(data, 0, data.size)
        return c.value
    }
}
