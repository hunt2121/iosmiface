// SPDX-License-Identifier: MIT
// RLE «RLEReversed» і формати пікселів (порт кодеків зображень WatchfaceCompiler).

using System;
using System.Collections.Generic;

namespace BandFace.Faces
{
    static class Rle
    {
        public const uint Magic = 0x5AA521E0;

        /// <summary>Розпакування: c&amp;0x80 — c&amp;0x7F літеральних елементів, інакше повтор елемента c&amp;0x7F разів.</summary>
        public static byte[] Decompress(byte[] src, int start, int outSize, int E)
        {
            var o = new List<byte>(outSize);
            int i = start, n = src.Length;
            while (i < n)
            {
                int c = src[i]; i++;
                int k = c & 0x7F;
                if ((c & 0x80) != 0)
                {
                    int m = k * E;
                    o.AddRange(src.Slice(i, Math.Min(m, Math.Max(0, n - i))));
                    i += m;
                }
                else
                {
                    if (k > 0)
                    {
                        var el = src.Slice(i, E);
                        for (int r = 0; r < k; r++) o.AddRange(el);
                    }
                    i += E;
                }
            }
            var res = new byte[outSize];
            for (int j = 0; j < outSize && j < o.Count; j++) res[j] = o[j];
            return res;
        }

        static bool Eq(byte[] s, int a, int b, int E)
        {
            int n = s.Length;
            for (int k = 0; k < E; k++)
            {
                int x = a + k < n ? s[a + k] : -1;
                int y = b + k < n ? s[b + k] : -1;
                if (x != y) return false;
            }
            return true;
        }

        /// <summary>Точний порт стискача exe (мінімальна серія 5, максимум 127).</summary>
        public static byte[] Compress(byte[] src, int E, int minRun = 5)
        {
            int n = src.Length;
            var o = new List<byte>();
            int pos = 0;
            if (n == 0) return o.ToArray();
            while (pos < n)
            {
                if (n < E) break;
                int run = 0, off = 0;
                if (pos < n)
                {
                    while (true)
                    {
                        if (!Eq(src, pos + off, pos, E)) break;
                        run++;
                        if (run == 0x7F) break;
                        off += E;
                        if (off + pos >= n) break;
                    }
                }
                if (run == 0) break;
                if (run < minRun)
                {
                    int r14 = 0, cnt = 0, eqc = 0, prev = pos;
                    while (true)
                    {
                        int cur = pos + r14;
                        eqc++;
                        if (Eq(src, cur, prev, E))
                        {
                            if (eqc > minRun) break;
                        }
                        else
                        {
                            cnt += eqc; prev = cur; eqc = 0;
                            if (cnt >= 0x7F) { cnt = 0x7F; break; }
                        }
                        r14 += E;
                        if (r14 + pos >= n)
                        {
                            cnt += eqc;
                            if (cnt >= 0x7F) cnt = 0x7F;
                            break;
                        }
                    }
                    o.Add((byte)((cnt & 0x7F) | 0x80));
                    o.AddRange(src.Slice(pos, Math.Min(cnt * E, n - pos)));
                    pos += cnt * E;
                }
                else
                {
                    o.Add((byte)run);
                    o.AddRange(src.Slice(pos, Math.Min(E, n - pos)));
                    pos += run * E;
                }
            }
            return o.ToArray();
        }

        /// <summary>Блок «E0 21 A5 5A, (E | size&lt;&lt;4), потік».</summary>
        public static byte[] Block(byte[] raw, int E)
        {
            var w = new ByteWriter();
            w.U32(Magic);
            w.U32(((uint)E & 0xF) | (((uint)raw.Length << 4) & 0x0FFFFFFF));
            w.Append(Compress(raw, E));
            return w.ToArray();
        }
    }

    /// <summary>Формати пікселів: 0 — RGBA32 (BGRA у файлі), 6 — RGB565A8, 0x10 — indexed8.</summary>
    public static class PixelFormat
    {
        public static string Name(byte f) => f == 0 ? "RGBA32" : f == 6 ? "RGB565A8" : f == 0x10 ? "indexed8" : null;
        public static int Bpp(byte f) => f == 0 ? 4 : (f == 6 ? 3 : 1);

