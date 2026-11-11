// SPDX-License-Identifier: MIT
// «Форма» для чисел: одна фігура (коло, капсула, прямокутник) навколо всього числа, а не під кожною цифрою.
// Цифри числа на браслеті — окремі картинки, тож фігура — окремий шар-картинка під числом. Він не вибирається
// на полотні й у списку шарів і після кожної правки сам стає під своїм числом (під ширину всіх його цифр).

using System;
using System.Linq;
using System.Windows;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class NumberBadge
    {
        public const string Suffix = "_numbg";

        public static bool IsBadge(XNode layout) => (layout?.Str("ref") ?? "").EndsWith(Suffix, StringComparison.Ordinal);

        /// <summary>Намалювати (або прибрати, якщо форми немає) фігуру під числом</summary>
        public static void Update(FaceProject p, XNode res, Generator gen)
        {
            var name = res.Str("name") ?? "";
            var bg = name + Suffix;
            Remove(p, bg);
            if (string.IsNullOrEmpty(gen.Badge)) return;
            var size = ContentSize(p, res);
            if (size == null) return;
            var img = AssetFactory.BadgeImage(gen, size.Value.Width, size.Value.Height);
            if (img == null) return;
            var src = bg + ".png";
            p.SetFile(src, img.Png());
            p.Resources.Add("Image").Set("name", bg).Set("src", src).Set("compressMethod", "RLEReversed").Set("format", img.BestFormat()).Set("recolorEnable", false);
            foreach (var th in p.Themes)
                foreach (var l in th.All("Layout").Where(l => l.Str("ref") == "@" + name).ToList())
                {
                    var b = new XNode("Layout"); b.Set("ref", "@" + bg);
                    th.Kids.Insert(th.Kids.IndexOf(l), b);
                }
            Sync(p);
        }

        static void Remove(FaceProject p, string bg)
        {
            foreach (var th in p.Themes) th.Kids.RemoveAll(k => k.Tag == "Layout" && k.Str("ref") == "@" + bg);
            var old = p.Resource(bg);
            if (old != null)
            {
                var s = old.Str("src"); if (s != null) p.RemoveFile(s);
                p.Resources.Kids.Remove(old);
            }
        }

        /// <summary>Розмір числа з усіма його цифрами (totalDigits; без нього — 4)</summary>
        static Size? ContentSize(FaceProject p, XNode res)
        {
            var arr = p.ResourceRef(res.Str("ref"));
            var src = arr?.All("Image").FirstOrDefault()?.Str("src");
            var d = src == null ? null : p.File(src);
            var img = d == null ? null : Imaging.Decode(d);
            if (img == null) return null;
            int n = res.Int("totalDigits") > 0 ? res.Int("totalDigits") : 4;
            double space = (sbyte)(byte)res.Int("space");
            return new Size(n * img.W + (n - 1) * space, img.H);
        }

        /// <summary>Після кожної правки: фігура — під своїм числом (одразу перед ним у шарах), по центру всіх його цифр.
        /// Фігура без числа прибирається.</summary>
        public static void Sync(FaceProject p)
        {
            foreach (var th in p.Themes)
                foreach (var b in th.All("Layout").Where(IsBadge).ToList())
                {
                    var bgName = (b.Str("ref") ?? "").Substring(1);
                    var name = bgName.Substring(0, bgName.Length - Suffix.Length);
                    var num = th.All("Layout").FirstOrDefault(l => l.Str("ref") == "@" + name);
                    var res = p.Resource(name);
                    var size = res == null ? null : ContentSize(p, res);
                    var bsrc = p.Resource(bgName)?.Str("src");
                    var bd = bsrc == null ? null : p.File(bsrc);
                    var bi = bd == null ? null : Imaging.Decode(bd);
                    if (num == null || size == null || bi == null) { th.Kids.Remove(b); continue; }
                    // x макета числа — точка прив'язки (left / center / right), як на браслеті
                    double x = num.Int("x");
                    var al = res.Str("align");
                    if (al == "right" || al == "flex-end") x -= size.Value.Width;
                    else if (al == "center") x -= size.Value.Width / 2;
                    double cx = x + size.Value.Width / 2, cy = num.Int("y") + size.Value.Height / 2;
                    b.Set("x", (int)Math.Round(cx - bi.W / 2.0)).Set("y", (int)Math.Round(cy - bi.H / 2.0));
                    // одразу під числом
                    int ib = th.Kids.IndexOf(b), inum = th.Kids.IndexOf(num);
                    if (ib != inum - 1)
                    {
                        th.Kids.RemoveAt(ib);
                        th.Kids.Insert(th.Kids.IndexOf(num), b);
                    }
                }
        }
    }
}
