// SPDX-License-Identifier: MIT
// Кольорові варіанти циферблата (користувач вибирає колір циферблата на браслеті).
//  • <Watchface colorGroupTable="#C0,#C1,…"> — кольори; перший — основний вигляд;
//  • <Theme colorGroup="#C0,#C1,…"> — кольори теми (у нас — усі);
//  • картинка без colorGroup — основний вигляд, її варіанти — елементи з тим самим іменем і colorGroup="#Ci".
// Варіанти малюються заново для цифр, дуг, ліній і стрілок, створених редактором; одноколірні картинки перефарбовуються.

using System;
using System.Collections.Generic;
using System.Linq;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class ColorVariants
    {
        /// <summary>Найбільше кольорів (на практиці в циферблатах до 10)</summary>
        public const int MaxColors = 10;

        /// <summary>Доступність: null — недоступно (з поясненням у why)</summary>
        public enum Availability { Generator, Tint, Unavailable }

        // MARK: Кольори

        public static List<string> Colors(FaceProject p)
        {
            var raw = p.Root.Str("colorGroupTable");
            if (raw == null) return new List<string>();
            return raw.Split(',').Select(Normalize).Where(s => s.Length > 0).ToList();
        }

        public static bool IsEnabled(FaceProject p) => Colors(p).Count > 1;

        public static string Normalize(string s)
        {
            var t = (s ?? "").Trim().ToUpperInvariant();
            var hex = t.StartsWith("#") ? t.Substring(1) : t.StartsWith("0X") ? t.Substring(2) : t;
            uint v;
            if (hex.Length != 6 || !uint.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out v)) return "";
            return "#" + hex;
        }

        public static void Enable(FaceProject p, string b, string first) => Write(p, new List<string> { Normalize(b), Normalize(first) });

        /// <summary>Нові кольори: варіанти увімкнених елементів малюються заново (варіанти прибраних кольорів видаляються)</summary>
        public static void SetColors(FaceProject p, List<string> list)
        {
            var old = Colors(p);
            var nw = list.Select(Normalize).Where(s => s.Length > 0).Take(MaxColors).ToList();
            var enabled = TargetsWithVariants(p);
            var redraw = enabled.Where(t => CanRedraw(p, t)).ToList();
            foreach (var t in redraw) RemoveVariants(p, t);
            foreach (var t in enabled)
            {
                if (redraw.Contains(t)) continue;
                foreach (var v in Variants(p, t))
                    if (!nw.Skip(1).Contains(Normalize(v.Str("colorGroup")))) Drop(p, v);
            }
            Write(p, nw);
            if (nw.Count < 2) return;
            foreach (var t in redraw) Rebuild(p, t, null);
            // елементи з галочкою, у яких варіантів ще не було (кольори щойно з'явилися)
            foreach (var n in p.Meta.ColorFollow.ToList())
            {
                var el = p.Resource(n);
                if (el == null || Check(p, el, out _) == Availability.Unavailable) continue;
                foreach (var t in Targets(p, el)) if (Variants(p, t).Count == 0) Rebuild(p, t, el);
            }
        }

        /// <summary>Вимикає варіанти повністю</summary>
        public static void Disable(FaceProject p)
        {
            foreach (var t in TargetsWithVariants(p)) RemoveVariants(p, t);
            p.Root.Remove("colorGroupTable");
            foreach (var th in p.Themes) { th.Remove("colorGroup"); th.Remove("colorGroupTable"); }
            foreach (var r in p.Resources.Elements) if (r.Tag == "Image" || r.Tag == "ImageArray") r.Remove("colorGroup");
        }

        /// <summary>Таблиці тем за поточними кольорами</summary>
        public static void SyncThemes(FaceProject p)
        {
            var c = Colors(p);
            if (c.Count < 2) return;
            var joined = string.Join(",", c);
            if (p.Themes.Any(t => t.Str("colorGroup") != joined)) Write(p, c);
        }

        static void Write(FaceProject p, List<string> list)
        {
            if (list.Count < 2) { Disable(p); return; }
            var joined = string.Join(",", list);
            p.Root.Set("colorGroupTable", joined);
            foreach (var th in p.Themes) th.Set("colorGroup", joined);
        }

        // MARK: Пошук

        /// <summary>Версія картинки для кольору з індексом index (null — немає)</summary>
        public static XNode Variant(FaceProject p, XNode b, int index)
        {
            var cols = Colors(p);
            var name = b.Str("name");
            if (index <= 0 || index >= cols.Count || name == null) return null;
            var c = cols[index];
            return p.Resources.Elements.FirstOrDefault(e => e.Tag == b.Tag && e.Str("name") == name && Normalize(e.Str("colorGroup")) == c);
        }

        public static List<XNode> Variants(FaceProject p, XNode b)
        {
            var name = b.Str("name");
            if (name == null) return new List<XNode>();
            var first = Colors(p).FirstOrDefault();
            return p.Resources.Elements.Where(e => e != b && e.Tag == b.Tag && e.Str("name") == name && e.Has("colorGroup")
                                                 && Normalize(e.Str("colorGroup")) != first).ToList();
        }

        static List<XNode> TargetsWithVariants(FaceProject p)
        {
            var seen = new HashSet<string>();
            var o = new List<XNode>();
            foreach (var r in p.Resources.Elements.ToList())
            {
                if (r.Tag != "Image" && r.Tag != "ImageArray") continue;
                var name = r.Str("name");
                if (name == null || !seen.Add(name)) continue;
                var b = p.Resource(name);
                if (b != null && Variants(p, b).Count > 0) o.Add(b);
            }
            return o;
        }

        // MARK: Елемент

        /// <summary>Картинки елемента, що міняють колір (для дуги й лінії — лише заповнення)</summary>
        public static List<XNode> Targets(FaceProject p, XNode res)
        {
            switch (res.Tag)
            {
                case "Image": case "ImageArray": return new List<XNode> { res };
                case "DataItemImageNumber": case "DataItemImageValues": case "Sprite": case "DataItemPointer":
                case "DataItemArcProgressBar": case "DataItemLineProgressBar":
                    var r = p.ResourceRef(res.Str("ref"));
                    return r == null ? new List<XNode>() : new List<XNode> { r };
                default: return new List<XNode>();
            }
        }

        public static Availability Check(FaceProject p, XNode res, out string why)
        {
            why = null;
            switch (res.Tag)
            {
                case "DataItemText": why = S.Get("cvText"); return Availability.Unavailable;
                case "Widget": case "Slot":
                    var ms = Members(p, res);
                    if (ms.Count == 0) { why = S.Get("cvWidgetEmpty"); return Availability.Unavailable; }
                    foreach (var m in ms) { var a = Check(p, m, out _); if (a != Availability.Unavailable) return a; }
                    why = S.Get("cvWidget"); return Availability.Unavailable;
            }
            var ts = Targets(p, res);
            if (ts.Count == 0) { why = S.Get("cvNone"); return Availability.Unavailable; }
            var g = p.Meta.Gen(res.Str("name"));
            if (g != null && g.Drawn) return Availability.Generator;
            foreach (var t in ts)
                if (!Frames(p, t).All(f => TintBase(f) != null)) { why = S.Get("cvMulti"); return Availability.Unavailable; }
            return Availability.Tint;
        }

        public static bool IsOn(FaceProject p, XNode res) =>
            res.Tag == "Widget" || res.Tag == "Slot" ? Members(p, res).Any(m => IsOn(p, m)) : Targets(p, res).Any(t => Variants(p, t).Count > 0);

        /// <summary>Елементи всередині віджета (і вкладених віджетів) або слота (усі його віджети)</summary>
        public static List<XNode> Members(FaceProject p, XNode res, int depth = 0)
        {
            var o = new List<XNode>();
            if (depth >= 6 || (res.Tag != "Widget" && res.Tag != "Slot")) return o;
            foreach (var it in res.All("Item"))
            {
                var c = p.ResourceRef(it.Str("ref"));
                if (c == null) continue;
                if (c.Tag == "Widget" || c.Tag == "Slot") o.AddRange(Members(p, c, depth + 1)); else o.Add(c);
            }
            return o;
        }

        public static void Set(FaceProject p, XNode res, bool on)
        {
            var n = res.Str("name") ?? "";
            if (on) p.Meta.ColorFollow.Add(n); else p.Meta.ColorFollow.Remove(n);
            if (res.Tag == "Widget" || res.Tag == "Slot")
            {
                foreach (var m in Members(p, res)) if (!on || Check(p, m, out _) != Availability.Unavailable) Set(p, m, on);
                return;
            }
            foreach (var t in Targets(p, res)) { if (on) Rebuild(p, t, res); else RemoveVariants(p, t); }
        }

        /// <summary>Галочку поставили, але кольорів у циферблата ще немає</summary>
        public static bool Wanted(FaceProject p, XNode res) => p.Meta.ColorFollow.Contains(res.Str("name") ?? "");

        /// <summary>Після зміни картинок елемента — варіанти малюються заново</summary>
        public static void Refresh(FaceProject p, XNode res)
        {
            if (!IsEnabled(p) || !IsOn(p, res)) return;
            Set(p, res, Check(p, res, out _) != Availability.Unavailable);
        }

        // MARK: Малювання варіантів

        /// <summary>Елемент, якому належить картинка (щоб знайти параметри малювання)</summary>
        static XNode Owner(FaceProject p, XNode target)
        {
            var name = target.Str("name");
            if (name == null) return null;
            var r = "@" + name;
            return p.Resources.Elements.FirstOrDefault(e => e.Str("ref") == r && p.Meta.Gen(e.Str("name")) != null);
        }

        public static void RemoveAll(FaceProject p, XNode b) => RemoveVariants(p, b);

        static void RemoveVariants(FaceProject p, XNode b) { foreach (var v in Variants(p, b)) Drop(p, v); }

        static void Drop(FaceProject p, XNode v)
        {
            var s = v.Str("src");
            if (s != null) p.RemoveFile(s);
            foreach (var i in v.All("Image")) { var x = i.Str("src"); if (x != null) p.RemoveFile(x); }
            p.Resources.Kids.Remove(v);
        }

        static bool CanRedraw(FaceProject p, XNode b)
        {
            var el = Owner(p, b);
            var g = el == null ? null : p.Meta.Gen(el.Str("name"));
            if (g != null && g.Drawn) return true;
            var fr = Frames(p, b);
            return fr.Count > 0 && fr.All(f => TintBase(f) != null);
        }

        /// <summary>Малює варіанти картинки для всіх кольорів, крім основного (старі прибираються)</summary>
        static void Rebuild(FaceProject p, XNode b, XNode element)
        {
            RemoveVariants(p, b);
            var cols = Colors(p);
            var name = b.Str("name");
            if (cols.Count < 2 || name == null) return;
            var el = element ?? Owner(p, b);
            var gen = el == null ? null : p.Meta.Gen(el.Str("name"));
            var src = Frames(p, b);
            if (src.Count == 0) return;
            var kids = p.Resources.Kids;
            int insertAt = kids.IndexOf(b);
            insertAt = (insertAt < 0 ? kids.Count - 1 : insertAt) + 1;
            for (int i = 1; i < cols.Count; i++)
            {
                var c = cols[i];
                List<RgbaImage> images;
                if (gen != null && gen.Drawn)
                {
                    var g = gen.Copy(); g.Color = c;
                    switch (gen.Kind)
                    {
                        case GenKind.Digits: images = AssetFactory.DigitFrames(g); break;
                        // дуга й лінія — тієї ж форми, що й основна (кут, кінці), лише іншого кольору
                        case GenKind.Arc: images = new List<RgbaImage> { ElementFactory.ArcImage(ElementFactory.Synced(el, g), c) }; break;
                        case GenKind.Line: images = new List<RgbaImage> { ElementFactory.LineImage(ElementFactory.Synced(el, g), c, out _, out _) }; break;
                        case GenKind.Pointer: images = new List<RgbaImage> { AssetFactory.Hand(g.Length, g.Width, c) }; break;
                        case GenKind.Texts: images = AssetFactory.TextFrames(g, g.Texts); break;
                        case GenKind.Label: { var li = AssetFactory.LabelImage(g); images = li == null ? new List<RgbaImage>() : new List<RgbaImage> { li }; break; }
                        default: images = new List<RgbaImage>(); break;
                    }
                }
                else images = src.Select(f => Tint(f, c)).Where(f => f != null).ToList();
                if (images.Count == 0 || (images.Count != src.Count && b.Tag != "ImageArray")) continue;
                var tag = c.Substring(1).ToLowerInvariant();
                var v = new XNode(b.Tag);
                v.Set("name", name).Set("compressMethod", b.Str("compressMethod") ?? "RLEReversed");
                if (b.Tag == "Image")
                {
                    var file = name + "_" + tag + ".png";
                    p.SetFile(file, images[0].Png());
                    v.Set("src", file).Set("format", images[0].BestFormat());
                }
                else v.Set("format", images.Any(x => x.BestFormat() == "RGB565A8") ? "RGB565A8" : "indexed8");
                v.Set("recolorEnable", false).Set("colorGroup", c);
                if (b.Tag == "ImageArray")
                    for (int k = 0; k < images.Count; k++)
                    {
                        var file = name + "_" + tag + "/" + k + ".png";
                        p.SetFile(file, images[k].Png());
                        v.Add("Image").Set("src", file);
                    }
                kids.Insert(Math.Min(insertAt, kids.Count), v);
                insertAt++;
            }
        }

        /// <summary>Кадри картинки (Image — один)</summary>
        static List<RgbaImage> Frames(FaceProject p, XNode res)
        {
            var srcs = res.Tag == "Image" ? new List<string> { res.Str("src") } : res.All("Image").Select(i => i.Str("src")).ToList();
            var o = new List<RgbaImage>();
            foreach (var s in srcs)
            {
                var d = p.File(s);
                var png = d == null ? null : Png.Decode(d);
                if (png != null) o.Add(png);
            }
            return o;
        }

        // MARK: Перефарбування

        /// <summary>Колір одноколірної картинки (найяскравіший піксель), якщо всі видимі пікселі — його відтінки</summary>
        static int[] TintBase(RgbaImage img)
        {
            var px = img.Px;
            int[] best = { 0, 0, 0 };
            int bestL = -1;
            for (int i = 0; i < px.Length; i += 4)
            {
                if (px[i + 3] <= 32) continue;
                int l = px[i] + px[i + 1] + px[i + 2];
                if (l > bestL) { bestL = l; best = new[] { (int)px[i], px[i + 1], px[i + 2] }; }
            }
            if (bestL <= 30) return null;
            for (int i = 0; i < px.Length; i += 4)
            {
                if (px[i + 3] <= 32) continue;
                int r = px[i], g = px[i + 1], b = px[i + 2];
                double k = (double)(r + g + b) / bestL;
                if (Math.Abs(best[0] * k - r) > 28 || Math.Abs(best[1] * k - g) > 28 || Math.Abs(best[2] * k - b) > 28) return null;
            }
            return best;
        }

        public static RgbaImage Tint(RgbaImage img, string hex)
        {
            var b = TintBase(img);
            if (b == null) return null;
            var c = Imaging.ParseColor(hex);
            double baseL = b[0] + b[1] + b[2];
            var o = (byte[])img.Px.Clone();
            for (int i = 0; i < o.Length; i += 4)
            {
                if (o[i + 3] == 0) continue;
                double k = Math.Min(1, (o[i] + o[i + 1] + o[i + 2]) / baseL);
                o[i] = (byte)Math.Min(255, Math.Round(c.R * k));
                o[i + 1] = (byte)Math.Min(255, Math.Round(c.G * k));
                o[i + 2] = (byte)Math.Min(255, Math.Round(c.B * k));
            }
            return new RgbaImage(img.W, img.H, o);
        }
    }
}
