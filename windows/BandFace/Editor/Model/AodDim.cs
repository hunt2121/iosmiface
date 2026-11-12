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

        /// <summary>Службові шари, яких не видно серед шарів і які не вибираються: приглушення AOD і фігура під числом</summary>
        public static bool Is(FaceProject p, XNode layout, int theme) => NumberBadge.IsBadge(layout) || (theme == AodTheme && AlphaOf(p, layout) > 0);

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

        /// <summary>Позначка шару AOD «над приглушенням» (лише для редактора; компілятор читає в Layout тільки ref, x, y)</summary>
        public const string AboveKey = "aboveDim";

        public static bool IsAbove(XNode l) => l != null && l.Bool(AboveKey);

        /// <summary>Підняти шар над приглушенням або повернути під нього</summary>
        public static void SetAbove(FaceProject p, XNode l, bool on)
        {
            if (on) l.Set(AboveKey, true); else l.Remove(AboveKey);
            KeepOnTop(p);
        }

        /// <summary>Порядок AOD: звичайні шари, потім приглушення, потім шари «над приглушенням» (фігура під числом — разом із числом)</summary>
        public static void KeepOnTop(FaceProject p)
        {
            var th = p.Theme(AodTheme);
            var dim = Find(p);
            if (th == null || dim == null) return;
            var lays = th.Kids.Where(k => !k.IsComment && k.Tag == "Layout" && k != dim).ToList();
            var above = new System.Collections.Generic.List<XNode>();
            for (int i = 0; i < lays.Count; i++)
            {
                var next = i + 1 < lays.Count ? lays[i + 1] : null;
                if (IsAbove(lays[i]) || (NumberBadge.IsBadge(lays[i]) && IsAbove(next))) above.Add(lays[i]);
            }
            var tail = new System.Collections.Generic.List<XNode> { dim };
            tail.AddRange(above);
            var all = th.Kids.Where(k => !k.IsComment && k.Tag == "Layout").ToList();
            if (all.Count >= tail.Count && all.Skip(all.Count - tail.Count).SequenceEqual(tail)) return;
            th.Kids.RemoveAll(k => tail.Contains(k));
            th.Kids.AddRange(tail);
        }

        /// <summary>Відкритий .bin / старий проєкт: шари, що стоять вище за приглушення, позначаються «над приглушенням»</summary>
        public static void MarkFromOrder(FaceProject p)
        {
            var th = p.Theme(AodTheme);
            var dim = Find(p);
            if (th == null || dim == null) return;
            var lays = th.Kids.Where(k => !k.IsComment && k.Tag == "Layout").ToList();
            if (lays.Any(IsAbove)) return;
            int i = lays.IndexOf(dim);
            for (int k = i + 1; k < lays.Count; k++)
                if (!NumberBadge.IsBadge(lays[k]) && AlphaOf(p, lays[k]) == 0) lays[k].Set(AboveKey, true);
        }
    }
}
