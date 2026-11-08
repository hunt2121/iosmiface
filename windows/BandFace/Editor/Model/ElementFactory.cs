// SPDX-License-Identifier: MIT
// Створення, копіювання й видалення елементів циферблата (ресурс у <Resources> + <Layout> у темі),
// перемальовування згенерованих елементів, дія при натисканні.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using BandFace.Faces;

namespace BandFace.Creator
{
    public enum ElementKind { Text, Label, Digits, Image, Animation, Pointer, Arc, Line, Values, Widget, Slot, Other }

    static class Elements
    {
        public static ElementKind Of(XNode res)
        {
            switch (res?.Tag)
            {
                case "DataItemText": return ElementKind.Text;
                case "DataItemImageNumber": return ElementKind.Digits;
                case "Image": case "ImageArray": return ElementKind.Image;
                case "Sprite": return ElementKind.Animation;
                case "DataItemPointer": return ElementKind.Pointer;
                case "DataItemArcProgressBar": return ElementKind.Arc;
                case "DataItemLineProgressBar": return ElementKind.Line;
                case "DataItemImageValues": return ElementKind.Values;
                case "Widget": return ElementKind.Widget;
                case "Slot": return ElementKind.Slot;
                default: return ElementKind.Other;
            }
        }

        /// <summary>Тип із урахуванням редактора: картинка-напис показується як «Напис»</summary>
        public static ElementKind Of(XNode res, FaceProject p)
        {
            var k = Of(res);
            if (k == ElementKind.Image && p.Meta.Gen(res?.Str("name"))?.Kind == GenKind.Label) return ElementKind.Label;
            return k;
        }

        public static string Title(ElementKind k) => S.Get("el" + k);
    }

    static class ElementFactory
    {
        // MARK: Допоміжне

        /// <summary>Додає зображення як ресурс Image, повертає його ім'я.</summary>
        public static string AddImageResource(FaceProject p, RgbaImage img, string b, bool compress = true)
        {
            var name = p.UniqueName(b);
            var src = name + ".png";
            p.SetFile(src, img.Png());
            var e = new XNode("Image");
            e.Set("name", name).Set("src", src).Set("compressMethod", compress ? "RLEReversed" : "none")
             .Set("format", img.BestFormat()).Set("recolorEnable", false);
            p.Resources.Kids.Add(e);
            return name;
        }

        /// <summary>Кадри як ImageArray.</summary>
        public static string AddFrames(FaceProject p, List<RgbaImage> frames, string b)
        {
            var name = p.UniqueName(b);
            var e = new XNode("ImageArray");
            var fmt = frames.Any(f => f.BestFormat() == "RGB565A8") ? "RGB565A8" : "indexed8";
            e.Set("name", name).Set("compressMethod", "RLEReversed").Set("format", fmt).Set("recolorEnable", false);
            for (int i = 0; i < frames.Count; i++)
            {
                var src = name + "/" + i + ".png";
                p.SetFile(src, frames[i].Png());
                e.Add("Image").Set("src", src);
            }
            p.Resources.Kids.Add(e);
            return name;
        }

        public static XNode AddLayout(FaceProject p, string r, int theme, int x, int y)
        {
            var th = p.Theme(theme);
            if (th == null) return null;
            var l = new XNode("Layout");
            l.Set("ref", "@" + r).Set("x", x).Set("y", y);
            th.Kids.Add(l);
            return l;
        }

        // MARK: Елементи

        public static void AddDigits(FaceProject p, string source, Generator gen, int theme, int cx, int cy)
        {
            var frames = AssetFactory.DigitFrames(gen);
            var arr = AddFrames(p, frames, "digits");
            var name = p.UniqueName(source);
            var e = new XNode("DataItemImageNumber");
            e.Set("name", name).Set("source", source).Set("ref", "@" + arr).Set("totalDigits", 2).Set("decimalDigits", 0)
             .Set("align", "left").Set("leadingZero", true).Set("trailingZero", false).Set("renderRule", "alwaysShow")
             .Set("rotation", 0).Set("decimalOffsetX", 0).Set("space", 0);
            p.Resources.Kids.Add(e);
            p.Meta.Generators[name] = gen;
            int w = (frames.Count > 0 ? frames[0].W : 0) * 2, h = frames.Count > 0 ? frames[0].H : 0;
            AddLayout(p, name, theme, cx - w / 2, cy - h / 2);
        }

