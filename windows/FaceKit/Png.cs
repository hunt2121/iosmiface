// SPDX-License-Identifier: MIT
// PNG без системних бібліотек, щоб результат був однаковим на будь-якій платформі:
// • запис — побайтово як у stb_image_write (його використовує exe): евристика фільтрів, власний deflate, quality 8;
// • читання — як stb_image з req_comp=4 (усі типи кольору, глибини 1–16, tRNS, Adam7, 16 біт → старший байт).

using System;
using System.Collections.Generic;
using System.Text;

namespace BandFace.Faces
{
    /// <summary>Картинка RGBA8888 без розмноження на альфу.</summary>
    public sealed class RgbaImage
    {
        public readonly int W, H;
        public readonly byte[] Px;
        public RgbaImage(int w, int h, byte[] px) { W = w; H = h; Px = px; }
    }

    public static class Png
    {
        static readonly uint[] CrcTable = MakeCrc();
        static uint[] MakeCrc()
        {
            var t = new uint[256];
            for (uint n = 0; n < 256; n++)
            {
                uint c = n;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
                t[n] = c;
            }
            return t;
        }
        static uint Crc32(byte[] a, byte[] b)
        {
            uint c = 0xFFFFFFFF;
            foreach (var x in a) c = CrcTable[(c ^ x) & 0xFF] ^ (c >> 8);
            foreach (var x in b) c = CrcTable[(c ^ x) & 0xFF] ^ (c >> 8);
            return c ^ 0xFFFFFFFF;
        }

        // MARK: Запис (stb_image_write)

