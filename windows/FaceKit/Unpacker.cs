// SPDX-License-Identifier: MIT
// Розпакування .bin → manifest.xml + PNG + файли (порт завантажувача й запису WatchfaceCompiler 0.9.8).

using System;
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Faces
{
    public sealed class FaceUnpacker
    {
        readonly byte[] b;
        internal readonly FaceCompilerOptions Options;
        readonly FaceCompilerLog log;

        sealed class Theme
        {
            public uint Flags, Preview;
            public int EntryOffset;
            public uint[] Extra;
            public int[][] Tables;
            public readonly List<UnpackItem>[] Items = Enumerable.Range(0, 10).Select(_ => new List<UnpackItem>()).ToArray();
            public UnpackItem PreviewImage;
        }

        readonly uint[] colors;
        readonly int esize;
        readonly List<Theme> themes = new List<Theme>();
        readonly List<UnpackItem> globalItems = new List<UnpackItem>();
        readonly Dictionary<uint, UnpackItem> registry = new Dictionary<uint, UnpackItem>();
        static readonly int[] KnownTypes = { 0, 2, 3, 4, 5, 6, 7, 8, 9 };

        public FaceUnpacker(byte[] data, FaceCompilerOptions options = null, FaceCompilerLog log = null)
        {
            b = data; Options = options ?? new FaceCompilerOptions(); this.log = log ?? new FaceCompilerLog();
            int n = b.U8(0x1D);
            int ncol = n != 0 ? n : (int)b.U32(0x18);
            if (ncol < 0 || ncol > 4096) throw new FaceCompilerException("Invalid colour table");
            colors = Enumerable.Range(0, ncol).Select(i => b.U32(0xA8 + 4 * i)).ToArray();
            esize = b.U32(4) != 0 ? 0xA0 : 0x58;
            int off = 0xA8 + 4 * ncol;
            for (int t = 0; t < b.U8(0x1C); t++)
            {
                int k = esize == 0xA0 ? (int)((b.U32(off + 0x9C) >> 2) & 0xFF) : 0;
                var th = new Theme
                {
                    Flags = b.U32(off), Preview = b.U32(off + 4), EntryOffset = off,
                    Extra = Enumerable.Range(0, k).Select(i => b.U32(off + esize + 4 * i)).ToArray(),
                    Tables = Enumerable.Range(0, 10).Select(i => new[] { (int)b.U32(off + 8 + 8 * i), (int)b.U32(off + 12 + 8 * i) }).ToArray(),
                };
                themes.Add(th);
                off += esize + 4 * k;
            }
            for (int t = 0; t < themes.Count; t++)
            {
                var th = themes[t];
                int p = (int)th.Preview;
                if (p != 0 && th.Preview != 0xFFFFFFFF)
                {
                    int len = (int)b.U32(p + 8);
                    th.PreviewImage = new UnpackItem(this, 2, 0, t, b.Slice(p, 12 + len));
                }
                int eo = th.EntryOffset;
                if (esize == 0xA0 && b.U32(eo + 0x58) == 0xFFFFFFFF)
                {
                    int o = (int)b.U32(eo + 0x64), s = (int)b.U32(eo + 0x68);
                    globalItems.Add(new UnpackItem(this, 6, b.U32(eo + 0x5C), t, b.Slice(o, s)));
                }
            }
            for (int t = 0; t < themes.Count; t++)
                for (int ty = 0; ty < 10; ty++)
                {
                    int c = themes[t].Tables[ty][0], o = themes[t].Tables[ty][1];
                    if (c < 0 || c > 100000) throw new FaceCompilerException("Invalid resource table");
                    for (int i = 0; i < c; i++)
                    {
                        int r = o + 16 * i;
                        uint iid = b.U32(r);
                        int ro = (int)b.U32(r + 8), rs = (int)b.U32(r + 12);
                        if (rs == 0 || ro == 0) continue;
                        int typ = (int)(iid >> 24);
                        if (Array.IndexOf(KnownTypes, typ) < 0) throw new FaceCompilerException("Unknown item: " + Num.HexUpper(iid));
                        var it = new UnpackItem(this, typ, iid, t, b.Slice(ro, rs));
                        themes[t].Items[ty].Add(it);
                        if (!registry.ContainsKey(iid)) registry[iid] = it;
                    }
                }
        }

        internal string RefName(uint rid)
        {
            if (rid == 0) return "@";
            if (!registry.TryGetValue(rid, out var it)) throw new FaceCompilerException("Unknown resource with uid=" + rid.ToString("x"));
            return "@" + it.Name;
        }

        internal void PutColorGroup(XNode e, UnpackItem it)
        {
            if (b.U8(0x1D) != 0 || b.U32(0x18) == 0) return;
            int k = it.Id != 0 ? (int)((it.Id >> 19) & 0x1F) : 0;
            if (k < colors.Length) e.Set("colorGroup", Num.Hex6(colors[k]));
        }

        /// <summary>manifest.xml (LF). Якщо задано сховище — файли пишуться під час обходу, як у exe.</summary>
        public byte[] ManifestXml(IFaceStorage storage = null)
        {
            var root = new XNode("Watchface");
            root.Set("id", b.CStr(0x28, 0x40));
            if (b.U32(0x68) != 0xFFFFFFFF) root.Set("name", b.CStr(0x68, 0x40)); else root.Set("name", "@Translation_" + b.U32(0x6C));
            if (b.U8(0x1D) != 0) root.Set("recolorTable", string.Join(",", colors.Select(Num.Hex6)));
            else if (b.U32(0x18) != 0) root.Set("colorGroupTable", string.Join(",", colors.Select(Num.Hex6)));
            var res = root.Add("Resources");
            foreach (var it in globalItems) it.Xml(res);
            for (int t = 0; t < themes.Count; t++)
            {
                var th = themes[t];
                res.Kids.Add(XNode.Comment("Resources of theme " + t));
                if (th.PreviewImage != null)
                {
                    th.PreviewImage.Xml(res, "preview_" + t);
                    if (storage != null) th.PreviewImage.Save(storage, "preview_" + t);
                }
                for (int ty = 1; ty < 10; ty++)
                    foreach (var it in th.Items[ty])
                    {
                        it.Xml(res);
                        if (storage != null) it.Save(storage);
                    }
            }
            for (int t = 0; t < themes.Count; t++)
            {
                var th = themes[t];
                var e = root.Add("Theme");
                uint aod = esize == 0xA0 ? b.U32(th.EntryOffset + 0x9C) & 3 : 0;
                e.Set("type", (aod != 0 || (t == 1 && (b.U8(0x1E) & 4) != 0)) ? "AOD" : "normal");
                e.Set("name", esize == 0xA0 ? b.CStr(th.EntryOffset + 0x58, 0x40) : new byte[0]);
                e.Set("bgColor", Num.Hex6(th.Flags));
                if (th.PreviewImage != null) e.Set("preview", "@preview_" + t);
                foreach (var it in th.Items[0]) it.Xml(e);
                if (th.Extra.Length > 0)
                    e.Set("colorGroup", string.Join(",", th.Extra.Select(x => Num.Hex6(x < colors.Length ? colors[x] : 0))));
            }
            return Xml.Print(root);
        }

        /// <summary>Записує проєкт: зображення, файли, manifest.xml (CR LF, як exe).</summary>
        public void Save(IFaceStorage storage)
        {
            var xml = new List<byte>();
            foreach (var c in ManifestXml(storage)) { if (c == 0x0A) xml.Add(0x0D); xml.Add(c); }
            storage.Write("manifest.xml", xml.ToArray());
            log.Info("Done!");
        }
    }

    // MARK: Запис ресурсу

    sealed class UnpackItem
    {
        readonly FaceUnpacker face;
        public readonly int Type;
        public readonly uint Id;
        readonly int theme;
        readonly byte[] d;
        readonly int n;

        int kind;
        byte fmt; bool recolor, comp; int w, h;
        byte[] rgba = new byte[0];
        readonly List<byte[]> frames = new List<byte[]>();
        readonly List<KeyValuePair<string, byte[]>> strings = new List<KeyValuePair<string, byte[]>>();

        public UnpackItem(FaceUnpacker face, int type, uint id, int theme, byte[] data)
        {
            this.face = face; Type = type; Id = id; this.theme = theme; d = data; n = data.Length;
            Parse();
        }

        static readonly Dictionary<int, string> Short = new Dictionary<int, string>
        {
            [0] = "Layout", [2] = "Image", [3] = "ImageArray", [4] = "Sprite", [5] = "File", [6] = "Translation", [8] = "Slot", [9] = "Widget",
        };
        static readonly string[] DiShort = { "Text", "ImageNumber", "ImageValues", "Pointer", "ArcProgress", "LineProgress" };

        string ShortName => Type == 7 ? (kind < 6 ? DiShort[kind] : "DataItem") : (Short.TryGetValue(Type, out var s) ? s : "Layout");
        /// <summary>«{Short}_{theme}_{id &amp; 0xFF07FFFF:X}»</summary>
        public string Name => ShortName + "_" + theme + "_" + Num.HexUpper(Id & 0xFF07FFFF);
        string FileName(string nm = null) => nm != null && Id == 0 ? nm : ShortName + "_" + theme + "_" + Num.HexUpper(Id);
        string Ref(uint rid) => face.RefName(rid);
        static int D10(short v) => v / 10;

        void Parse()
        {
            switch (Type)
            {
                case 2:
                {
                    fmt = d.U8(0); recolor = (d.U8(1) & 1) != 0;
                    w = d.U16(4); h = d.U16(6);
                    int len = (int)d.U32(8);
                    var body = d.Slice(12, len);
                    var raw = body;
                    if (body.Length >= 8 && body.U32(0) == Rle.Magic)
                    {
                        uint x = body.U32(4);
                        raw = Rle.Decompress(body, 8, (int)((x >> 4) & 0xFFFFFF), (int)(x & 0xF)); comp = true;
                    }
                    if (PixelFormat.Name(fmt) == null) throw new FaceCompilerException("Unknown color format: " + fmt + " (" + Num.HexUpper(fmt, 2) + ")");
                    rgba = PixelFormat.Decode(fmt, raw, w, h);
                    break;
                }
                case 3:
                {
                    fmt = d.U8(0); int cnt = d.U8(1); recolor = (d.U8(2) & 1) != 0;
                    w = d.U16(4); h = d.U16(6); int total = (int)d.U32(8);
                    int p = 12;
                    var sizes = new List<int>();
                    if ((d.U8(2) & 4) != 0) { for (int i = 0; i < cnt; i++) sizes.Add((int)d.U32(12 + 4 * i)); p += 4 * cnt; }
                    else if (cnt > 0) for (int i = 0; i < cnt; i++) sizes.Add(total / cnt);
                    comp = false;
                    foreach (var s in sizes)
                    {
                        var blob = d.Slice(p, s);
                        var raw = blob;
                        if (blob.Length >= 8 && blob.U32(0) == Rle.Magic)
                        {
                            uint x = blob.U32(4);
                            raw = Rle.Decompress(blob, 8, (int)((x >> 4) & 0xFFFFFF), (int)(x & 0xF)); comp = true;
                        }
                        else comp = false;
                        frames.Add(PixelFormat.Decode(fmt, raw, w, h));
                        p += s;
                    }
                    break;
                }
                case 6:
                {
                    ulong mask = d.U64(0);
                    int cnt = 0;
                    for (int bit = 0; bit < 64; bit++) if (((mask >> bit) & 1) != 0) cnt++;
                    var lens = Enumerable.Range(0, cnt).Select(i => (int)d.U32(8 + 4 * i)).ToArray();
                    int p = 8 + 4 * cnt, k = 0;
                    for (int bit = 0; bit < 64; bit++)
                    {
                        if (((mask >> bit) & 1) == 0) continue;
                        var s = d.Slice(p, lens[k]); p += lens[k]; k++;
                        strings.Add(new KeyValuePair<string, byte[]>(bit < FaceTables.Languages.Length ? FaceTables.Languages[bit] : "lang" + bit, s));
                    }
                    break;
                }
                case 7:
                    kind = d.U8(3) >> 4;
                    if (kind > 5) throw new FaceCompilerException("Unknown data format: " + kind);
                    break;
            }
        }

        // MARK: XML

        public void Xml(XNode parent, string nm = null)
        {
            switch (Type)
            {
                case 0:
                {
                    var e = parent.Add("Layout").Set("ref", Ref(d.U32(0))).Set("x", (int)d.I16(4)).Set("y", (int)d.I16(6));
                    if (d.U32(8) != 0) e.SetU("param", d.U32(8));
                    break;
                }
                case 2:
                {
                    var name = nm ?? Name;
                    var e = parent.Add("Image").Set("name", name).Set("src", FileName(name) + ".png");
                    e.Set("compressMethod", comp ? "RLEReversed" : "none").Set("format", PixelFormat.Name(fmt)).Set("recolorEnable", recolor);
                    face.PutColorGroup(e, this);
                    break;
                }
                case 3:
                {
                    var e = parent.Add("ImageArray").Set("name", Name);
                    e.Set("compressMethod", comp ? "RLEReversed" : "none").Set("format", PixelFormat.Name(fmt) ?? "RGBA32").Set("recolorEnable", recolor);
                    for (int i = 0; i < frames.Count; i++) e.Add("Image").Set("src", FileName() + "/" + i + ".png");
                    face.PutColorGroup(e, this);
                    break;
                }
                case 4:
                    parent.Add("Sprite").Set("name", Name).Set("ref", Ref(d.U32(0)))
                        .SetU("interval", d.U16(6)).SetU("repeatCount", d.U32(8));
                    break;
                case 5:
                {
                    int nl = (int)(d.U32(0) >> 24);
                    var fn = d.CStr(20, nl);
                    parent.Add("File").Set("name", Name).Set("filename", fn.Length == 0 ? Bytes.Utf8(Name) : fn);
                    break;
                }
                case 6:
                {
                    var e = parent.Add("Translation").Set("name", Name);
                    foreach (var s in strings) e.Add("Item").Set("language", s.Key).Set("str", s.Value);
                    break;
                }
                case 7: DataItemXml(parent); break;
                case 8:
                {
                    var e = parent.Add("Slot").Set("name", Name);
                    int k = d.U16(2) & 0xF0;
                    var st = k == 0 ? "widget" : (k == 0x30 ? "appWidget" : "unknown");
                    e.Set("type", st);
                    if (st == "appWidget")
                    {
                        ushort v = d.U16(4);
                        e.Set("appWidgetID", Lookup.AppWidgetById.TryGetValue(v, out var an) ? an : "0x" + Num.HexUpper(v));
                        return;
                    }
                    for (int i = 0; i < d.U8(0); i++) e.Add("Item").Set("ref", Ref(d.U32(4 + 4 * i)));
                    break;
                }
                case 9: WidgetXml(parent); break;
            }
        }

        static readonly string[] FlexNames = { "flex-start", "center", "flex-end" };
        static string Flex(uint v) => v < 3 ? FlexNames[v] : "flex-start";

        void WidgetXml(XNode parent)
        {
            var e = parent.Add("Widget").Set("name", Name);
            if (d.U32(0) == 0xFFFFFFFF) e.Set("widgetName", Ref(d.U32(4))); else e.Set("widgetName", d.CStr(0, 0x20));
            e.Set("groupType", "general");
            int fl = d.U16(0x2A);
            uint bg = d.U32(0x20);
            if ((fl & 1) != 0 && bg != 0) e.Set("bg", Num.Hex6(bg));
            if ((fl & 2) != 0)
            {
                byte j = (byte)((fl >> 4) & 0xFF);
                e.Set("jumpApp", Lookup.JumpById.TryGetValue(j, out var jn) ? jn : "unknown:0x" + Num.HexUpper(j));
            }
            if (d.U32(0x24) != 0) e.Set("preview", Ref(d.U32(0x24)));
            int cnt = d.U8(0x28), p = 0x2C;
            var items = new List<Tuple<uint, int, int>>();
            for (int i = 0; i < cnt; i++) { items.Add(Tuple.Create(d.U32(p + 4), (int)d.I16(p), (int)d.I16(p + 2))); p += 8; }
            if ((fl & 4) != 0) { e.Set("editbox", Ref(d.U32(p))); p += 4; }
            if ((fl & 0x1000) != 0) { e.Set("w", (int)d.U16(p + 2)).Set("h", (int)d.U16(p)); p += 4; }
            if ((fl & 0x2000) != 0) { e.Set("args", Ref(d.U32(p))); p += 4; }
            if ((fl & 0x4000) != 0)
            {
                uint v = d.U32(p);
                int gap = (int)((v >> 11) & 0x1FF);
                if ((v & 0x100000) != 0) gap = -gap;
                e.Set("flex_direction", (v & 3) == 1 ? "column" : "row");
                e.Set("justify_content", Flex((v >> 2) & 7));
                e.Set("align_content", Flex((v >> 5) & 7));
                e.Set("align_items", Flex((v >> 8) & 7));
                e.Set("gap", gap);
            }
            foreach (var it in items) e.Add("Item").Set("ref", Ref(it.Item1)).Set("x", it.Item2).Set("y", it.Item3);
        }

        static string RrName(ushort v) => v == 2 ? "hideWhenUnitMismatch" : (v == 4 ? "hideWhenOutRange" : "alwaysShow");

        void Vals(XNode e, bool unsigned, int o)
        {
            foreach (var kv in new[] { Tuple.Create("valueStart", o), Tuple.Create("valueRange", o + 4) })
            {
                int off = kv.Item2;
                if (d.U8(off) != 0) e.Set(kv.Item1 + "Source", Lookup.SourceName(d.U16(off)));
                else
                {
                    int v = d.I32(off) >> 8;
                    if (unsigned) e.SetU(kv.Item1, unchecked((uint)v)); else e.Set(kv.Item1, v);
                }
            }
        }

        void DataItemXml(XNode parent)
        {
            ushort src = d.U16(0);
            int total = d.U8(2) & 0xF, dec = d.U8(2) >> 4;
            int align = d.U8(3) & 3;
            bool lz = (d.U8(3) & 4) != 0, tz = (d.U8(3) & 8) != 0;
            ushort rr = d.U16(4), param = d.U16(6);
            var nm = Name;
            switch (kind)
            {
                case 0:
                {
                    uint color = d.U32(8), w0 = d.U32(0xC), w1 = d.U32(0x10);
                    var e = parent.Add("DataItemText").Set("name", nm).Set("color", Num.Hex6(color));
                    e.Set("opacity", 100 - (int)(color >> 24) * 100 / 255);
                    uint fid = (w0 >> 8) & 0x3F, fw = (w0 >> 14) & 0xF;
                    if (Lookup.FontIdById.TryGetValue(fid, out var fs)) e.Set("fontId", fs); else e.SetU("fontId", fid);
                    if (Lookup.FontWeightById.TryGetValue(fw, out var ws)) e.Set("fontWeight", ws); else e.SetU("fontWeight", fw);
                    e.SetU("letterSpace", (w0 >> 18) & 0xFF);
                    uint al = w1 & 7, lm = (w1 >> 3) & 7;
                    e.Set("align", al == 1 ? "center" : al == 2 ? "right" : "left");
                    e.Set("longMode", lm == 0 ? "wrap" : lm == 2 ? "scroll" : lm == 3 ? "scroll_circular" : lm == 4 ? "clip" : "dots");
                    if (((w1 >> 6) & 3) == 0)
                    {
                        e.Set("style", "normal").Set("lineSpace", (int)(sbyte)d.U8(0x14));
                        e.SetU("w", (d.U32(0x14) >> 8) & 0x3FF).SetU("h", (d.U32(0x14) >> 18) & 0x3FF);
                        e.Set("rotation", D10(d.I16(0x18)));
                    }
                    else
                    {
                        e.Set("style", "arc").SetU("radius", d.U32(0x14) & 0x3FF);
                        uint va = (d.U32(0x14) >> 10) & 3;
                        e.Set("veritcalAlign", va == 1 ? "center" : va == 2 ? "bottom" : "top");
                        e.Set("startAngle", D10(d.I16(0x18))).Set("span", D10(d.I16(0x1A)));
                    }
                    int len = d.U8(0x2C), ns = (int)((d.U32(0x2C) >> 8) & 0xF);
                    e.Set("string", d.Slice(0x30, len));
                    for (int i = 0; i < ns; i++) e.Add("Content").Set("source", Lookup.SourceName(d.U16(0x30 + len + 2 * i)));
                    break;
                }
                case 1:
                {
                    var e = parent.Add("DataItemImageNumber").Set("name", nm).Set("source", Lookup.SourceName(src));
                    e.Set("ref", Ref(d.U32(8))).Set("totalDigits", total).Set("decimalDigits", dec);
                    e.Set("align", align == 0 ? "right" : (align == 2 ? "center" : "left")).Set("leadingZero", lz).Set("trailingZero", tz);
                    e.Set("renderRule", RrName(rr)).Set("rotation", D10(d.I16(14)));
                    e.Set("decimalOffsetX", (int)(sbyte)d.U8(12)).Set("space", (int)(sbyte)d.U8(13));
                    if (d.U32(16) != 0) e.Set("unitIcon", Ref(d.U32(16)));
                    break;
                }
                case 2:
                {
                    var e = parent.Add("DataItemImageValues").Set("name", nm).Set("source", Lookup.SourceName(src));
                    e.Set("ref", Ref(d.U32(8))).Set("renderRule", RrName(rr)).Set("rotation", D10(d.I16(14)));
                    for (int i = 0; i < Math.Max(0, (n - 16) / 4); i++) e.Add("Param").SetU("value", d.U32(16 + 4 * i));
                    break;
                }
                case 3:
                {
                    var e = parent.Add("DataItemPointer").Set("name", nm).Set("source", Lookup.SourceName(src));
                    e.Set("ref", Ref(d.U32(8))).SetU("param", param).Set("renderRule", RrName(rr));
                    Vals(e, false, 12);
                    e.Set("pivotX", (int)d.I16(20)).Set("pivotY", (int)d.I16(22));
                    e.Set("angleStart", D10(d.I16(24))).Set("angleRange", D10(d.I16(26)));
                    break;
                }
                case 4:
                {
                    var e = parent.Add("DataItemArcProgressBar").Set("name", nm).Set("source", Lookup.SourceName(src));
                    e.Set("ref", Ref(d.U32(8)));
                    if (d.U32(12) != 0) e.Set("bg", Ref(d.U32(12)));
                    e.Set("endingStyle", (d.U32(16) & 1) != 0 ? "round" : "normal").Set("renderRule", RrName(rr));
                    Vals(e, true, 20);
                    e.Set("angleStart", D10(d.I16(32))).Set("angleRange", D10(d.I16(34)));
                    e.Set("pivotX", (int)d.I16(28)).Set("pivotY", (int)d.I16(30));
                    e.Set("barRadius", (int)d.I16(36)).Set("barWidth", (int)d.I16(38));
                    if (n > 0x28 && d.U32(40) != 0) e.Set("indicatorImage", Ref(d.U32(40))).Set("indicatorRadius", (int)d.I16(44));
                    break;
                }
                case 5:
                {
                    var e = parent.Add("DataItemLineProgressBar").Set("name", nm).Set("source", Lookup.SourceName(src));
                    e.Set("ref", Ref(d.U32(8)));
                    // exe друкує bg з неініціалізованого поля (фактично ніколи); порт — якщо задано
                    if (d.U32(12) != 0 && !face.Options.ExeQuirks) e.Set("bg", Ref(d.U32(12)));
                    e.Set("renderRule", RrName(rr));
                    Vals(e, true, 20);
                    e.Set("startX", (int)d.I16(28)).Set("startY", (int)d.I16(30)).Set("endX", (int)d.I16(32)).Set("endY", (int)d.I16(34));
                    e.Set("barWidth", (int)d.I16(38));
                    if ((d.U32(16) & 2) != 0)
                    {
                        uint ind = n > 0x28 ? d.U32(40) : 0;
                        e.Set("indicatorImage", Ref(ind)).Set("offsetX", n > 0x28 ? (int)d.I16(44) : 0).Set("offsetY", n > 0x28 ? (int)d.I16(46) : 0);
                    }
                    break;
                }
            }
        }

        // MARK: Файли

        public void Save(IFaceStorage s, string nm = null)
        {
            switch (Type)
            {
                case 2:
                    s.Write(FileName(nm ?? Name) + ".png", Png.Encode(w, h, rgba));
                    break;
                case 3:
                {
                    // exe кладе кадри в теку з маскованим id (назва ресурсу), хоча src указує на повний id (помилка exe)
                    var dir = face.Options.ExeQuirks ? Name : FileName();
                    for (int i = 0; i < frames.Count; i++) s.Write(dir + "/" + i + ".png", Png.Encode(w, h, frames[i]));
                    break;
                }
                case 5:
                {
                    uint h0 = d.U32(0);
                    int size = (int)(h0 & 0xFFFFFF), nl = (int)(h0 >> 24);
                    var fn = d.CStr(20, nl);
                    s.Write(fn.Length == 0 ? Name : Bytes.Str(fn), d.Slice(20 + nl, Math.Min(size, Math.Max(0, n - 20 - nl))));
                    break;
                }
            }
        }
    }
}