        /// <summary>Число з ваших картинок 0–9 (усі вирівнюються під розмір першої)</summary>
        public static void AddDigitImages(FaceProject p, string source, List<RgbaImage> images, int theme, int cx, int cy)
        {
            if (images.Count == 0) return;
            var f0 = images[0];
            var arr = AddFrames(p, images.Select(i => Imaging.Contain(i, f0.W, f0.H)).ToList(), "digits");
            var name = p.UniqueName(source);
            var e = new XNode("DataItemImageNumber");
            e.Set("name", name).Set("source", source).Set("ref", "@" + arr).Set("totalDigits", 2).Set("decimalDigits", 0)
             .Set("align", "left").Set("leadingZero", true).Set("trailingZero", false).Set("renderRule", "alwaysShow")
             .Set("rotation", 0).Set("decimalOffsetX", 0).Set("space", 0);
            p.Resources.Kids.Add(e);
            AddLayout(p, name, theme, cx - f0.W, cy - f0.H / 2);
        }

        /// <summary>Напис картинкою (рядок вибраним шрифтом)</summary>
        public static void AddLabel(FaceProject p, Generator gen, int theme, int cx, int cy)
        {
            var img = AssetFactory.LabelImage(gen);
            if (img == null) return;
            var name = AddImageResource(p, img, "label");
            p.Meta.Generators[name] = gen;
            AddLayout(p, name, theme, cx - img.W / 2, cy - img.H / 2);
        }

        public static void AddImage(FaceProject p, RgbaImage img, int theme, int cx, int cy)
        {
            var name = AddImageResource(p, img, "image");
            p.Meta.Generators[name] = new Generator(GenKind.Image);
            AddLayout(p, name, theme, cx - img.W / 2, cy - img.H / 2);
        }

        public static void AddAnimation(FaceProject p, List<RgbaImage> frames, int interval, int theme, int cx, int cy)
        {
            if (frames.Count == 0) return;
            var arr = AddFrames(p, frames, "frames");
            var name = p.UniqueName("animation");
            var e = new XNode("Sprite");
            e.Set("name", name).Set("ref", "@" + arr).Set("interval", interval).Set("repeatCount", 0);
            p.Resources.Kids.Add(e);
            AddLayout(p, name, theme, cx - frames[0].W / 2, cy - frames[0].H / 2);
        }

        public static void AddPointer(FaceProject p, string source, Generator gen, int theme, int cx, int cy)
        {
            var img = AssetFactory.Hand(gen.Length, gen.Width, gen.Color);
            var r = AddImageResource(p, img, "hand");
            var name = p.UniqueName("pointer");
            p.Meta.Generators[name] = gen;
            var range = PointerRange(source);
            var e = new XNode("DataItemPointer");
            e.Set("name", name).Set("source", source).Set("ref", "@" + r).Set("param", 1000).Set("renderRule", "alwaysShow")
             .Set("valueStart", 0).Set("valueRange", range[0])
             .Set("pivotX", img.W / 2).Set("pivotY", img.H - img.W / 2)
             .Set("angleStart", 0).Set("angleRange", range[1]);
            p.Resources.Kids.Add(e);
            AddLayout(p, name, theme, cx - img.W / 2, cy - (img.H - img.W / 2));
        }

        /// <summary>(діапазон значень, кут) для стрілок годинника</summary>
        public static int[] PointerRange(string source)
        {
            if (source.Contains("Hour")) return new[] { 24, 720 };
            if (source.Contains("Minute") || source.Contains("Second")) return new[] { 60, 360 };
            return new[] { 100, 360 };
        }

        public static RgbaImage ArcImage(Generator g, string color) => AssetFactory.ArcSegment(g.Radius, g.Width, color, g.Start, g.Range, g.Round);

        public static RgbaImage LineImage(Generator g, string color, out System.Windows.Point s, out System.Windows.Point e)
            => AssetFactory.LineSegment(g.Length, g.Width, color, g.Angle, g.Round, out s, out e);

        /// <summary>Параметри дуги/лінії з самого маніфесту (кут, кінці) — для старих проєктів і після правки XML</summary>
        public static Generator Synced(XNode res, Generator gen)
        {
            if (gen == null) return null;
            var g = gen.Copy();
            g.Round = res.Str("endingStyle") != "normal";
            if (gen.Kind == GenKind.Arc) { g.Start = res.Int("angleStart"); g.Range = res.Int("angleRange"); }
            if (gen.Kind == GenKind.Line)
            {
                double dx = res.Int("endX") - res.Int("startX"), dy = res.Int("endY") - res.Int("startY");
                if (dx != 0 || dy != 0) { g.Angle = Math.Round(Math.Atan2(dy, dx) * 180 / Math.PI, 1); g.Length = Math.Round(Math.Sqrt(dx * dx + dy * dy)); }
            }
            return g;
        }

