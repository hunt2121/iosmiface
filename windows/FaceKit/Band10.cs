// SPDX-License-Identifier: MIT
// Обмеження Xiaomi Smart Band 10 / 11, знайдені на справжніх циферблатах (Б-1: циферблат із фото-фоном зламав прошивку):
//  • у 11 циферблатах Band 10 (14 382 картинки) усі зображення — indexed8; RGB565A8 і RGBA32 не трапляються жодного разу;
//  • DataItemText немає в жодному з 400+ відомих циферблатів — на браслеті не перевірено.
// Тут: зменшення до 256 кольорів (разом із прозорістю), виправлення сховища перед збиранням і перелік ризиків.

using System;
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Faces
{
    public static class Band10
    {
        /// <summary>Картинка, що вміщається в indexed8 (≤ 256 різних RGBA). Якщо вже вміщається — та сама.
        /// Медіанний поділ у просторі R5 G5 B5 A3; майже прозорі пікселі (альфа &lt; 8) — один прозорий колір.</summary>
        public static RgbaImage To256(RgbaImage img)
        {
            var px = img.Px;
            int n = img.W * img.H;
            if (n == 0 || FaceCatalog.ColorCount(px) <= 256) return img;
            const int Bins = 1 << 18;
            var count = new long[Bins];
            var sr = new long[Bins]; var sg = new long[Bins]; var sb = new long[Bins]; var sa = new long[Bins];
            bool clear = false;
            for (int i = 0; i < n; i++)
            {
                int o = i * 4, a = px[o + 3];
                if (a < 8) { clear = true; continue; }
                int k = Key(px, o);
                count[k]++; sr[k] += px[o]; sg[k] += px[o + 1]; sb[k] += px[o + 2]; sa[k] += a;
            }
            var all = new List<int>();
            for (int k = 0; k < Bins; k++) if (count[k] > 0) all.Add(k);
            var boxes = new List<List<int>> { all };
            int colors = clear ? 255 : 256;
            while (boxes.Count < colors)
            {
                int best = -1, bestCh = 0;
                long bestScore = 0;
                for (int i = 0; i < boxes.Count; i++)
                {
                    var box = boxes[i];
                    if (box.Count <= 1) continue;
                    int[] lo = { 99, 99, 99, 99 }, hi = { -1, -1, -1, -1 };
                    long w = 0;
                    foreach (var k in box)
                    {
                        for (int c = 0; c < 4; c++) { int v = Ch(k, c); if (v < lo[c]) lo[c] = v; if (v > hi[c]) hi[c] = v; }
                        w += count[k];
                    }
                    int ch = 0, span = -1;
                    for (int c = 0; c < 4; c++)
                    {
                        // альфа має 8 рівнів проти 32 у кольорів — зважуємо, щоб її різниця важила так само
                        int s = (hi[c] - lo[c]) * (c == 3 ? 4 : 1);
                        if (s > span) { span = s; ch = c; }
                    }
                    long score = span * w;
                    if (score > bestScore) { bestScore = score; best = i; bestCh = ch; }
                }
                if (best < 0) break;
                int bc = bestCh;
                var sorted = boxes[best];
                sorted.Sort((x, y) => Ch(x, bc).CompareTo(Ch(y, bc)));
                long total = 0;
                foreach (var k in sorted) total += count[k];
                long acc = 0;
                int cut = 1;
                for (int j = 0; j < sorted.Count; j++)
                {
                    acc += count[sorted[j]];
                    if (acc * 2 >= total) { cut = Math.Max(1, Math.Min(sorted.Count - 1, j + 1)); break; }
                }
                boxes[best] = sorted.GetRange(0, cut);
                boxes.Add(sorted.GetRange(cut, sorted.Count - cut));
            }
            // середній колір кожного поділу
            var map = new int[Bins];
            var pal = new byte[boxes.Count * 4];
            for (int i = 0; i < boxes.Count; i++)
            {
                long r = 0, g = 0, b = 0, a = 0, w = 0;
                foreach (var k in boxes[i]) { r += sr[k]; g += sg[k]; b += sb[k]; a += sa[k]; w += count[k]; map[k] = i; }
                w = Math.Max(w, 1);
                pal[i * 4] = (byte)(r / w); pal[i * 4 + 1] = (byte)(g / w); pal[i * 4 + 2] = (byte)(b / w); pal[i * 4 + 3] = (byte)(a / w);
            }
            var outPx = new byte[px.Length];
            for (int i = 0; i < n; i++)
            {
                int o = i * 4;
                if (px[o + 3] < 8) continue;   // прозорий: 0,0,0,0
                int c = map[Key(px, o)] * 4;
                outPx[o] = pal[c]; outPx[o + 1] = pal[c + 1]; outPx[o + 2] = pal[c + 2]; outPx[o + 3] = pal[c + 3];
            }
            return new RgbaImage(img.W, img.H, outPx);
        }

        static int Key(byte[] p, int o) => (p[o] >> 3) << 13 | (p[o + 1] >> 3) << 8 | (p[o + 2] >> 3) << 3 | p[o + 3] >> 5;
        static int Ch(int k, int c) => c == 0 ? k >> 13 : c == 1 ? (k >> 8) & 31 : c == 2 ? (k >> 3) & 31 : k & 7;

        /// <summary>Перед збиранням для Band 10/11: кожне Image / ImageArray не у форматі indexed8 стає indexed8
        /// (картинки зменшуються до 256 кольорів). Змінює лише передане сховище. Повертає кількість виправлених ресурсів.</summary>
        public static int FixImages(MemoryStorage st)
        {
            if (!st.Files.TryGetValue("manifest.xml", out var xml)) return 0;
            var root = Xml.Parse(xml);
            var res = root?.First("Resources");
            if (res == null) return 0;
            int fixedCount = 0;
            foreach (var e in res.Elements)
            {
                if (e.Tag != "Image" && e.Tag != "ImageArray") continue;
                if (e.Str("format") == "indexed8") continue;
                var srcs = e.Tag == "Image" ? new List<string> { e.Str("src") } : e.All("Image").Select(i => i.Str("src")).ToList();
                foreach (var s in srcs.Where(x => x != null))
                {
                    var d = st.Read(s);
                    var img = d == null ? null : ImageDecoder.Decode(d);
                    if (img == null) continue;
                    st.Write(s, Png.Encode(img.W, img.H, To256(img).Px));
                }
                e.Set("format", "indexed8");
                fixedCount++;
            }
            if (fixedCount > 0) st.Files["manifest.xml"] = Xml.Print(root);
            return fixedCount;
        }

        /// <summary>Елементи, яких немає в жодному відомому циферблаті Band 10 (не перевірені на браслеті): назва тегу → кількість.</summary>
        public static Dictionary<string, int> Untested(XNode root)
        {
            var o = new Dictionary<string, int>();
            var res = root?.First("Resources");
            if (res == null) return o;
            foreach (var e in res.Elements)
                if (e.Tag == "DataItemText") o[e.Tag] = (o.TryGetValue(e.Tag, out var c) ? c : 0) + 1;
            return o;
        }
    }
}
