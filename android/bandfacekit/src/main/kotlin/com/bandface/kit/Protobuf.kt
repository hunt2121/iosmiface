// SPDX-License-Identifier: MIT
package com.bandface.kit

import java.io.ByteArrayOutputStream

sealed class ProtoValue {
    data class Varint(val value: Long) : ProtoValue()
    data class Fixed64(val value: Long) : ProtoValue()
    class Bytes(val value: ByteArray) : ProtoValue()
    data class Fixed32(val value: Long) : ProtoValue()
}

class ProtoField(val number: Int, val value: ProtoValue)

class ProtoWriter {
    private val out = ByteArrayOutputStream()

    val output: ByteArray get() = out.toByteArray()

    private fun writeVarint(value: Long) {
        var v = value
        while ((v and 0x7FL.inv()) != 0L) {
            out.write(((v and 0x7F) or 0x80).toInt())
            v = v ushr 7
        }
        out.write(v.toInt())
    }

    private fun tag(field: Int, wire: Int) = writeVarint((field.toLong() shl 3) or wire.toLong())

    fun varint(field: Int, value: Long): ProtoWriter { tag(field, 0); writeVarint(value); return this }

    fun bytes(field: Int, value: ByteArray): ProtoWriter {
        tag(field, 2); writeVarint(value.size.toLong()); out.write(value, 0, value.size); return this
    }

    fun string(field: Int, value: String): ProtoWriter = bytes(field, value.toByteArray(Charsets.UTF_8))

    fun float(field: Int, value: Float): ProtoWriter {
        tag(field, 5)
        val bits = java.lang.Float.floatToIntBits(value)
        for (shift in 0 until 32 step 8) out.write((bits shr shift) and 0xFF)
        return this
    }

    fun message(field: Int, build: (ProtoWriter) -> Unit): ProtoWriter {
        val nested = ProtoWriter()
        build(nested)
        return bytes(field, nested.output)
    }
}

class ProtoMessage(val fields: List<ProtoField>) {
    fun first(number: Int): ProtoValue? = fields.firstOrNull { it.number == number }?.value

    fun all(number: Int): List<ProtoValue> = fields.filter { it.number == number }.map { it.value }

    fun varint(number: Int): Long? = (first(number) as? ProtoValue.Varint)?.value

    fun bool(number: Int): Boolean? = varint(number)?.let { it != 0L }

    fun bytes(number: Int): ByteArray? = (first(number) as? ProtoValue.Bytes)?.value

    fun string(number: Int): String? = bytes(number)?.toString(Charsets.UTF_8)

    fun message(number: Int): ProtoMessage? = bytes(number)?.let { runCatching { parse(it) }.getOrNull() }

    fun messages(number: Int): List<ProtoMessage> =
        all(number).mapNotNull { v -> (v as? ProtoValue.Bytes)?.let { runCatching { parse(it.value) }.getOrNull() } }

    fun message(path: List<Int>): ProtoMessage? {
        var current: ProtoMessage? = this
        for (n in path) current = current?.message(n)
        return current
    }

    fun value(path: List<Int>): ProtoValue? {
        val last = path.lastOrNull() ?: return null
        return message(path.dropLast(1))?.first(last)
    }

    fun varint(path: List<Int>): Long? = (value(path) as? ProtoValue.Varint)?.value

    fun bytes(path: List<Int>): ByteArray? = (value(path) as? ProtoValue.Bytes)?.value

    companion object {
        fun parse(data: ByteArray): ProtoMessage {
            val fields = ArrayList<ProtoField>()
            var i = 0

            fun readVarint(): Long {
                var result = 0L
                var shift = 0
                while (true) {
                    if (i >= data.size || shift >= 64) throw BandError(ErrorKind.MALFORMED_PROTOBUF)
                    val b = data.u(i)
                    i++
                    result = result or ((b and 0x7F).toLong() shl shift)
                    if (b and 0x80 == 0) return result
                    shift += 7
                }
            }

            while (i < data.size) {
                val key = readVarint()
                val number = (key ushr 3).toInt()
                if (number <= 0) throw BandError(ErrorKind.MALFORMED_PROTOBUF)
                when ((key and 7).toInt()) {
                    0 -> fields.add(ProtoField(number, ProtoValue.Varint(readVarint())))
                    1 -> {
                        if (i + 8 > data.size) throw BandError(ErrorKind.MALFORMED_PROTOBUF)
                        var v = 0L
                        for (k in 0 until 8) v = v or (data.u(i + k).toLong() shl (8 * k))
                        i += 8
                        fields.add(ProtoField(number, ProtoValue.Fixed64(v)))
                    }
                    2 -> {
                        val len = readVarint()
                        if (len < 0 || len > (data.size - i).toLong()) throw BandError(ErrorKind.MALFORMED_PROTOBUF)
                        val end = i + len.toInt()
                        fields.add(ProtoField(number, ProtoValue.Bytes(data.copyOfRange(i, end))))
                        i = end
                    }
                    5 -> {
                        if (i + 4 > data.size) throw BandError(ErrorKind.MALFORMED_PROTOBUF)
                        fields.add(ProtoField(number, ProtoValue.Fixed32(data.le32(i))))
                        i += 4
                    }
                    else -> throw BandError(ErrorKind.MALFORMED_PROTOBUF)
                }
            }
            return ProtoMessage(fields)
        }
    }
}