        public static void AddArc(FaceProject p, string source, Generator gen, int theme, int cx, int cy)
        {
            var fg = ArcImage(gen, gen.Color);
            var bg = ArcImage(gen, gen.BgColor);
            // фон перед основною — як їх упорядковує компілятор (стабільні id після розпакування)
            var bgName = AddImageResource(p, bg, "arcBg");
            var fgName = AddImageResource(p, fg, "arc");
            var name = p.UniqueName("arc");
            p.Meta.Generators[name] = gen;
            var e = new XNode("DataItemArcProgressBar");
            e.Set("name", name).Set("source", source).Set("ref", "@" + fgName).Set("bg", "@" + bgName)
             .Set("endingStyle", gen.Round ? "round" : "normal").Set("renderRule", "alwaysShow").Set("valueStart", 0).Set("valueRange", 100)
             .Set("angleStart", (int)Math.Round(gen.Start)).Set("angleRange", (int)Math.Round(gen.Range)).Set("pivotX", fg.W / 2).Set("pivotY", fg.H / 2)
             .Set("barRadius", (int)gen.Radius).Set("barWidth", (int)gen.Width);
            p.Resources.Kids.Add(e);
            AddLayout(p, name, theme, cx - fg.W / 2, cy - fg.H / 2);
        }

        public static void AddLine(FaceProject p, string source, Generator gen, int theme, int cx, int cy)
        {
            var fg = LineImage(gen, gen.Color, out var s, out var en);
            var bg = LineImage(gen, gen.BgColor, out _, out _);
            var bgName = AddImageResource(p, bg, "barBg");
            var fgName = AddImageResource(p, fg, "bar");
            var name = p.UniqueName("line");
            p.Meta.Generators[name] = gen;
            var e = new XNode("DataItemLineProgressBar");
            e.Set("name", name).Set("source", source).Set("ref", "@" + fgName).Set("bg", "@" + bgName)
             .Set("endingStyle", gen.Round ? "round" : "normal").Set("renderRule", "alwaysShow").Set("valueStart", 0).Set("valueRange", 100);
            SetEnds(e, s, en, gen.Width);
            p.Resources.Kids.Add(e);
            AddLayout(p, name, theme, cx - fg.W / 2, cy - fg.H / 2);
        }

        /// <summary>Три стрілки (години, хвилини, секунди) і центральна крапка</summary>
        public static void AddAnalogClock(FaceProject p, int theme, int cx, int cy)
        {
            AddPointer(p, "timeHour", new Generator(GenKind.Pointer) { Color = "#FFFFFF", Width = 9, Length = 58 }, theme, cx, cy);
            AddPointer(p, "timeMinute", new Generator(GenKind.Pointer) { Color = "#FFFFFF", Width = 6, Length = 86 }, theme, cx, cy);
            AddPointer(p, "timeSecond", new Generator(GenKind.Pointer) { Color = "#FF9500", Width = 3, Length = 92 }, theme, cx, cy);
            var name = AddImageResource(p, AssetFactory.Dot(14, "#FF9500"), "clockCenter");
            AddLayout(p, name, theme, cx - 7, cy - 7);
        }

        /// <summary>Картинка залежно від значення: пороги рівномірно по діапазону джерела</summary>
        public static void AddValues(FaceProject p, string source, List<RgbaImage> images, int theme, int cx, int cy)
        {
            if (images.Count == 0) return;
            var f0 = images[0];
            var arr = AddFrames(p, images.Select(i => Imaging.Contain(i, f0.W, f0.H)).ToList(), "icons");
            var name = p.UniqueName(source + "Icons");
            var e = new XNode("DataItemImageValues");
            e.Set("name", name).Set("source", source).Set("ref", "@" + arr).Set("renderRule", "alwaysShow").Set("rotation", 0);
            var r = ValueRange(source);
            for (int i = 0; i < images.Count; i++) e.Add("Param").Set("value", r[0] + (r[1] - r[0]) * i / Math.Max(1, images.Count));
            p.Resources.Kids.Add(e);
            AddLayout(p, name, theme, cx - f0.W / 2, cy - f0.H / 2);
        }

