// SPDX-License-Identifier: MIT

/// Підготовка файлу до передачі каналом 2.
///
/// Потік байтів: `00 10` | MD5 (16) | розмір LE32 | дані від позиції | CRC-32 LE32 усього попереднього.
/// Потік ріжуть на частини по (C − 4) байти; перед кожною — кількість частин LE16 і номер частини LE16 (з 1).
public enum FileTransfer {
    public static let streamHeader: [UInt8] = [0x00, 0x10]

    public static func stream(file: [UInt8], md5: [UInt8], resumePosition: Int = 0) -> [UInt8] {
        precondition(md5.count == 16)
        let start = min(max(resumePosition, 0), file.count)
        var out = streamHeader
        out.reserveCapacity(2 + 16 + 4 + (file.count - start) + 4)
        out.append(contentsOf: md5)
        out.appendLE32(UInt32(file.count))
        out.append(contentsOf: file[start...])
        out.appendLE32(Checksum.crc32(out))
        return out
    }

    /// Частини з 4-байтовим заголовком, готові до відправки як тіло кадру даних.
    public static func parts(stream: [UInt8], chunkSize: Int) -> [[UInt8]] {
        precondition(chunkSize > 4)
        let partLength = chunkSize - 4
        let total = (stream.count + partLength - 1) / partLength
        precondition(total <= Int(UInt16.max), "file too large for this chunk size")
        var parts: [[UInt8]] = []
        parts.reserveCapacity(total)
        var offset = 0
        var index = 1
        while offset < stream.count {
            let end = min(offset + partLength, stream.count)
            var part: [UInt8] = []
            part.reserveCapacity(4 + end - offset)
            part.appendLE16(UInt16(total))
            part.appendLE16(UInt16(index))
            part.append(contentsOf: stream[offset..<end])
            parts.append(part)
            offset = end
            index += 1
        }
        return parts
    }

    public static func parts(file: [UInt8], md5: [UInt8], resumePosition: Int, chunkSize: Int) -> [[UInt8]] {
        parts(stream: stream(file: file, md5: md5, resumePosition: resumePosition), chunkSize: chunkSize)
    }
}
