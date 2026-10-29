// SPDX-License-Identifier: MIT
using System.Collections.Generic;

namespace BandFace.Protocol
{
    public static class FrameType { public const int Ack = 1, Session = 2, Data = 3; }
    public static class DataChannel { public const int Protobuf = 1, File = 2; }
    public static class DataOpcode { public const int Plain = 1, Encrypted = 2; }

    /// <summary>Кадр: A5 A5 | тип | номер | довжина LE16 | CRC-16 LE16 | навантаження.</summary>
    public sealed class Frame
    {
        public const int HeaderLength = 8;
        public const int MaxPayload = 0xFC00;
        public int Type { get; }
        public int Sequence { get; }
        public byte[] Payload { get; }

        public Frame(int type, int sequence, byte[] payload = null)
        {
            Type = type; Sequence = sequence; Payload = payload ?? new byte[0];
        }

        public static Frame Ack(int sequence) => new Frame(FrameType.Ack, sequence);

        public byte[] Encoded() =>
            new ByteBuilder().U8(0xA5).U8(0xA5).U8(Type).U8(Sequence).Le16(Payload.Length)
                .Le16(Payload.Length == 0 ? 0 : Checksum.Crc16(Payload)).Add(Payload).ToArray();
    }

    /// <summary>Збирає цілі кадри зі сповіщень BLE.</summary>
    public sealed class FrameParser
    {
        byte[] _buf = new byte[0];

        public void Reset() => _buf = new byte[0];

        public List<Frame> Append(byte[] bytes)
        {
            _buf = Bytes.Concat(_buf, bytes);
            var frames = new List<Frame>();
            while (true)
            {
                int start = Preamble();
                if (start < 0)
                {
                    _buf = _buf.Length > 0 && _buf[_buf.Length - 1] == 0xA5 ? new byte[] { 0xA5 } : new byte[0];
                    break;
                }
                if (start > 0) _buf = _buf.Slice(start, _buf.Length);
                if (_buf.Length < Frame.HeaderLength) break;
                int len = _buf.U16(4);
                if (len > Frame.MaxPayload) { _buf = _buf.Slice(1, _buf.Length); continue; }
                if (_buf.Length < Frame.HeaderLength + len) break;
                var payload = _buf.Slice(Frame.HeaderLength, Frame.HeaderLength + len);
                int crc = _buf.U16(6);
                int expected = payload.Length == 0 ? 0 : Checksum.Crc16(payload);
                if (crc != expected) { _buf = _buf.Slice(1, _buf.Length); continue; }
                int type = _buf[2] & 0x0F, seq = _buf[3];
                _buf = _buf.Slice(Frame.HeaderLength + len, _buf.Length);
                if (type >= 1 && type <= 3) frames.Add(new Frame(type, seq, payload));
            }
            return frames;
        }

        int Preamble()
        {
            for (int i = 0; i + 1 < _buf.Length; i++) if (_buf[i] == 0xA5 && _buf[i + 1] == 0xA5) return i;
            return -1;
        }
    }

    public sealed class DataPacket
    {
        public int Channel { get; }
        public int Opcode { get; }
        public byte[] Body { get; }
        public DataPacket(int channel, int opcode, byte[] body) { Channel = channel; Opcode = opcode; Body = body; }
        public byte[] Payload => new ByteBuilder().U8(Channel).U8(Opcode).Add(Body).ToArray();

        public static DataPacket Parse(byte[] p) =>
            p.Length < 2 ? null : new DataPacket(p[0] & 0x0F, p[1], p.Slice(2, p.Length));
    }

    /// <summary>Керування сесією: код + параметри TLV (ключ, довжина LE16, значення).</summary>
    public sealed class SessionControl
    {
        public const int OpenRequest = 1, OpenResponse = 2, CloseRequest = 3, CloseResponse = 4;
        public int Code { get; }
        public List<KeyValuePair<int, byte[]>> Parameters { get; }

        public SessionControl(int code, List<KeyValuePair<int, byte[]>> parameters = null)
        {
            Code = code;
            Parameters = parameters ?? new List<KeyValuePair<int, byte[]>>();
        }

        public byte[] Payload
        {
            get
            {
                var b = new ByteBuilder().U8(Code);
                foreach (var p in Parameters) b.U8(p.Key).Le16(p.Value.Length).Add(p.Value);
                return b.ToArray();
            }
        }

        public static SessionControl Parse(byte[] p)
        {
            if (p.Length == 0) return null;
            var list = new List<KeyValuePair<int, byte[]>>();
            int i = 1;
            while (i + 3 <= p.Length)
            {
                int key = p[i], len = p.U16(i + 1);
                i += 3;
                if (i + len > p.Length) return null;
                list.Add(new KeyValuePair<int, byte[]>(key, p.Slice(i, i + len)));
                i += len;
            }
            return new SessionControl(p[0], list);
        }

        static KeyValuePair<int, byte[]> Kv(int k, params byte[] v) => new KeyValuePair<int, byte[]>(k, v);

        /// <summary>Перевірений на Band 10: версія 1.0.0, кадр 0xFC00, вікно 32, тайм-аут 10000 мс.</summary>
        public static SessionControl DefaultOpen() => new SessionControl(OpenRequest, new List<KeyValuePair<int, byte[]>>
        {
            Kv(1, 0x01, 0x00, 0x00), Kv(2, 0x00, 0xFC), Kv(3, 0x20, 0x00), Kv(4, 0x10, 0x27),
        });

        public static SessionControl Close() => new SessionControl(CloseRequest);
    }
}