        public static int[] ValueRange(string source)
        {
            var l = source.ToLowerInvariant();
            if (l.Contains("heart")) return new[] { 40, 180 };
            if (l.Contains("hour")) return new[] { 0, 24 };
            if (l.Contains("minute") || l.Contains("second")) return new[] { 0, 60 };
            if (l.Contains("week")) return new[] { 0, 7 };
            if (l.Contains("temperature")) return new[] { -20, 40 };
            return new[] { 0, 100 };
        }

        public static void ReplaceValueImages(FaceProject p, XNode res, List<RgbaImage> images)
        {
            if (images.Count == 0) return;
            var f0 = images[0];
            var old = res.Str("ref");
            if (old != null) { res.Remove("ref"); Collect(p, old); }
            var arr = AddFrames(p, images.Select(i => Imaging.Contain(i, f0.W, f0.H)).ToList(), "icons");
            res.Set("ref", "@" + arr);
            var r = ValueRange(res.Str("source") ?? "");
            res.Kids.RemoveAll(k => k.Tag == "Param");
            for (int i = 0; i < images.Count; i++) res.Add("Param").Set("value", r[0] + (r[1] - r[0]) * i / Math.Max(1, images.Count));
        }

        /// <summary>Фонове зображення на весь екран найнижчим шаром</summary>
        public static void AddBackground(FaceProject p, RgbaImage img, int theme)
        {
            var dev = p.Meta.Device;
            var name = AddImageResource(p, Imaging.Cover(img, dev.Width, dev.Height), "background");
            var th = p.Theme(theme);
            if (th == null) return;
            var l = new XNode("Layout");
            l.Set("ref", "@" + name).Set("x", 0).Set("y", 0);
            int first = th.Kids.FindIndex(k => k.Tag == "Layout");
            th.Kids.Insert(first < 0 ? th.Kids.Count : first, l);
        }

        // MARK: Шари

        public static XNode Duplicate(FaceProject p, XNode layout, int theme)
        {
            var th = p.Theme(theme);
            var res = p.ResourceRef(layout.Str("ref"));
            if (th == null || res == null) return null;
            var copy = res.Copy();
            var name = p.UniqueName(res.Str("name") ?? "copy");
            copy.Set("name", name);
            p.Resources.Kids.Add(copy);
            var g = p.Meta.Gen(res.Str("name"));
            if (g != null) p.Meta.Generators[name] = g.Copy();
            var l = layout.Copy();
            l.Set("ref", "@" + name).Set("x", layout.Int("x") + 8).Set("y", layout.Int("y") + 8);
            th.Kids.Add(l);
            return l;
        }

        /// <summary>Видаляє шар; ресурс прибирається, якщо більше ніде не використовується.</summary>
        public static void Delete(FaceProject p, XNode layout, int theme)
        {
            var th = p.Theme(theme);
            if (th == null) return;
            th.Kids.Remove(layout);
            var r = layout.Str("ref");
            if (r != null) Collect(p, r);
        }

        /// <summary>Прибирає ресурс і все, на що лише він посилався.</summary>
        public static void Collect(FaceProject p, string r)
        {
            if (r.Length < 2) return;
            var res = p.ResourceRef(r);
            if (res == null || IsReferenced(p, r)) return;
            ColorVariants.RemoveAll(p, res);
            p.Resources.Kids.Remove(res);
            p.Meta.Generators.Remove(res.Str("name") ?? "");
            var src = res.Str("src");
            if (src != null) p.RemoveFile(src);
            foreach (var c in res.All("Image")) { var s = c.Str("src"); if (s != null) p.RemoveFile(s); }
            var refs = new List<string>();
            foreach (var a in res.Attrs) if (a.Key != "name" && a.Value.Length > 0 && a.Value[0] == 0x40) refs.Add(Bytes.Str(a.Value));
            foreach (var c in res.Elements) { var x = c.Str("ref"); if (x != null) refs.Add(x); }
            foreach (var x in refs) Collect(p, x);
        }

        public static bool IsReferenced(FaceProject p, string r)
        {
            var target = Bytes.Utf8(r);
            bool Scan(XNode n)
            {
                foreach (var a in n.Attrs) if (a.Key != "name" && Bytes.Same(a.Value, target)) return true;
                return n.Kids.Any(Scan);
            }
            return Scan(p.Root);
        }