        /// <summary>Сирі дані → RGBA8888.</summary>
        public static byte[] Decode(byte fmt, byte[] raw, int w, int h)
        {
            int n = w * h;
            var o = new byte[n * 4];
            switch (fmt)
            {
                case 0:
                    for (int i = 0; i < n; i++)
                    {
                        o[i * 4] = raw.U8(i * 4 + 2); o[i * 4 + 1] = raw.U8(i * 4 + 1);
                        o[i * 4 + 2] = raw.U8(i * 4); o[i * 4 + 3] = raw.U8(i * 4 + 3);
                    }
                    break;
                case 6:
                    for (int i = 0; i < n; i++)
                    {
                        int v = raw.U16(i * 3);
                        int r5 = v >> 11, g6 = (v >> 5) & 0x3F, b5 = v & 0x1F;
                        o[i * 4] = (byte)((r5 * 255 + 15) / 31);
                        o[i * 4 + 1] = (byte)((g6 * 255 + 31) / 63);
                        o[i * 4 + 2] = (byte)((b5 * 255 + 15) / 31);
                        o[i * 4 + 3] = raw.U8(i * 3 + 2);
                    }
                    break;
                case 0x10:
                    for (int i = 0; i < n; i++)
                    {
                        int p = raw.U8(1024 + i) * 4;
                        o[i * 4] = raw.U8(p + 2); o[i * 4 + 1] = raw.U8(p + 1);
                        o[i * 4 + 2] = raw.U8(p); o[i * 4 + 3] = raw.U8(p + 3);
                    }
                    break;
                default:
                    throw new FaceCompilerException("Unknown color format: " + fmt + " (" + Num.HexUpper(fmt, 2) + ")");
            }
            return o;
        }

        /// <summary>RGBA8888 → сирі дані формату.</summary>
        public static byte[] Encode(byte fmt, byte[] rgba, int w, int h)
        {
            int n = w * h;
            switch (fmt)
            {
                case 0:
                {
                    var o = new byte[n * 4];
                    for (int i = 0; i < n; i++)
                    {
                        o[i * 4] = rgba[i * 4 + 2]; o[i * 4 + 1] = rgba[i * 4 + 1];
                        o[i * 4 + 2] = rgba[i * 4]; o[i * 4 + 3] = rgba[i * 4 + 3];
                    }
                    return o;
                }
                case 6:
                {
                    var o = new byte[n * 3];
                    for (int i = 0; i < n; i++)
                    {
                        int r = (int)(rgba[i * 4] * 31.0 / 255.0);
                        int g = (int)(rgba[i * 4 + 1] * 63.0 / 255.0);
                        int b = (int)(rgba[i * 4 + 2] * 31.0 / 255.0);
                        int v = ((r << 6 | g) << 5 | b) & 0xFFFF;
                        o[i * 3] = (byte)(v & 0xFF); o[i * 3 + 1] = (byte)(v >> 8); o[i * 3 + 2] = rgba[i * 4 + 3];
                    }
                    return o;
                }
                case 0x10:
                {
                    var index = new Dictionary<uint, int>();
                    var cols = new List<uint>();
                    var idx = new byte[n];
                    for (int i = 0; i < n; i++)
                    {
                        uint c = rgba[i * 4] | (uint)rgba[i * 4 + 1] << 8 | (uint)rgba[i * 4 + 2] << 16 | (uint)rgba[i * 4 + 3] << 24;
                        if (index.TryGetValue(c, out var k)) { idx[i] = (byte)k; continue; }
                        if (cols.Count >= 256) throw new FaceCompilerException("Image has more than 256 colors!");
                        index[c] = cols.Count; idx[i] = (byte)cols.Count; cols.Add(c);
                    }
                    var pal = new byte[1024];
                    for (int k = 0; k < cols.Count; k++)
                    {
                        uint c = cols[k];
                        pal[k * 4] = (byte)((c >> 16) & 0xFF); pal[k * 4 + 1] = (byte)((c >> 8) & 0xFF);
                        pal[k * 4 + 2] = (byte)(c & 0xFF); pal[k * 4 + 3] = (byte)(c >> 24);
                    }
                    return Bytes.Concat(pal, idx);
                }
                default:
                    throw new FaceCompilerException("Unknown color format: " + fmt + " (" + Num.HexUpper(fmt, 2) + ")");
            }
        }
    }
}
