// SPDX-License-Identifier: MIT
package com.bandface.kit

object FrameType {
    const val ACK = 1
    const val SESSION = 2
    const val DATA = 3
}

/** Кадр транспортного рівня: A5 A5 | тип | номер | довжина LE16 | CRC-16 LE16 | навантаження. */
class Frame(val type: Int, val sequence: Int, val payload: ByteArray = ByteArray(0)) {
    fun encoded(): ByteArray {
        val b = ByteBuilder()
        b.u8(0xA5).u8(0xA5)
        b.u8(type) // прапорці у старших бітах = 0
        b.u8(sequence)
        b.le16(payload.size)
        b.le16(if (payload.isEmpty()) 0 else Checksum.crc16ARC(payload))
        b.bytes(payload)
        return b.toByteArray()
    }

    override fun equals(other: Any?): Boolean =
        other is Frame && type == other.type && sequence == other.sequence && payload.contentEquals(other.payload)

    override fun hashCode(): Int = (type * 31 + sequence) * 31 + payload.contentHashCode()

    override fun toString(): String = "Frame(type=$type, seq=$sequence, payload=${payload.hexString()})"

    companion object {
        const val HEADER_LENGTH = 8
        const val MAX_PAYLOAD_LENGTH = 0xFC00

        fun ack(sequence: Int): Frame = Frame(FrameType.ACK, sequence)
    }
}

/** Накопичує байти зі сповіщень BLE і виділяє з них цілі кадри. */
class FrameParser {
    private var buffer = ByteArray(0)

    fun reset() {
        buffer = ByteArray(0)
    }

    fun append(bytes: ByteArray): List<Frame> {
        buffer += bytes
        val frames = ArrayList<Frame>()
        while (true) {
            val start = preambleIndex()
            if (start < 0) {
                // Останній байт зберігаємо: він може бути першою половиною преамбули
                buffer = if (buffer.isNotEmpty() && buffer.last() == 0xA5.toByte()) byteArrayOf(0xA5.toByte()) else ByteArray(0)
                break
            }
            if (start > 0) buffer = buffer.copyOfRange(start, buffer.size)
            if (buffer.size < Frame.HEADER_LENGTH) break

            val length = buffer.le16(4)
            if (length > Frame.MAX_PAYLOAD_LENGTH) {
                buffer = buffer.copyOfRange(1, buffer.size)
                continue
            }
            if (buffer.size < Frame.HEADER_LENGTH + length) break

            val payload = buffer.copyOfRange(Frame.HEADER_LENGTH, Frame.HEADER_LENGTH + length)
            val crc = buffer.le16(6)
            val expected = if (payload.isEmpty()) 0 else Checksum.crc16ARC(payload)
            if (crc != expected) {
                // Невірна сума: шукаємо наступну преамбулу після цієї
                buffer = buffer.copyOfRange(1, buffer.size)
                continue
            }

            val typeNibble = buffer.u(2) and 0x0F
            val sequence = buffer.u(3)
            buffer = buffer.copyOfRange(Frame.HEADER_LENGTH + length, buffer.size)
            if (typeNibble == FrameType.ACK || typeNibble == FrameType.SESSION || typeNibble == FrameType.DATA) {
                frames.add(Frame(typeNibble, sequence, payload))
            }
        }
        return frames
    }

    private fun preambleIndex(): Int {
        for (i in 0 until buffer.size - 1) {
            if (buffer[i] == 0xA5.toByte() && buffer[i + 1] == 0xA5.toByte()) return i
        }
        return -1
    }
}

object DataChannel {
    const val PROTOBUF = 1
    const val FILE = 2
}

object DataOpcode {
    const val PLAIN = 1
    const val ENCRYPTED = 2
}

/** Навантаження кадру даних: канал, код операції, тіло. */
class DataPacket(val channel: Int, val opcode: Int, val body: ByteArray) {
    val payload: ByteArray get() = ByteBuilder().u8(channel).u8(opcode).bytes(body).toByteArray()

    companion object {
        fun parse(payload: ByteArray): DataPacket? {
            if (payload.size < 2) return null
            return DataPacket(payload.u(0) and 0x0F, payload.u(1), payload.copyOfRange(2, payload.size))
        }
    }
}

/** Навантаження кадру керування сесією (тип 2): код + параметри TLV «ключ (1 байт), довжина (LE16), значення». */
class SessionControl(val code: Int, val parameters: List<Pair<Int, ByteArray>> = emptyList()) {
    val payload: ByteArray
        get() {
            val b = ByteBuilder().u8(code)
            for ((key, value) in parameters) {
                b.u8(key).le16(value.size).bytes(value)
            }
            return b.toByteArray()
        }

    companion object {
        const val OPEN_REQUEST = 1
        const val OPEN_RESPONSE = 2
        const val CLOSE_REQUEST = 3
        const val CLOSE_RESPONSE = 4

        fun parse(payload: ByteArray): SessionControl? {
            if (payload.isEmpty()) return null
            val params = ArrayList<Pair<Int, ByteArray>>()
            var i = 1
            while (i + 3 <= payload.size) {
                val key = payload.u(i)
                val len = payload.le16(i + 1)
                i += 3
                if (i + len > payload.size) return null
                params.add(key to payload.copyOfRange(i, i + len))
                i += len
            }
            return SessionControl(payload.u(0), params)
        }

        /** Запит на відкриття, перевірений на Band 10: версія 1.0.0, макс. кадр 0xFC00, вікно 32, тайм-аут 10000 мс. */
        val defaultOpen: SessionControl
            get() = SessionControl(
                OPEN_REQUEST,
                listOf(
                    1 to bytesOf(0x01, 0x00, 0x00),
                    2 to bytesOf(0x00, 0xFC),
                    3 to bytesOf(0x20, 0x00),
                    4 to bytesOf(0x10, 0x27),
                ),
            )

        val close: SessionControl get() = SessionControl(CLOSE_REQUEST)
    }
}