        /// <summary>Переносить шар на позицію index серед шарів теми (0 — найнижчий)</summary>
        public static void Move(FaceProject p, XNode layout, int theme, int index)
        {
            var th = p.Theme(theme);
            if (th == null) return;
            int i = th.Kids.IndexOf(layout);
            if (i < 0) return;
            int count = th.Kids.Count(k => k.Tag == "Layout");
            th.Kids.RemoveAt(i);
            int target = Math.Max(0, Math.Min(index, count - 1));
            var after = th.Kids.Where(k => k.Tag == "Layout").ToList();
            if (target >= after.Count) th.Kids.Add(layout);
            else th.Kids.Insert(th.Kids.IndexOf(after[target]), layout);
        }

        // MARK: Перемальовування

        public static void Regenerate(FaceProject p, string name, Generator gen)
        {
            var res = p.Resource(name);
            if (res == null) return;
            p.Meta.Generators[name] = gen;
            switch (gen.Kind)
            {
                case GenKind.Digits:
                {
                    var arr = p.ResourceRef(res.Str("ref"));
                    if (arr == null) return;
                    var frames = AssetFactory.DigitFrames(gen);
                    foreach (var c in arr.All("Image")) { var s = c.Str("src"); if (s != null) p.RemoveFile(s); }
                    arr.Kids.Clear();
                    arr.Set("format", frames.Any(f => f.BestFormat() == "RGB565A8") ? "RGB565A8" : "indexed8");
                    var b = arr.Str("name") ?? name;
                    for (int i = 0; i < frames.Count; i++)
                    {
                        var src = b + "/" + i + ".png";
                        p.SetFile(src, frames[i].Png());
                        arr.Add("Image").Set("src", src);
                    }
                    if (gen.Unit.Length > 0 || res.Has("unitIcon")) SetUnit(p, res, gen);
                    break;
                }
                case GenKind.Texts:
                {
                    // кожна картинка елемента — свій рядок шрифтом (дні тижня, місяці, значки…); шляхи файлів лишаються
                    var target = MainImages(p, res);
                    if (target == null) return;
                    var slots = target.Tag == "Image" ? new List<XNode> { target } : target.All("Image");
                    var frames = AssetFactory.TextFrames(gen, gen.Texts);
                    int n = Math.Min(slots.Count, frames.Count);
                    for (int i = 0; i < n; i++)
                    {
                        var src = slots[i].Str("src");
                        if (src != null) p.SetFile(src, frames[i].Png());
                    }
                    if (n > 0) target.Set("format", frames.Take(n).Any(f => f.BestFormat() == "RGB565A8") ? "RGB565A8" : "indexed8");
                    break;
                }
                case GenKind.Arc:
                {
                    // центр дуги лишається на місці, хоч би як змінився розмір картинки
                    var keep = Anchors(p, res, true);
                    var fg = ArcImage(gen, gen.Color);
                    var r = p.ResourceRef(res.Str("ref"));
                    if (r != null) ReplaceImage(p, r, fg);
                    var bg = p.ResourceRef(res.Str("bg"));
                    if (bg != null) ReplaceImage(p, bg, ArcImage(gen, gen.BgColor));
                    res.Set("pivotX", fg.W / 2).Set("pivotY", fg.H / 2).Set("barRadius", (int)gen.Radius).Set("barWidth", (int)gen.Width)
                       .Set("angleStart", (int)Math.Round(gen.Start)).Set("angleRange", (int)Math.Round(gen.Range))
                       .Set("endingStyle", gen.Round ? "round" : "normal");
                    if (res.Has("indicatorRadius")) res.Set("indicatorRadius", (int)gen.Radius);
                    Restore(keep, res, true);
                    break;
                }
                case GenKind.Line:
                {
                    // початок лінії лишається на місці
                    var keep = Anchors(p, res, false);
                    var fg = LineImage(gen, gen.Color, out var s, out var en);
                    var r = p.ResourceRef(res.Str("ref"));
                    if (r != null) ReplaceImage(p, r, fg);
                    var bg = p.ResourceRef(res.Str("bg"));
                    if (bg != null) ReplaceImage(p, bg, LineImage(gen, gen.BgColor, out _, out _));
                    SetEnds(res, s, en, gen.Width);
                    res.Set("endingStyle", gen.Round ? "round" : "normal");
                    Restore(keep, res, false);
                    break;
                }
                case GenKind.Pointer:
                {
                    var img = AssetFactory.Hand(gen.Length, gen.Width, gen.Color);
                    var r = p.ResourceRef(res.Str("ref"));
                    if (r != null) ReplaceImage(p, r, img);
                    res.Set("pivotX", img.W / 2).Set("pivotY", img.H - img.W / 2);
                    break;
                }
                case GenKind.Label:
                {
                    var img = AssetFactory.LabelImage(gen);
                    if (img != null) ReplaceImage(p, res, img);
                    break;
                }
            }
            ColorVariants.Refresh(p, res);
        }

