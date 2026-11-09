// SPDX-License-Identifier: MIT
// Приглушення «Завжди на екрані»: чорний напівпрозорий шар на весь екран поверх усіх елементів AOD
// (так зроблено і в готових циферблатах, напр. BigWatch: 212×520, прозорість 84 з 255 ≈ 33 %).

using System;
using System.Linq;
using System.Runtime.CompilerServices;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class AodDim
    {
        public const int AodTheme = 1;
        sealed class Box { public int Alpha; }
        static readonly ConditionalWeakTable<byte[], Box> cache = new ConditionalWeakTable<byte[], Box>();

        /// <summary>Прозорість (1…254) шару-приглушення або 0, якщо шар — не приглушення</summary>
        public static int AlphaOf(FaceProject p, XNode layout)
        {
            if (layout == null || layout.Int("x") != 0 || layout.Int("y") != 0) return 0;
            var res = p.ElementOf(layout);
            if (res == null || res.Tag != "Image") return 0;
            var data = p.File(res.Str("src"));
            if (data == null) return 0;
            var b = cache.GetValue(data, d => new Box { Alpha = Measure(d, p.Meta.Device.Width, p.Meta.Device.Height) });
            return b.Alpha;
        }

        static int Measure(byte[] data, int w, int h)
        {
            try
            {
                var img = Imaging.Decode(data);
                if (img.W < w || img.H < h) return 0;
                int a = img.Px[3];
                if (a == 0 || a == 255) return 0;
                for (int i = 0; i < img.Px.Length; i += 4)
                    if (img.Px[i] > 8 || img.Px[i + 1] > 8 || img.Px[i + 2] > 8 || Math.Abs(img.Px[i + 3] - a) > 2) return 0;
                return a;
            }
            catch { return 0; }
        }

        public static bool Is(FaceProject p, XNode layout, int theme) => theme == AodTheme && AlphaOf(p, layout) > 0;

        /// <summary>Шар-приглушення в AOD (верхній з таких) або null</summary>
        public static XNode Find(FaceProject p)
        {
            if (p.Themes.Count < 2) return null;
            return p.Layouts(AodTheme).LastOrDefault(l => AlphaOf(p, l) > 0);
        }

        /// <summary>Сила приглушення у відсотках (0 — немає)</summary>
        public static int Percent(FaceProject p)
        {
            var l = Find(p);
            return l == null ? 0 : (int)Math.Round(AlphaOf(p, l) * 100 / 255.0);
        }

        /// <summary>Ставить приглушення (0 — прибирає шар)</summary>
        public static void Set(FaceProject p, int percent)
        {
            var th = p.Theme(AodTheme);
            if (th == null) return;
            var cur = Find(p);
            if (percent <= 0)
            {
                if (cur != null) ElementFactory.Delete(p, cur, AodTheme);
                return;
            }
            int alpha = Math.Max(1, Math.Min(254, (int)Math.Round(percent * 255 / 100.0)));
            int w = p.Meta.Device.Width, h = p.Meta.Device.Height;
            var px = new byte[w * h * 4];
            for (int i = 3; i < px.Length; i += 4) px[i] = (byte)alpha;
            var img = new RgbaImage(w, h, px);
            if (cur != null)
            {
                var res = p.ElementOf(cur);
                if (ElementFactory.LayoutsOf(p, res).Count > 1) { ElementFactory.Delete(p, cur, AodTheme); cur = null; }
                else ElementFactory.ReplaceImage(p, res, img);
            }
            if (cur == null)
            {
                var name = ElementFactory.AddImageResource(p, img, "aod_dim");
                cur = new XNode("Layout");
                cur.Set("ref", "@" + name).Set("x", 0).Set("y", 0);
                th.Kids.Add(cur);
            }
            KeepOnTop(p);
        }

        /// <summary>Приглушення завжди найвище в AOD — нові та переміщені шари йдуть під нього</summary>
        public static void KeepOnTop(FaceProject p)
        {
            var th = p.Theme(AodTheme);
            var l = Find(p);
            if (th == null || l == null) return;
            var last = th.Kids.LastOrDefault(k => k.Tag == "Layout");
            if (last == l) return;
            th.Kids.Remove(l);
            th.Kids.Add(l);
        }
    }
}
