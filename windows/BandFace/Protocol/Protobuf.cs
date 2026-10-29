// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace BandFace.Protocol
{
    public enum Wire { Varint = 0, Fixed64 = 1, Bytes = 2, Fixed32 = 5 }

    public sealed class ProtoField
    {
        public int Number;
        public Wire Type;
        public long Varint;
        public byte[] Data;
    }

    public sealed class ProtoWriter
    {
        readonly MemoryStream _o = new MemoryStream();
        public byte[] Output => _o.ToArray();

        void Varint(ulong v)
        {
            while (v >= 0x80) { _o.WriteByte((byte)((v & 0x7F) | 0x80)); v >>= 7; }
            _o.WriteByte((byte)v);
        }

        void Tag(int f, int w) => Varint(((ulong)f << 3) | (ulong)w);

        public ProtoWriter WriteVarint(int f, long v) { Tag(f, 0); Varint((ulong)v); return this; }
        public ProtoWriter WriteBytes(int f, byte[] v) { Tag(f, 2); Varint((ulong)v.Length); _o.Write(v, 0, v.Length); return this; }
        public ProtoWriter WriteString(int f, string v) => WriteBytes(f, Encoding.UTF8.GetBytes(v));
        public ProtoWriter WriteFloat(int f, float v)
        {
            Tag(f, 5);
            var b = BitConverter.GetBytes(v);
            if (!BitConverter.IsLittleEndian) Array.Reverse(b);
            _o.Write(b, 0, 4);
            return this;
        }
        public ProtoWriter WriteMessage(int f, Action<ProtoWriter> build)
        {
            var n = new ProtoWriter();
            build(n);
            return WriteBytes(f, n.Output);
        }
    }

    public sealed class ProtoMessage
    {
        public List<ProtoField> Fields { get; } = new List<ProtoField>();

        public static ProtoMessage Parse(byte[] data)
        {
            var m = new ProtoMessage();
            int i = 0;
            Func<long> varint = () =>
            {
                ulong r = 0; int shift = 0;
                while (true)
                {
                    if (i >= data.Length || shift >= 64) throw new BandException(ErrorKind.MalformedProtobuf);
                    byte b = data[i++];
                    r |= (ulong)(b & 0x7F) << shift;
                    if ((b & 0x80) == 0) return (long)r;
                    shift += 7;
                }
            };
            while (i < data.Length)
            {
                long key = varint();
                int number = (int)((ulong)key >> 3);
                if (number <= 0) throw new BandException(ErrorKind.MalformedProtobuf);
                switch ((int)(key & 7))
                {
                    case 0: m.Fields.Add(new ProtoField { Number = number, Type = Wire.Varint, Varint = varint() }); break;
                    case 1:
                        if (i + 8 > data.Length) throw new BandException(ErrorKind.MalformedProtobuf);
                        m.Fields.Add(new ProtoField { Number = number, Type = Wire.Fixed64, Data = data.Slice(i, i + 8) }); i += 8; break;
                    case 2:
                        long len = varint();
                        if (len < 0 || len > data.Length - i) throw new BandException(ErrorKind.MalformedProtobuf);
                        m.Fields.Add(new ProtoField { Number = number, Type = Wire.Bytes, Data = data.Slice(i, i + (int)len) }); i += (int)len; break;
                    case 5:
                        if (i + 4 > data.Length) throw new BandException(ErrorKind.MalformedProtobuf);
                        m.Fields.Add(new ProtoField { Number = number, Type = Wire.Fixed32, Data = data.Slice(i, i + 4) }); i += 4; break;
                    default: throw new BandException(ErrorKind.MalformedProtobuf);
                }
            }
            return m;
        }

        ProtoField First(int n) => Fields.FirstOrDefault(f => f.Number == n);

        public long? Varint(int n) { var f = First(n); return f != null && f.Type == Wire.Varint ? f.Varint : (long?)null; }
        public bool? Bool(int n) { var v = Varint(n); return v.HasValue ? v.Value != 0 : (bool?)null; }
        public byte[] Bytes(int n) { var f = First(n); return f != null && f.Type == Wire.Bytes ? f.Data : null; }
        public string String(int n) { var b = Bytes(n); return b == null ? null : Encoding.UTF8.GetString(b); }

        public ProtoMessage Message(int n)
        {
            var b = Bytes(n);
            if (b == null) return null;
            try { return Parse(b); } catch (BandException) { return null; }
        }

        public List<ProtoMessage> Messages(int n)
        {
            var r = new List<ProtoMessage>();
            foreach (var f in Fields.Where(x => x.Number == n && x.Type == Wire.Bytes))
            {
                try { r.Add(Parse(f.Data)); } catch (BandException) { }
            }
            return r;
        }

        ProtoMessage Walk(int[] path, int count)
        {
            ProtoMessage cur = this;
            for (int k = 0; k < count && cur != null; k++) cur = cur.Message(path[k]);
            return cur;
        }

        public long? VarintAt(params int[] path) => Walk(path, path.Length - 1)?.Varint(path[path.Length - 1]);
        public byte[] BytesAt(params int[] path) => Walk(path, path.Length - 1)?.Bytes(path[path.Length - 1]);
        public ProtoMessage MessageAt(params int[] path) => Walk(path, path.Length);
    }
}