        /// <summary>Основні картинки елемента: те, на що посилається ref (масив чи одна картинка), або сам ресурс-картинка</summary>
        public static XNode MainImages(FaceProject p, XNode res)
        {
            if (res == null) return null;
            if (res.Tag == "Image" || res.Tag == "ImageArray") return res;
            var r = p.ResourceRef(res.Str("ref"));
            return r != null && (r.Tag == "Image" || r.Tag == "ImageArray") ? r : null;
        }

        /// <summary>Скільки картинок намалювати шрифтом</summary>
        public static int SlotCount(FaceProject p, XNode res)
        {
            var t = MainImages(p, res);
            return t == null ? 0 : t.Tag == "Image" ? 1 : t.All("Image").Count;
        }

        static void SetEnds(XNode res, System.Windows.Point s, System.Windows.Point e, double width)
            => res.Set("startX", (int)Math.Round(s.X)).Set("startY", (int)Math.Round(s.Y)).Set("endX", (int)Math.Round(e.X)).Set("endY", (int)Math.Round(e.Y))
                  .Set("barWidth", (int)Math.Round(width));

        /// <summary>Усі шари (на всіх екранах), що показують цей ресурс</summary>
        public static List<XNode> LayoutsOf(FaceProject p, XNode res)
        {
            var o = new List<XNode>();
            for (int t = 0; t < p.Themes.Count; t++) o.AddRange(p.Layouts(t).Where(l => p.ElementOf(l) == res));
            return o;
        }

        /// <summary>Точка прив'язки в координатах циферблата: центр дуги або початок лінії</summary>
        static List<Tuple<XNode, int, int>> Anchors(FaceProject p, XNode res, bool arc)
            => LayoutsOf(p, res).Select(l => Tuple.Create(l, l.Int("x") + (arc ? res.Int("pivotX") : res.Int("startX")),
                                                             l.Int("y") + (arc ? res.Int("pivotY") : res.Int("startY")))).ToList();

        static void Restore(List<Tuple<XNode, int, int>> keep, XNode res, bool arc)
        {
            foreach (var k in keep)
                k.Item1.Set("x", k.Item2 - (arc ? res.Int("pivotX") : res.Int("startX"))).Set("y", k.Item3 - (arc ? res.Int("pivotY") : res.Int("startY")));
        }

        /// <summary>Лінія за двома кінцями в координатах циферблата (перетягування ручок, поля X1 Y1 X2 Y2)</summary>
        public static void PlaceLine(FaceProject p, XNode res, XNode layout, Generator gen, double x1, double y1, double x2, double y2)
        {
            double dx = x2 - x1, dy = y2 - y1;
            var g = gen.Copy();
            g.Length = Math.Max(1, Math.Round(Math.Sqrt(dx * dx + dy * dy)));
            g.Angle = Math.Round(Math.Atan2(dy, dx) * 180 / Math.PI, 1);
            Regenerate(p, res.Str("name"), g);
            layout.Set("x", (int)Math.Round(x1) - res.Int("startX")).Set("y", (int)Math.Round(y1) - res.Int("startY"));
        }

        /// <summary>Значок одиниці біля числа (порожній текст — прибрати)</summary>
        public static void SetUnit(FaceProject p, XNode res, Generator gen)
        {
            var old = res.Str("unitIcon");
            res.Remove("unitIcon");
            if (old != null) Collect(p, old);
            var img = AssetFactory.UnitImage(gen.Unit, gen);
            if (img == null) return;
            var name = AddImageResource(p, img, (res.Str("name") ?? "number") + "_unit");
            res.Set("unitIcon", "@" + name);
        }

