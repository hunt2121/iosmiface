// SPDX-License-Identifier: MIT
// Протокол встановлення циферблатів на Xiaomi Smart Band 10 (порт BandFaceKit).
using System;
using System.IO;
using System.Text;

namespace BandFace.Protocol
{
    public enum ErrorKind
    {
        Timeout, NotConnected, CharacteristicNotFound, SessionOpenFailed, SessionNotOpen, NotAuthenticated,
        InvalidAuthKey, AuthKeyMismatch, MalformedResponse, MalformedProtobuf, InstallRejected, UploadRejected,
        InstallAborted, ActivationFailed, InvalidFaceFile, InvalidPreview, Cancelled, Disconnected,
    }

    public sealed class BandException : Exception
    {
        public ErrorKind Kind { get; }
        public long Status { get; }
        public BandException(ErrorKind kind, string detail = "", long status = 0) : base(kind + " " + detail)
        {
            Kind = kind;
            Status = status;
        }
    }

    public static class Bytes
    {
        public static int U16(this byte[] b, int i) => b[i] | (b[i + 1] << 8);
        public static long U32(this byte[] b, int i) =>
            b[i] | ((long)b[i + 1] << 8) | ((long)b[i + 2] << 16) | ((long)b[i + 3] << 24);

        public static byte[] Concat(params byte[][] parts)
        {
            int n = 0;
            foreach (var p in parts) n += p.Length;
            var r = new byte[n];
            int o = 0;
            foreach (var p in parts) { Buffer.BlockCopy(p, 0, r, o, p.Length); o += p.Length; }
            return r;
        }

        public static byte[] Slice(this byte[] b, int from, int to)
        {
            var r = new byte[to - from];
            Buffer.BlockCopy(b, from, r, 0, r.Length);
            return r;
        }

        public static string Hex(this byte[] b)
        {
            var sb = new StringBuilder(b.Length * 3);
            foreach (var x in b) sb.Append(x.ToString("X2")).Append(' ');
            return sb.ToString().TrimEnd();
        }

        public static bool ConstantTimeEqual(byte[] a, byte[] b)
        {
            if (a.Length != b.Length) return false;
            int d = 0;
            for (int i = 0; i < a.Length; i++) d |= a[i] ^ b[i];
            return d == 0;
        }

        /// <summary>Шістнадцятковий рядок → байти; пробіли, «:» і «-» ігноруються.</summary>
        public static byte[] ParseHex(string s)
        {
            s = s.Trim();
            if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) s = s.Substring(2);
            var sb = new StringBuilder();
            foreach (var c in s) if (c != ' ' && c != ':' && c != '-') sb.Append(c);
            s = sb.ToString();
            if (s.Length % 2 != 0) return null;
            var r = new byte[s.Length / 2];
            for (int i = 0; i < r.Length; i++)
            {
                int hi = HexVal(s[i * 2]), lo = HexVal(s[i * 2 + 1]);
                if (hi < 0 || lo < 0) return null;
                r[i] = (byte)((hi << 4) | lo);
            }
            return r;
        }

        static int HexVal(char c) =>
            c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;

        public static string ToHexLower(byte[] b)
        {
            var sb = new StringBuilder();
            foreach (var x in b) sb.Append(x.ToString("x2"));
            return sb.ToString();
        }
    }

    public sealed class ByteBuilder
    {
        readonly MemoryStream _s = new MemoryStream();
        public ByteBuilder U8(int v) { _s.WriteByte((byte)v); return this; }
        public ByteBuilder Le16(int v) { _s.WriteByte((byte)v); _s.WriteByte((byte)(v >> 8)); return this; }
        public ByteBuilder Le32(long v) { for (int i = 0; i < 32; i += 8) _s.WriteByte((byte)(v >> i)); return this; }
        public ByteBuilder Add(byte[] b) { _s.Write(b, 0, b.Length); return this; }
        public ByteBuilder Add(byte[] b, int from, int to) { _s.Write(b, from, to - from); return this; }
        public byte[] ToArray() => _s.ToArray();
    }

    public static class Checksum
    {
        /// <summary>CRC-16/ARC.</summary>
        public static int Crc16(byte[] data)
        {
            int crc = 0;
            foreach (var b in data)
            {
                crc ^= b;
                for (int i = 0; i < 8; i++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
            }
            return crc & 0xFFFF;
        }

        static readonly uint[] Table = MakeTable();
        static uint[] MakeTable()
        {
            var t = new uint[256];
            for (uint i = 0; i < 256; i++)
            {
                uint c = i;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                t[i] = c;
            }
            return t;
        }

        /// <summary>CRC-32 (IEEE, як у ZIP).</summary>
        public static long Crc32(byte[] data)
        {
            uint crc = 0xFFFFFFFFu;
            foreach (var b in data) crc = Table[(crc ^ b) & 0xFF] ^ (crc >> 8);
            return (long)(crc ^ 0xFFFFFFFFu);
        }
    }
}