        static readonly int[] Lengthc = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258, 259 };
        static readonly int[] Lengtheb = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
        static readonly int[] Distc = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577, 32768 };
        static readonly int[] Disteb = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };

        static int Zhash(byte[] d, int i)
        {
            uint h = unchecked(d[i] + ((uint)d[i + 1] << 8) + ((uint)d[i + 2] << 16));
            unchecked
            {
                h ^= h << 3; h += h >> 5;
                h ^= h << 4; h += h >> 17;
                h ^= h << 25; h += h >> 6;
            }
            return (int)(h & 16383);
        }
        static int Bitrev(int code, int n)
        {
            int r = 0, c = code;
            for (int i = 0; i < n; i++) { r = (r << 1) | (c & 1); c >>= 1; }
            return r;
        }
        static int Countm(byte[] d, int a, int b, int limit)
        {
            int lim = Math.Min(limit, 258), i = 0;
            while (i < lim && d[a + i] == d[b + i]) i++;
            return i;
        }

        sealed class BitOut
        {
            public readonly List<byte> O = new List<byte> { 0x78, 0x5E };
            uint buf; int cnt;
            public void Add(int code, int bits)
            {
                buf |= (uint)code << cnt; cnt += bits;
                while (cnt >= 8) { O.Add((byte)(buf & 0xFF)); buf >>= 8; cnt -= 8; }
            }
            public int Pending => cnt;
            void Huffa(int b, int c) => Add(Bitrev(b, c), c);
            public void Huff(int n)
            {
                if (n <= 143) Huffa(0x30 + n, 8);
                else if (n <= 255) Huffa(0x190 + n - 144, 9);
                else if (n <= 279) Huffa(n - 256, 7);
                else Huffa(0xC0 + n - 280, 8);
            }
            public void Huffb(int n) { if (n <= 143) Huffa(0x30 + n, 8); else Huffa(0x190 + n - 144, 9); }
        }

        public static byte[] ZlibCompress(byte[] data, int q = 8)
        {
            int quality = Math.Max(q, 5);
            var bo = new BitOut();
            bo.Add(1, 1); bo.Add(1, 2);
            var table = new List<int>[16384];
            int n = data.Length, i = 0;
            while (i < n - 3)
            {
                int h = Zhash(data, i);
                int best = 3, bestloc = -1;
                var bucket = table[h] ?? (table[h] = new List<int>());
                foreach (var p in bucket)
                {
                    if (p <= i - 32768) continue;
                    int d = Countm(data, p, i, n - i);
                    if (d >= best) { best = d; bestloc = p; }
                }
                if (bucket.Count == 2 * quality) bucket.RemoveRange(0, quality);
                bucket.Add(i);
                if (bestloc >= 0)
                {
                    var b2 = table[Zhash(data, i + 1)];
                    if (b2 != null)
                        foreach (var p in b2)
                        {
                            if (p <= i - 32767) continue;
                            int e = Countm(data, p, i + 1, n - i - 1);
                            if (e > best) { bestloc = -1; break; }
                        }
                }
                if (bestloc >= 0)
                {
                    int d = i - bestloc, j = 0;
                    while (best > Lengthc[j + 1] - 1) j++;
                    bo.Huff(j + 257);
                    if (Lengtheb[j] != 0) bo.Add(best - Lengthc[j], Lengtheb[j]);
                    j = 0;
                    while (d > Distc[j + 1] - 1) j++;
                    bo.Add(Bitrev(j, 5), 5);
                    if (Disteb[j] != 0) bo.Add(d - Distc[j], Disteb[j]);
                    i += best;
                }
                else { bo.Huffb(data[i]); i++; }
            }
            while (i < n) { bo.Huffb(data[i]); i++; }
            bo.Huff(256);
            while (bo.Pending != 0) bo.Add(0, 1);
            var o = bo.O;
            if (o.Count > n + 2 + ((n + 32766) / 32767) * 5)
            {
                o.RemoveRange(2, o.Count - 2);
                int j = 0;
                while (j < n)
                {
                    int bl = Math.Min(n - j, 32767);
                    o.Add((byte)(n - j == bl ? 1 : 0)); o.Add((byte)(bl & 0xFF)); o.Add((byte)(bl >> 8));
                    o.Add((byte)(~bl & 0xFF)); o.Add((byte)((~bl >> 8) & 0xFF));
                    for (int k = 0; k < bl; k++) o.Add(data[j + k]);
                    j += bl;
                }
            }
            uint s1 = 1, s2 = 0;
            int blk = n % 5552, jj = 0;
            while (jj < n)
            {
                for (int k = 0; k < blk; k++) { s1 += data[jj + k]; s2 += s1; }
                s1 %= 65521; s2 %= 65521; jj += blk; blk = 5552;
            }
            o.Add((byte)((s2 >> 8) & 0xFF)); o.Add((byte)(s2 & 0xFF)); o.Add((byte)((s1 >> 8) & 0xFF)); o.Add((byte)(s1 & 0xFF));
            return o.ToArray();
        }

        static int Paeth(int a, int b, int c)
        {
            int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
            if (pa <= pb && pa <= pc) return a & 0xFF;
            if (pb <= pc) return b & 0xFF;
            return c & 0xFF;
        }

        static readonly int[] FirstRow = { 0, 1, 0, 5, 6 };

        static void EncodeLine(byte[] px, int stride, int y, int n, int ftype, byte[] o)
        {
            int typ = y != 0 ? ftype : FirstRow[ftype];
            int z = y * stride;
            if (typ == 0) { Buffer.BlockCopy(px, z, o, 0, stride); return; }
            for (int i = 0; i < stride; i++)
            {
                int cur = px[z + i];
                int left = i >= n ? px[z + i - n] : 0;
                int up = (typ == 2 || typ == 3 || typ == 4) ? px[z + i - stride] : 0;
                int ul = (typ == 4 && i >= n) ? px[z + i - stride - n] : 0;
                int v;
                switch (typ)
                {
                    case 1: v = cur - left; break;
                    case 2: v = cur - up; break;
                    case 3: v = cur - ((left + up) >> 1); break;
                    case 4: v = cur - Paeth(left, up, ul); break;
                    case 5: v = cur - (left >> 1); break;
                    default: v = cur - Paeth(left, 0, 0); break;
                }
                o[i] = (byte)v;
            }
        }

        static byte[] Be32(uint v) => new[] { (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v };

        static void Chunk(List<byte> o, string t, byte[] d)
        {
            var tb = Encoding.ASCII.GetBytes(t);
            o.AddRange(Be32((uint)d.Length)); o.AddRange(tb); o.AddRange(d); o.AddRange(Be32(Crc32(tb, d)));
        }

        static readonly byte[] Signature = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

        /// <summary>RGBA8888 → PNG (точно як stbi_write_png з 4 каналами).</summary>
        public static byte[] Encode(int w, int h, byte[] rgba)
        {
            int n = 4, stride = w * n;
            var filt = new byte[(stride + 1) * h];
            var lines = new byte[5][];
            for (int f = 0; f < 5; f++) lines[f] = new byte[stride];
            int fo = 0;
            for (int y = 0; y < h; y++)
            {
                int best = 0, bestv = int.MaxValue;
                for (int f = 0; f < 5; f++)
                {
                    EncodeLine(rgba, stride, y, n, f, lines[f]);
                    int est = 0;
                    foreach (var b in lines[f]) est += b >= 128 ? 256 - b : b;
                    if (est < bestv) { bestv = est; best = f; }
                }
                filt[fo++] = (byte)best;
                Buffer.BlockCopy(lines[best], 0, filt, fo, stride); fo += stride;
            }
            var o = new List<byte>(Signature);
            Chunk(o, "IHDR", Bytes.Concat(Be32((uint)w), Be32((uint)h), new byte[] { 8, 6, 0, 0, 0 }));
            Chunk(o, "IDAT", ZlibCompress(filt, 8));
            Chunk(o, "IEND", new byte[0]);
            return o.ToArray();
        }

        /// <summary>Палітровий PNG (8 біт, тип 3): індекси w×h і палітра RGB (до 256 кольорів).</summary>
        public static byte[] EncodeIndexed(int w, int h, byte[] indices, byte[] palette)
        {
            var raw = new byte[(w + 1) * h];
            for (int y = 0; y < h; y++) Buffer.BlockCopy(indices, y * w, raw, y * (w + 1) + 1, w);
            var o = new List<byte>(Signature);
            int colors = Math.Max(1, Math.Min(256, palette.Length / 3));
            Chunk(o, "IHDR", Bytes.Concat(Be32((uint)w), Be32((uint)h), new byte[] { 8, 3, 0, 0, 0 }));
            Chunk(o, "PLTE", palette.Slice(0, colors * 3));
            Chunk(o, "IDAT", ZlibCompress(raw, 8));
            Chunk(o, "IEND", new byte[0]);
            return o.ToArray();
        }

        // MARK: Читання

        static int Be(byte[] d, int p) => d[p] << 24 | d[p + 1] << 16 | d[p + 2] << 8 | d[p + 3];

        public static RgbaImage Decode(byte[] d)
        {
            if (d == null || d.Length <= 8) return null;
            for (int i = 0; i < 8; i++) if (d[i] != Signature[i]) return null;
            int p = 8, w = 0, h = 0, depth = 0, ctype = 0, interlace = 0;
            byte[] pal = new byte[0], trns = new byte[0];
            var idat = new List<byte>();
            while (p + 8 <= d.Length)
            {
                int len = Be(d, p);
                string t = Encoding.ASCII.GetString(d, p + 4, 4);
                int s = p + 8;
                if (len < 0 || s + len > d.Length) return null;
                switch (t)
                {
                    case "IHDR":
                        if (len < 13) return null;
                        w = Be(d, s); h = Be(d, s + 4); depth = d[s + 8]; ctype = d[s + 9]; interlace = d[s + 12];
                        break;
                    case "PLTE": pal = d.Slice(s, len); break;
                    case "tRNS": trns = d.Slice(s, len); break;
                    case "IDAT": for (int k = 0; k < len; k++) idat.Add(d[s + k]); break;
                }
                if (t == "IEND") break;
                p = s + len + 4;
            }
            if (w <= 0 || h <= 0 || w >= 1 << 24 || h >= 1 << 24) return null;
            if (depth != 1 && depth != 2 && depth != 4 && depth != 8 && depth != 16) return null;
            int chans;
            switch (ctype) { case 0: chans = 1; break; case 2: chans = 3; break; case 3: chans = 1; break; case 4: chans = 2; break; case 6: chans = 4; break; default: return null; }
            if (idat.Count <= 2) return null;
            var raw = Inflate.Run(idat.GetRange(2, idat.Count - 2).ToArray());
            if (raw == null) return null;
            return new Decoder(w, h, depth, ctype, chans, pal, trns, raw).Run();
        }

        sealed class Decoder
        {
            readonly int w, h, depth, ctype, chans, bitsPP, bpp;
            readonly byte[] pal, trns, raw, rgba;
            int src;

            public Decoder(int w, int h, int depth, int ctype, int chans, byte[] pal, byte[] trns, byte[] raw)
            {
                this.w = w; this.h = h; this.depth = depth; this.ctype = ctype; this.chans = chans;
                this.pal = pal; this.trns = trns; this.raw = raw;
                bitsPP = chans * depth; bpp = Math.Max(1, bitsPP / 8);
                rgba = new byte[w * h * 4];
            }

            int Sample(byte[] row, int x, int c)
            {
                switch (depth)
                {
                    case 16: return row[(x * chans + c) * 2] << 8 | row[(x * chans + c) * 2 + 1];
                    case 8: return row[x * chans + c];
                    default:
                        int bit = (x * chans + c) * depth;
                        return (row[bit >> 3] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
                }
            }
            byte To8(int v)
            {
                switch (depth)
                {
                    case 16: return (byte)(v >> 8);
                    case 8: return (byte)v;
                    case 4: return (byte)(v * 0x11);
                    case 2: return (byte)(v * 0x55);
                    default: return (byte)(v * 0xFF);
                }
            }
            int TrnsKey(int c)
            {
                if (trns.Length == 0) return -1;
                int off = ctype == 0 ? 0 : c * 2;
                if (off + 1 >= trns.Length) return -1;
                return trns[off] << 8 | trns[off + 1];
            }
            void Put(byte[] row, int x, int o)
            {
                switch (ctype)
                {
                    case 0:
                    {
                        int v = Sample(row, x, 0);
                        byte g = To8(v);
                        rgba[o] = g; rgba[o + 1] = g; rgba[o + 2] = g;
                        rgba[o + 3] = TrnsKey(0) == v ? (byte)0 : (byte)255;
                        break;
                    }
                    case 2:
                    {
                        int r = Sample(row, x, 0), g = Sample(row, x, 1), b = Sample(row, x, 2);
                        rgba[o] = To8(r); rgba[o + 1] = To8(g); rgba[o + 2] = To8(b);
                        int kr = TrnsKey(0), kg = TrnsKey(1), kb = TrnsKey(2);
                        rgba[o + 3] = kr >= 0 && kg >= 0 && kb >= 0 && kr == r && kg == g && kb == b ? (byte)0 : (byte)255;
                        break;
                    }
                    case 3:
                    {
                        int i = Sample(row, x, 0);
                        rgba[o] = pal.U8(i * 3); rgba[o + 1] = pal.U8(i * 3 + 1); rgba[o + 2] = pal.U8(i * 3 + 2);
                        rgba[o + 3] = i < trns.Length ? trns[i] : (byte)255;
                        break;
                    }
                    case 4:
                    {
                        byte g = To8(Sample(row, x, 0));
                        rgba[o] = g; rgba[o + 1] = g; rgba[o + 2] = g; rgba[o + 3] = To8(Sample(row, x, 1));
                        break;
                    }
                    default:
                        for (int c = 0; c < 4; c++) rgba[o + c] = To8(Sample(row, x, c));
                        break;
                }
            }

            bool Pass(int x0, int y0, int dx, int dy)
            {
                int pw = (w - x0 + dx - 1) / dx, ph = (h - y0 + dy - 1) / dy;
                if (pw <= 0 || ph <= 0) return true;
                int stride = (pw * bitsPP + 7) / 8;
                var prev = new byte[stride];
                var cur = new byte[stride];
                for (int py = 0; py < ph; py++)
                {
                    if (src + 1 + stride > raw.Length) return false;
                    int f = raw[src]; src++;
                    for (int i = 0; i < stride; i++)
                    {
                        int x = raw[src + i];
                        int a = i >= bpp ? cur[i - bpp] : 0;
                        int b = prev[i];
                        int c = i >= bpp ? prev[i - bpp] : 0;
                        int v;
                        switch (f)
                        {
                            case 0: v = x; break;
                            case 1: v = x + a; break;
                            case 2: v = x + b; break;
                            case 3: v = x + ((a + b) >> 1); break;
                            case 4: v = x + Paeth(a, b, c); break;
                            default: return false;
                        }
                        cur[i] = (byte)v;
                    }
                    src += stride;
                    for (int px = 0; px < pw; px++) Put(cur, px, ((y0 + py * dy) * w + (x0 + px * dx)) * 4);
                    var t = prev; prev = cur; cur = t;
                }
                return true;
            }

            public RgbaImage Run()
            {
                if (raw == null) return null;
                if (interlace == 1)
                {
                    int[][] passes = { new[] { 0, 0, 8, 8 }, new[] { 4, 0, 8, 8 }, new[] { 0, 4, 4, 8 }, new[] { 2, 0, 4, 4 }, new[] { 0, 2, 2, 4 }, new[] { 1, 0, 2, 2 }, new[] { 0, 1, 1, 2 } };
                    foreach (var ps in passes) if (!Pass(ps[0], ps[1], ps[2], ps[3])) return null;
                }
                else if (!Pass(0, 0, 1, 1)) return null;
                return new RgbaImage(w, h, rgba);
            }
        }
    }

    /// <summary>Розпакування DEFLATE (RFC 1951).</summary>
    static class Inflate
    {
        sealed class Huff
        {
            public readonly int[] Counts = new int[16];
            public readonly int[] Symbols;
            public Huff(int[] lengths)
            {
                foreach (var l in lengths) Counts[l]++;
                Counts[0] = 0;
                var offs = new int[16];
                for (int i = 1; i < 16; i++) offs[i] = offs[i - 1] + Counts[i - 1];
                Symbols = new int[lengths.Length];
                for (int s = 0; s < lengths.Length; s++) if (lengths[s] != 0) Symbols[offs[lengths[s]]++] = s;
            }
        }

        static readonly int[] Lbase = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
        static readonly int[] Lext = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
        static readonly int[] Dbase = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
        static readonly int[] Dext = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
        static readonly int[] Order = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

        sealed class State
        {
            public byte[] Src; public int Pos, Buf, Cnt;
            /// <summary>-1 — кінець даних</summary>
            public int Bits(int n)
            {
                while (Cnt < n)
                {
                    if (Pos >= Src.Length) return -1;
                    Buf |= Src[Pos++] << Cnt; Cnt += 8;
                }
                int v = Buf & ((1 << n) - 1);
                Buf >>= n; Cnt -= n;
                return v;
            }
            public int Decode(Huff h)
            {
                int code = 0, first = 0, index = 0;
                for (int len = 1; len < 16; len++)
                {
                    int b = Bits(1);
                    if (b < 0) return -1;
                    code |= b;
                    int count = h.Counts[len];
                    if (code - count < first) return h.Symbols[index + (code - first)];
                    index += count; first += count; first <<= 1; code <<= 1;
                }
                return -1;
            }
        }

        public static byte[] Run(byte[] src)
        {
            var o = new List<byte>(src.Length * 4);
            var s = new State { Src = src };
            Huff fixedL = null, fixedD = null;
            while (true)
            {
                int last = s.Bits(1), type = s.Bits(2);
                if (last < 0 || type < 0) return null;
                if (type == 0)
                {
                    s.Buf = 0; s.Cnt = 0;
                    if (s.Pos + 4 > src.Length) return null;
                    int len = src[s.Pos] | src[s.Pos + 1] << 8;
                    s.Pos += 4;
                    if (s.Pos + len > src.Length) return null;
                    for (int k = 0; k < len; k++) o.Add(src[s.Pos + k]);
                    s.Pos += len;
                }
                else
                {
                    Huff lh, dh;
                    if (type == 1)
                    {
                        if (fixedL == null)
                        {
                            var l = new int[288];
                            for (int i = 0; i < 288; i++) l[i] = i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8;
                            fixedL = new Huff(l);
                            var dd = new int[30];
                            for (int i = 0; i < 30; i++) dd[i] = 5;
                            fixedD = new Huff(dd);
                        }
                        lh = fixedL; dh = fixedD;
                    }
                    else if (type == 2)
                    {
                        int hl = s.Bits(5), hd = s.Bits(5), hc = s.Bits(4);
                        if (hl < 0 || hd < 0 || hc < 0) return null;
                        var cl = new int[19];
                        for (int i = 0; i < hc + 4; i++) { int v = s.Bits(3); if (v < 0) return null; cl[Order[i]] = v; }
                        var ch = new Huff(cl);
                        var lens = new List<int>();
                        int total = hl + 257 + hd + 1;
                        while (lens.Count < total)
                        {
                            int sym = s.Decode(ch);
                            if (sym < 0) return null;
                            if (sym < 16) lens.Add(sym);
                            else if (sym == 16)
                            {
                                int r = s.Bits(2);
                                if (r < 0 || lens.Count == 0) return null;
                                int pv = lens[lens.Count - 1];
                                for (int k = 0; k < 3 + r; k++) lens.Add(pv);
                            }
                            else if (sym == 17) { int r = s.Bits(3); if (r < 0) return null; for (int k = 0; k < 3 + r; k++) lens.Add(0); }
                            else { int r = s.Bits(7); if (r < 0) return null; for (int k = 0; k < 11 + r; k++) lens.Add(0); }
                        }
                        if (lens.Count != total) return null;
                        lh = new Huff(lens.GetRange(0, hl + 257).ToArray());
                        dh = new Huff(lens.GetRange(hl + 257, total - hl - 257).ToArray());
                    }
                    else return null;
                    while (true)
                    {
                        int sym = s.Decode(lh);
                        if (sym < 0) return null;
                        if (sym < 256) { o.Add((byte)sym); continue; }
                        if (sym == 256) break;
                        int li = sym - 257;
                        if (li >= 29) return null;
                        int e = s.Bits(Lext[li]);
                        if (e < 0) return null;
                        int len = Lbase[li] + e;
                        int ds = s.Decode(dh);
                        if (ds < 0 || ds >= 30) return null;
                        int de = s.Bits(Dext[ds]);
                        if (de < 0) return null;
                        int dist = Dbase[ds] + de;
                        if (dist > o.Count) return null;
                        int start = o.Count - dist;
                        for (int k = 0; k < len; k++) o.Add(o[start + k]);
                    }
                }
                if (last == 1) break;
            }
            return o.ToArray();
        }
    }
}