        /// <summary>Крапка на кінці заповнення дуги</summary>
        public static void SetIndicator(FaceProject p, XNode res, bool on, double size)
        {
            var old = res.Str("indicatorImage");
            if (old != null) { res.Remove("indicatorImage"); res.Remove("indicatorRadius"); Collect(p, old); }
            if (!on) return;
            int d = Math.Max(6, (int)Math.Round(size * 1.5));
            var name = AddImageResource(p, AssetFactory.Dot(d, "#FFFFFF"), (res.Str("name") ?? "arc") + "_dot");
            res.Set("indicatorImage", "@" + name).Set("indicatorRadius", res.Int("barRadius"));
        }

        /// <summary>Видаляє тему (екран) з її шарами</summary>
        public static void DeleteTheme(FaceProject p, int index)
        {
            var th = p.Theme(index);
            if (th == null || p.Themes.Count < 2) return;
            var refs = th.All("Layout").Select(l => l.Str("ref")).Where(r => r != null).ToList();
            var pv = th.Str("preview");
            if (pv != null) refs.Add(pv);
            p.Root.Kids.Remove(th);
            foreach (var r in refs) Collect(p, r);
        }

        public static void ReplaceImage(FaceProject p, XNode res, RgbaImage img)
        {
            var src = res.Str("src") ?? (res.Str("name") ?? "image") + ".png";
            p.SetFile(src, img.Png());
            res.Set("src", src).Set("format", img.BestFormat());
        }

        // MARK: Дія при натисканні

        /// <summary>Обгортка «натиснув — відкрився застосунок»: Widget з одним елементом і jumpApp, ім'я починається з tap_</summary>
        public static XNode TapInner(FaceProject p, XNode r)
        {
            if (r.Tag != "Widget" || !(r.Str("name") ?? "").StartsWith("tap_") || !r.Has("jumpApp")) return null;
            var items = r.All("Item");
            return items.Count == 1 ? p.ResourceRef(items[0].Str("ref")) : null;
        }

        public static string TapApp(FaceProject p, XNode layout)
        {
            var r = p.ResourceRef(layout.Str("ref"));
            return r != null && TapInner(p, r) != null ? r.Str("jumpApp") : null;
        }

        /// <summary>Дія натискання: елемент загортається у віджет розміру його рамки (або розгортається назад)</summary>
        public static void SetTapApp(FaceProject p, XNode layout, int theme, string app)
        {
            var r = p.ResourceRef(layout.Str("ref"));
            if (r == null) return;
            int lx = layout.Int("x"), ly = layout.Int("y");
            var inner = TapInner(p, r);
            if (inner != null)
            {
                var item = r.All("Item")[0];
                layout.Set("ref", "@" + (inner.Str("name") ?? "")).Set("x", lx + item.Int("x")).Set("y", ly + item.Int("y"));
                p.Resources.Kids.Remove(r);
            }
            if (app == null) return;
            var el = p.ResourceRef(layout.Str("ref"));
            if (el == null) return;
            var box = new FaceRenderer(p).Boxes(theme).FirstOrDefault(b => b.Layout == layout)?.Rect
                      ?? new Rect(layout.Int("x"), layout.Int("y"), 40, 40);
            int bx = (int)Math.Floor(box.X), by = (int)Math.Floor(box.Y);
            int w = Math.Max(8, (int)Math.Ceiling(box.Width)), h = Math.Max(8, (int)Math.Ceiling(box.Height));
            var name = p.UniqueName("tap_" + (el.Str("name") ?? "element"));
            var wg = new XNode("Widget");
            wg.Set("name", name).Set("w", w).Set("h", h).Set("jumpApp", app);
            wg.Add("Item").Set("ref", "@" + (el.Str("name") ?? "")).Set("x", layout.Int("x") - bx).Set("y", layout.Int("y") - by);
            p.Resources.Kids.Add(wg);
            layout.Set("ref", "@" + name).Set("x", bx).Set("y", by);
        }

        /// <summary>Застосунки браслета з назвами (решта jumpApp — службові)</summary>
        public static readonly string[] Apps =
        {
            "heartrate", "sleep", "SpO2", "sport", "activities", "media", "settings", "weather", "timer", "alarm", "chronograph",
            "flashlight", "findPhone", "pressure", "breath", "calendar", "compass", "worldclock", "todo", "womenHealth", "remoteCamera",
            "phone", "contact", "recorder", "barometer", "temperature", "sms", "nfcCard", "sportsRecord", "vitalityValue",
            "trainingStatus", "tomato", "perpetualcalendar", "navigation", "voiceAssistant", "share", "sportsCourse",
        };
    }
}
