// SPDX-License-Identifier: MIT
// Набори картинок (ImageArray) усередині циферблата: один набір можуть брати кілька елементів
// (години й хвилини, основний екран і AOD). Тут — пошук, спільне використання і відокремлення.

using System;
using System.Collections.Generic;
using System.Linq;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class ImageSets
    {
        // MARK: Покажчик для інтерфейсу — один прохід по циферблату на кожну зміну

        sealed class Index
        {
            public object Root; public int Rev; public int N;
            public readonly Dictionary<string, List<XNode>> Users = new Dictionary<string, List<XNode>>();
            public readonly Dictionary<XNode, List<Tuple<int, XNode>>> Layouts = new Dictionary<XNode, List<Tuple<int, XNode>>>();
        }
        static Index cache;

        static Index Ix(FaceProject p)
        {
            int n = p.Resources.Kids.Count;
            var c = cache;
            if (c != null && ReferenceEquals(c.Root, p.Root) && c.Rev == p.Revision && c.N == n) return c;
            var ix = new Index { Root = p.Root, Rev = p.Revision, N = n };
            var byName = new Dictionary<string, XNode>();
            foreach (var e in p.Resources.Elements)
            {
                var nm = e.Str("name");
                if (nm != null && !byName.ContainsKey(nm)) byName[nm] = e;
                var r = e.Str("ref");
                if (r != null && r.Length > 1 && r[0] == '@')
                {
                    var k = r.Substring(1);
                    if (!ix.Users.TryGetValue(k, out var l)) ix.Users[k] = l = new List<XNode>();
                    l.Add(e);
                }
            }
            for (int t = 0; t < p.Themes.Count; t++)
                foreach (var l in p.Layouts(t))
                {
                    var r = l.Str("ref");
                    if (r == null || r.Length < 2 || !byName.TryGetValue(r.Substring(1), out var res)) continue;
                    var shown = ElementFactory.TapInner(p, res) ?? res;
                    if (!ix.Layouts.TryGetValue(shown, out var list)) ix.Layouts[shown] = list = new List<Tuple<int, XNode>>();
                    list.Add(Tuple.Create(t, l));
                }
            return cache = ix;
        }

        /// <summary>Хто бере набір — з покажчика (для показу; у змінах — Users)</summary>
        public static List<XNode> UsersFast(FaceProject p, XNode arr)
            => Ix(p).Users.TryGetValue(arr.Str("name") ?? "", out var l) ? l.Where(x => x != arr).ToList() : new List<XNode>();

        /// <summary>Шари елемента на всіх екранах (екран, шар) — з покажчика</summary>
        public static List<Tuple<int, XNode>> LayoutsFast(FaceProject p, XNode res)
            => Ix(p).Layouts.TryGetValue(res, out var l) ? l : new List<Tuple<int, XNode>>();

        /// <summary>Набір, який показує елемент (лише масив картинок; одна картинка — не набір)</summary>
        public static XNode SetOf(FaceProject p, XNode res)
        {
            if (res == null || res.Tag == "ImageArray") return null;
            var r = p.ResourceRef(res.Str("ref"));
            return r != null && r.Tag == "ImageArray" ? r : null;
        }

        public static int Count(XNode arr) => arr?.All("Image").Count ?? 0;

        /// <summary>Елементи (ресурси), що беруть цей набір</summary>
        public static List<XNode> Users(FaceProject p, XNode arr)
        {
            var key = "@" + (arr.Str("name") ?? "");
            return p.Resources.Elements.Where(e => e != arr && e.Str("ref") == key).ToList();
        }

        /// <summary>Скільки місць показує набір: кожен шар кожного елемента на кожному екрані</summary>
        public static int Uses(FaceProject p, XNode arr) => UsersFast(p, arr).Sum(u => System.Math.Max(1, LayoutsFast(p, u).Count));

        /// <summary>Набір підходить елементу: для числа — 10 цифр, для інших — стільки ж картинок, скільки зараз</summary>
        public static bool Fits(FaceProject p, XNode res, XNode arr)
        {
            if (arr == null) return false;
            if (res.Tag == "DataItemImageNumber") return Count(arr) >= 10;
            var cur = SetOf(p, res);
            return cur != null && Count(arr) == Count(cur);
        }

        /// <summary>Усі набори циферблата, якими хтось користується</summary>
        public static List<XNode> All(FaceProject p)
            => p.Resources.Elements.Where(e => e.Tag == "ImageArray" && UsersFast(p, e).Count > 0).ToList();

        /// <summary>Набори для нового числа (10 цифр і більше)</summary>
        public static List<XNode> ForDigits(FaceProject p)
            => All(p).Where(a => Count(a) >= 10 && UsersFast(p, a).Any(u => u.Tag == "DataItemImageNumber")).ToList();

        /// <summary>Набори для нових значків за значенням (дні тижня — 7, місяці — 12…)</summary>
        public static List<XNode> ForValues(FaceProject p, int count)
            => All(p).Where(a => Count(a) == count && UsersFast(p, a).Any(u => u.Tag == "DataItemImageValues")).ToList();

        /// <summary>Елемент бере інший набір; старий прибирається, якщо більше нікому не потрібен.
        /// Параметри малювання беруться від іншого елемента цього набору (щоб «Намалювати шрифтом» малював те саме).</summary>
        public static void Use(FaceProject p, XNode res, XNode arr)
        {
            var old = res.Str("ref");
            var key = "@" + arr.Str("name");
            if (old == key) return;
            res.Set("ref", key);
            var nm = res.Str("name") ?? "";
            var donor = Users(p, arr).Select(u => u.Str("name") ?? "").FirstOrDefault(n => n != nm && p.Meta.Generators.ContainsKey(n));
            if (donor != null)
            {
                var g = p.Meta.Generators[donor].Copy();
                if (p.Meta.Generators.TryGetValue(nm, out var mine)) { g.Unit = mine.Unit; }
                p.Meta.Generators[nm] = g;
            }
            else p.Meta.Generators.Remove(nm);
            if (old != null) ElementFactory.Collect(p, old);
            ColorVariants.Refresh(p, res);
        }

        /// <summary>Копія набору з власними файлами; повертає нову назву</summary>
        public static string CopySet(FaceProject p, XNode arr)
        {
            var name = p.UniqueName(arr.Str("name") ?? "images");
            var copy = new XNode("ImageArray");
            foreach (var a in arr.Attrs) copy.Set(a.Key, a.Value);
            copy.Set("name", name);
            var imgs = arr.All("Image");
            for (int i = 0; i < imgs.Count; i++)
            {
                var data = p.File(imgs[i].Str("src"));
                var src = name + "/" + i + ".png";
                if (data != null) p.SetFile(src, data);
                copy.Add("Image").Set("src", src);
            }
            p.Resources.Kids.Add(copy);
            return name;
        }

        /// <summary>Чи має цей шар окремі картинки: набір і сам елемент більше ніде не показуються</summary>
        public static bool IsShared(FaceProject p, XNode res)
        {
            if (LayoutsFast(p, res).Count > 1) return true;
            var arr = SetOf(p, res);
            return arr != null && UsersFast(p, arr).Count > 1;
        }

        /// <summary>Окремі картинки для цього шару: якщо елемент показано на двох екранах — шар отримує свою копію елемента,
        /// і набір копіюється. Повертає ресурс, який тепер показує шар.</summary>
        public static XNode Detach(FaceProject p, XNode layout)
        {
            var res = p.ElementOf(layout);
            if (res == null) return null;
            if (ElementFactory.LayoutsOf(p, res).Count > 1)
            {
                var copy = res.Copy();
                var nm = p.UniqueName(res.Str("name") ?? "copy");
                copy.Set("name", nm);
                p.Resources.Kids.Add(copy);
                if (p.Meta.Generators.TryGetValue(res.Str("name") ?? "", out var g)) p.Meta.Generators[nm] = g.Copy();
                if (p.Meta.ColorFollow.Contains(res.Str("name") ?? "")) p.Meta.ColorFollow.Add(nm);
                layout.Set("ref", "@" + nm);
                res = copy;
            }
            var arr = SetOf(p, res);
            if (arr != null && Users(p, arr).Count > 1)
            {
                res.Set("ref", "@" + CopySet(p, arr));
                ColorVariants.Refresh(p, res);
            }
            return res;
        }

        /// <summary>Замінити всі картинки набору (усім, хто його бере). Розмір — як у першої нової картинки.</summary>
        public static void ReplaceAll(FaceProject p, XNode arr, List<RgbaImage> images)
        {
            var slots = arr.All("Image");
            var f0 = images[0];
            int n = System.Math.Min(slots.Count, images.Count);
            for (int i = 0; i < n; i++)
            {
                var src = slots[i].Str("src") ?? (arr.Str("name") + "/" + i + ".png");
                p.SetFile(src, Imaging.Contain(images[i], f0.W, f0.H).Png());
                slots[i].Set("src", src);
            }
            arr.Set("format", "indexed8");
            // свої картинки — параметри малювання шрифтом більше не діють
            foreach (var u in Users(p, arr))
            {
                p.Meta.Generators.Remove(u.Str("name") ?? "");
                ColorVariants.Refresh(p, u);
            }
        }
    }
}
