// SPDX-License-Identifier: MIT
package com.bandface.kit

class FaceFile(val data: ByteArray) {
    val id: String
    val name: String?
    val previewOffset: Int?

    init {
        if (data.size < 0x7C) throw BandError(ErrorKind.INVALID_FACE_FILE, "file too short")
        if (data[0] != 0x5A.toByte() || data[1] != 0xA5.toByte()) throw BandError(ErrorKind.INVALID_FACE_FILE, "bad signature")
        val idBytes = zeroTerminated(data, 0x28, 0x40)
        if (idBytes.isEmpty() || idBytes.any { it < 0x30 || it > 0x39 }) {
            throw BandError(ErrorKind.INVALID_FACE_FILE, "bad watchface id")
        }
        id = String(idBytes, Charsets.US_ASCII)
        name = if (data.le32(0x68) == 0xFFFFFFFFL) null
        else String(zeroTerminated(data, 0x68, 0x40), Charsets.UTF_8).ifEmpty { null }
        val offset = data.le32(0x20).toInt()
        previewOffset = if (offset <= 0 || offset + 12 > data.size) null else offset
    }

    val size: Int get() = data.size
    val md5: ByteArray get() = BandCrypto.md5(data)

    fun decodePreview(): PreviewImage? = previewOffset?.let { PreviewImage.decode(data, it) }

    private fun zeroTerminated(b: ByteArray, from: Int, maxLength: Int): ByteArray {
        val end = minOf(from + maxLength, b.size)
        var i = from
        while (i < end && b[i] != 0.toByte()) i++
        return b.copyOfRange(from, i)
    }
}

/** Розпаковане зображення: ARGB-пікселі (як android.graphics.Bitmap.setPixels). */
class PreviewImage(val width: Int, val height: Int, val argb: IntArray) {
    companion object {
        fun decode(bytes: ByteArray, offset: Int): PreviewImage {
            if (offset + 12 > bytes.size) throw BandError(ErrorKind.INVALID_PREVIEW, "header out of range")
            val format = bytes.u(offset)
            if (format !in intArrayOf(0, 1, 4, 7, 16)) throw BandError(ErrorKind.INVALID_PREVIEW, "unknown pixel format $format")
            val compression = bytes.u(offset + 1)
            if (compression !in intArrayOf(0, 4, 8)) throw BandError(ErrorKind.INVALID_PREVIEW, "unknown compression $compression")
            val width = bytes.le16(offset + 4)
            val height = bytes.le16(offset + 6)
            val size = bytes.le32(offset + 8)
            val start = offset + 12
            if (width <= 0 || height <= 0 || width > 4096 || height > 4096) throw BandError(ErrorKind.INVALID_PREVIEW, "bad dimensions")
            if (start + size > bytes.size) throw BandError(ErrorKind.INVALID_PREVIEW, "data out of range")
            var raw = bytes.copyOfRange(start, start + size.toInt())
            raw = when (compression) {
                8 -> RLE.decode(raw, runIsHigh = true)
                4 -> RLE.decode(raw, runIsHigh = false)
                else -> raw
            }
            return fromRaw(raw, format, width, height)
        }

        fun fromRaw(raw: ByteArray, format: Int, width: Int, height: Int): PreviewImage {
            val count = width * height
            val out = IntArray(count)
            fun argb(a: Int, r: Int, g: Int, b: Int) = (a shl 24) or (r shl 16) or (g shl 8) or b
            fun put565(i: Int, v: Int) {
                val r = (v shr 11) and 0x1F
                val g = (v shr 5) and 0x3F
                val b = v and 0x1F
                out[i] = argb(0xFF, (r shl 3) or (r shr 2), (g shl 2) or (g shr 4), (b shl 3) or (b shr 2))
            }
            when (format) {
                0 -> {
                    if (raw.size < count * 4) throw BandError(ErrorKind.INVALID_PREVIEW, "not enough pixel data")
                    for (i in 0 until count) out[i] = argb(raw.u(i * 4 + 3), raw.u(i * 4 + 2), raw.u(i * 4 + 1), raw.u(i * 4))
                }
                1, 4 -> {
                    if (raw.size < count * 2) throw BandError(ErrorKind.INVALID_PREVIEW, "not enough pixel data")
                    for (i in 0 until count) put565(i, raw.u(i * 2) or (raw.u(i * 2 + 1) shl 8))
                }
                7 -> {
                    if (raw.size < count * 2) throw BandError(ErrorKind.INVALID_PREVIEW, "not enough pixel data")
                    for (i in 0 until count) put565(i, (raw.u(i * 2) shl 8) or raw.u(i * 2 + 1))
                }
                else -> {
                    val palette = 256 * 4
                    if (raw.size < palette + count) throw BandError(ErrorKind.INVALID_PREVIEW, "not enough pixel data")
                    for (i in 0 until count) {
                        val p = raw.u(palette + i) * 4
                        out[i] = argb(raw.u(p + 3), raw.u(p + 2), raw.u(p + 1), raw.u(p))
                    }
                }
            }
            return PreviewImage(width, height, out)
        }
    }
}

object RLE {
    private val magic = bytesOf(0xE0, 0x21, 0xA5, 0x5A)

    /** runIsHigh = true — варіант «8» (старший біт 1: повтор n+1), false — «4» (старший біт 0: повтор n). */
    fun decode(data: ByteArray, runIsHigh: Boolean): ByteArray {
        if (data.size < 8 || !data.copyOfRange(0, 4).contentEquals(magic)) {
            throw BandError(ErrorKind.INVALID_PREVIEW, "bad RLE header")
        }
        val word = data.le32(4)
        val elementSize = maxOf((word and 0x0F).toInt(), 1)
        val total = (word shr 4).toInt()
        val out = java.io.ByteArrayOutputStream(total)
        var i = 8
        while (i < data.size && out.size() < total) {
            val control = data.u(i)
            i++
            val high = control and 0x80 != 0
            val n = control and 0x7F
            val isRun: Boolean
            val count: Int
            if (runIsHigh) { isRun = high; count = n + 1 } else { isRun = !high; count = n }
            if (isRun) {
                if (i + elementSize > data.size) throw BandError(ErrorKind.INVALID_PREVIEW, "truncated RLE")
                repeat(count) { out.write(data, i, elementSize) }
                i += elementSize
            } else {
                val length = count * elementSize
                if (i + length > data.size) throw BandError(ErrorKind.INVALID_PREVIEW, "truncated RLE")
                out.write(data, i, length)
                i += length
            }
        }
        val result = out.toByteArray()
        return if (result.size > total) result.copyOf(total) else result
    }
}
