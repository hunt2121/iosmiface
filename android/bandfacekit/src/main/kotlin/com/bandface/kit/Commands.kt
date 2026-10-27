// SPDX-License-Identifier: MIT
package com.bandface.kit

/** Повідомлення «Команда» (protobuf) і конструктори потрібних команд. */
class Command(body: ByteArray) {
    val root: ProtoMessage = ProtoMessage.parse(body)
    val type: Long = root.varint(1) ?: throw BandError(ErrorKind.MALFORMED_RESPONSE, "command without type")
    val subtype: Long = root.varint(2) ?: 0L
    val status: Long? get() = root.varint(100)
    val name: String get() = "$type/$subtype"

    fun matches(type: Long, vararg subtypes: Long): Boolean = this.type == type && subtypes.contains(subtype)

    companion object {
        const val AUTH = 1L
        const val SYSTEM = 2L
        const val WATCHFACE = 4L
        const val DATA_UPLOAD = 22L
        const val UPLOAD_TYPE_WATCHFACE = 16L

        private fun build(type: Long, subtype: Long, fill: (ProtoWriter) -> Unit = {}): ByteArray {
            val w = ProtoWriter()
            w.varint(1, type)
            w.varint(2, subtype)
            fill(w)
            return w.output
        }

        fun authPhoneNonce(nonce: ByteArray): ByteArray = build(AUTH, 26) { w ->
            w.message(3) { a -> a.message(30) { it.bytes(1, nonce) } }
        }

        fun authConfirm(confirmation: ByteArray, encryptedPhoneInfo: ByteArray): ByteArray = build(AUTH, 27) { w ->
            w.message(3) { a ->
                a.message(32) { m ->
                    m.bytes(1, confirmation)
                    m.bytes(2, encryptedPhoneInfo)
                }
            }
        }

        fun phoneInfo(model: String = "Android", region: String = "UK"): ByteArray {
            val w = ProtoWriter()
            w.varint(1, 0)
            w.float(2, 34.0f)
            w.string(3, model)
            w.varint(4, 224)
            w.string(5, region)
            return w.output
        }

        fun deviceInfoRequest(): ByteArray = build(SYSTEM, 2)
        fun batteryRequest(): ByteArray = build(SYSTEM, 1)
        fun watchfaceListRequest(): ByteArray = build(WATCHFACE, 0)

        fun activateWatchface(id: String): ByteArray = build(WATCHFACE, 1) { w -> w.message(6) { it.string(2, id) } }

        fun deleteWatchface(id: String): ByteArray = build(WATCHFACE, 2) { w -> w.message(6) { it.string(2, id) } }

        fun installRequest(id: String, size: Int): ByteArray = build(WATCHFACE, 4) { w ->
            w.message(6) { f ->
                f.message(6) { m ->
                    m.string(1, id)
                    m.varint(2, size.toLong())
                }
            }
        }

        fun uploadRequest(md5: ByteArray, size: Int, type: Long = UPLOAD_TYPE_WATCHFACE): ByteArray =
            build(DATA_UPLOAD, 0) { w ->
                w.message(24) { d ->
                    d.message(1) { m ->
                        m.varint(1, type)
                        m.bytes(2, md5)
                        m.varint(3, size.toLong())
                    }
                }
            }
    }
}

class WatchfaceEntry(val id: String, val isActive: Boolean, val canDelete: Boolean) {
    companion object {
        private fun from(m: ProtoMessage): WatchfaceEntry? {
            val id = m.string(1) ?: return null
            return WatchfaceEntry(id, m.bool(3) ?: false, m.bool(4) ?: false)
        }

        fun list(command: Command): List<WatchfaceEntry> {
            command.root.message(listOf(6, 1))?.let { c ->
                val e = c.messages(1).mapNotNull { from(it) }
                if (e.isNotEmpty()) return e
            }
            return command.root.message(6)?.messages(1)?.mapNotNull { from(it) } ?: emptyList()
        }
    }
}

class UploadResponse(command: Command) {
    val status: Long = command.root.varint(listOf(24, 2, 2)) ?: 0L
    val resumePosition: Int = (command.root.varint(listOf(24, 2, 4)) ?: 0L).toInt()
    val chunkSize: Int = (command.root.varint(listOf(24, 2, 5)) ?: 4096L).toInt()
}

object FileTransfer {
    private val streamHeader = bytesOf(0x00, 0x10)

    fun stream(file: ByteArray, md5: ByteArray, resumePosition: Int = 0): ByteArray {
        require(md5.size == 16)
        val start = resumePosition.coerceIn(0, file.size)
        val b = ByteBuilder().bytes(streamHeader).bytes(md5).le32(file.size.toLong()).bytes(file, start, file.size)
        val body = b.toByteArray()
        return ByteBuilder().bytes(body).le32(Checksum.crc32(body)).toByteArray()
    }

    fun parts(stream: ByteArray, chunkSize: Int): List<ByteArray> {
        require(chunkSize > 4)
        val partLength = chunkSize - 4
        val total = (stream.size + partLength - 1) / partLength
        require(total <= 0xFFFF) { "file too large for this chunk size" }
        val parts = ArrayList<ByteArray>(total)
        var offset = 0
        var index = 1
        while (offset < stream.size) {
            val end = minOf(offset + partLength, stream.size)
            parts.add(ByteBuilder().le16(total).le16(index).bytes(stream, offset, end).toByteArray())
            offset = end
            index++
        }
        return parts
    }

    fun parts(file: ByteArray, md5: ByteArray, resumePosition: Int, chunkSize: Int): List<ByteArray> =
        parts(stream(file, md5, resumePosition), chunkSize)
}
