// SPDX-License-Identifier: MIT
using System;
using System.IO;
using System.Text;

namespace BandFace.Protocol
{
    public sealed class FaceFile
    {
        public byte[] Data { get; }
        public string Id { get; }
        public string Name { get; }
        public int? PreviewOffset { get; }
        public int Size => Data.Length;
        public byte[] Md5 => BandCrypto.Md5(Data);

        public FaceFile(byte[] data)
        {
            if (data.Length < 0x7C) throw new BandException(ErrorKind.InvalidFaceFile, "file too short");
            if (data[0] != 0x5A || data[1] != 0xA5) throw new BandException(ErrorKind.InvalidFaceFile, "bad signature");
            Data = data;
            var idBytes = ZeroTerminated(data, 0x28, 0x40);
            if (idBytes.Length == 0) throw new BandException(ErrorKind.InvalidFaceFile, "bad watchface id");
            foreach (var b in idBytes) if (b < 0x30 || b > 0x39) throw new BandException(ErrorKind.InvalidFaceFile, "bad watchface id");
            Id = Encoding.ASCII.GetString(idBytes);
            if (data.U32(0x68) == 0xFFFFFFFFL) Name = null;
            else
            {
                var n = Encoding.UTF8.GetString(ZeroTerminated(data, 0x68, 0x40));
                Name = n.Length == 0 ? null : n;
            }
            long off = data.U32(0x20);
            PreviewOffset = (off <= 0 || off + 12 > data.Length) ? (int?)null : (int)off;
        }

        static byte[] ZeroTerminated(byte[] b, int from, int max)
        {
            int end = Math.Min(from + max, b.Length), i = from;
            while (i < end && b[i] != 0) i++;
            return b.Slice(from, i);
        }

        public Preview DecodePreview() => PreviewOffset.HasValue ? Preview.Decode(Data, PreviewOffset.Value) : null;
    }

    /// <summary>Розпаковане зображення: пікселі BGRA (Bgra32 у WPF).</summary>
    public sealed class Preview
    {
        public int Width, Height;
        public byte[] Bgra;

        public static Preview Decode(byte[] d, int off)
        {
            if (off + 12 > d.Length) throw new BandException(ErrorKind.InvalidPreview, "header out of range");
            int format = d[off], comp = d[off + 1];
            if (format != 0 && format != 1 && format != 4 && format != 7 && format != 16) throw new BandException(ErrorKind.InvalidPreview, "pixel format");
            if (comp != 0 && comp != 4 && comp != 8) throw new BandException(ErrorKind.InvalidPreview, "compression");
            int w = d.U16(off + 4), h = d.U16(off + 6);
            long size = d.U32(off + 8);
            int start = off + 12;
            if (w <= 0 || h <= 0 || w > 4096 || h > 4096) throw new BandException(ErrorKind.InvalidPreview, "bad dimensions");
            if (start + size > d.Length) throw new BandException(ErrorKind.InvalidPreview, "data out of range");
            var raw = d.Slice(start, start + (int)size);
            if (comp == 8) raw = Rle.Decode(raw, true);
            else if (comp == 4) raw = Rle.Decode(raw, false);
            return FromRaw(raw, format, w, h);
        }

        static Preview FromRaw(byte[] raw, int format, int w, int h)
        {
            int n = w * h;
            var o = new byte[n * 4];
            Action<int, int> p565 = (i, v) =>
            {
                int r = (v >> 11) & 0x1F, g = (v >> 5) & 0x3F, b = v & 0x1F;
                o[i * 4] = (byte)((b << 3) | (b >> 2)); o[i * 4 + 1] = (byte)((g << 2) | (g >> 4));
                o[i * 4 + 2] = (byte)((r << 3) | (r >> 2)); o[i * 4 + 3] = 0xFF;
            };
            if (format == 0)
            {
                if (raw.Length < n * 4) throw new BandException(ErrorKind.InvalidPreview, "not enough pixel data");
                Buffer.BlockCopy(raw, 0, o, 0, n * 4);
            }
            else if (format == 1 || format == 4 || format == 7)
            {
                if (raw.Length < n * 2) throw new BandException(ErrorKind.InvalidPreview, "not enough pixel data");
                for (int i = 0; i < n; i++) p565(i, format == 7 ? (raw[i * 2] << 8) | raw[i * 2 + 1] : raw[i * 2] | (raw[i * 2 + 1] << 8));
            }
            else
            {
                if (raw.Length < 1024 + n) throw new BandException(ErrorKind.InvalidPreview, "not enough pixel data");
                for (int i = 0; i < n; i++) Buffer.BlockCopy(raw, raw[1024 + i] * 4, o, i * 4, 4);
            }
            return new Preview { Width = w, Height = h, Bgra = o };
        }
    }

    public static class Rle
    {
        public static byte[] Decode(byte[] d, bool runIsHigh)
        {
            if (d.Length < 8 || d[0] != 0xE0 || d[1] != 0x21 || d[2] != 0xA5 || d[3] != 0x5A) throw new BandException(ErrorKind.InvalidPreview, "bad RLE header");
            long word = d.U32(4);
            int elem = Math.Max((int)(word & 0x0F), 1);
            int total = (int)(word >> 4);
            var o = new MemoryStream(total);
            int i = 8;
            while (i < d.Length && o.Length < total)
            {
                int c = d[i++];
                bool high = (c & 0x80) != 0;
                int n = c & 0x7F;
                bool run = runIsHigh ? high : !high;
                int count = runIsHigh ? n + 1 : n;
                if (run)
                {
                    if (i + elem > d.Length) throw new BandException(ErrorKind.InvalidPreview, "truncated RLE");
                    for (int k = 0; k < count; k++) o.Write(d, i, elem);
                    i += elem;
                }
                else
                {
                    int len = count * elem;
                    if (i + len > d.Length) throw new BandException(ErrorKind.InvalidPreview, "truncated RLE");
                    o.Write(d, i, len);
                    i += len;
                }
            }
            var r = o.ToArray();
            return r.Length > total ? r.Slice(0, total) : r;
        }
    }
}
