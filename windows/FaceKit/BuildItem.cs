// SPDX-License-Identifier: MIT
// Ресурси для збирання: читання з XML (конструктори класів exe), залежності (vtable[3]) і серіалізація (vtable[2]).

using System;
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Faces
{
    sealed class BuildItem
    {
        readonly FaceBuilder b;
        public readonly XNode E;
        public readonly int Type;
        public uint Id;
        public byte ColorGroup;
        public int Theme;
        public string Name = "";

        /// <summary>getId(): (type&lt;&lt;24) | (colorGroup&lt;&lt;19) | (id &amp; 0x7FFFF)</summary>
        public uint RealId => unchecked((((uint)Type << 5 | ColorGroup) << 19) | (Id & 0x7FFFF));

        // Layout / посилання
        byte[] refName = new byte[0];
        int x, y, param;
        // Image / ImageArray
        bool comp, recolor; byte fmt; int w, h;
        byte[] rgba = new byte[0];
        List<byte[]> frames = new List<byte[]>();
        // Sprite
        int interval, repeatCount;
        // File
        byte[] filename = new byte[0], fileData = new byte[0];
        // Translation
        byte[][] strs;
        // Slot
        string slotType = ""; int slotKind; byte[] appWidget; readonly List<byte[]> slotItems = new List<byte[]>();
        // Widget
        byte[] tname, wname = new byte[0]; uint? bg; int[] size;
        byte? jump; byte[] editbox, preview = new byte[0], args;
        readonly List<Tuple<byte[], int, int>> witems = new List<Tuple<byte[], int, int>>();
        int[] flex;   // dir, justify, alignContent, alignItems, gap
        // DataItem
        int kind; ushort src; int rr;
        uint color, fontId, fontWeight; int fontSize, letterSpace;
        int talign, longMode; bool arc; int lineSpace, tw, th, rot;
        int radius, valign, a0, a1; byte[] text = new byte[0]; List<ushort> contents = new List<ushort>();
        int total, dec, dalign; bool lz, tz; int decoff, space;
        byte[] unit = new byte[0]; List<int> vals = new List<int>();
        bool vsSrc, vrSrc; int vs, vr;
        int px, py; byte[] bgRef = new byte[0]; bool round; byte[] ind = new byte[0];
        int rad, bw, indr, sx, sy, ex, ey, ox, oy;

        static readonly Dictionary<string, int> Factory = new Dictionary<string, int>
        {
            ["Layout"] = 0, ["Image"] = 2, ["ImageArray"] = 3, ["Translation"] = 6, ["File"] = 5, ["Sprite"] = 4, ["Slot"] = 8, ["Widget"] = 9,
        };
        static readonly Dictionary<string, int> DiKinds = new Dictionary<string, int>
        {
            ["DataItemText"] = 0, ["DataItemImageNumber"] = 1, ["DataItemImageValues"] = 2,
            ["DataItemPointer"] = 3, ["DataItemArcProgressBar"] = 4, ["DataItemLineProgressBar"] = 5,
        };

        /// <summary>Фабрика ресурсів за тегом.</summary>
        public static BuildItem Create(FaceBuilder b, XNode e)
        {
            if (Factory.TryGetValue(e.Tag, out var t)) return new BuildItem(b, e, t);
            if (e.Tag.StartsWith("DataItem", StringComparison.Ordinal)) return new BuildItem(b, e, 7);
            throw new FaceCompilerException("Unknown entry: " + e.Tag);
        }

        BuildItem(BuildItem o)
        {
            b = o.b; E = o.E; Type = o.Type; Id = o.Id; ColorGroup = o.ColorGroup; Theme = o.Theme; Name = o.Name;
            comp = o.comp; recolor = o.recolor; fmt = o.fmt; w = o.w; h = o.h; rgba = o.rgba; frames = o.frames;
        }
        public BuildItem Clone(byte colorGroup) => new BuildItem(this) { ColorGroup = colorGroup };

        byte[] Required(string k)
        {
            var v = E.Raw(k);
            if (v == null) throw new FaceCompilerException("Error on line " + E.Line + ": field " + k + " is required!");
            return v;
        }

        static T Get<T>(Dictionary<string, T> m, string k, T d) => k != null && m.TryGetValue(k, out var v) ? v : d;

        public BuildItem(FaceBuilder b, XNode e, int type)
        {
            this.b = b; E = e; Type = type;
            switch (type)
            {
                case 0:
                    refName = e.Raw("ref") ?? new byte[0];
                    x = e.Int("x"); y = e.Int("y"); param = e.Int("param");
                    break;
                case 2:
                {
                    Name = e.Str("name") ?? "";
                    comp = e.Str("compressMethod") == "RLEReversed";
                    recolor = e.Bool("recolorEnable");
                    fmt = ParseFormat(e.Raw("format"));
                    var img = LoadImage(e.Raw("src") ?? new byte[0]);
                    w = img.W; h = img.H; rgba = img.Px;
                    var cg = e.Raw("colorGroup");
                    if (cg != null) ColorGroup = GroupIndex(cg);
                    break;
                }
                case 3:
                {
                    Name = e.Str("name") ?? "";
                    comp = e.Str("compressMethod") == "RLEReversed";
                    recolor = e.Bool("recolorEnable");
                    fmt = ParseFormat(e.Raw("format"));
                    foreach (var c in e.All("Image"))
                    {
                        var s = c.Raw("src") ?? new byte[0];
                        var img = LoadImage(s);
                        if (frames.Count > 0 && (img.W != w || img.H != h))
                            throw new FaceCompilerException("Image " + Bytes.Str(s) + " not found has size " + img.W + "x" + img.H + ", but " + w + "x" + h + " expected");
                        if (frames.Count == 0) { w = img.W; h = img.H; }
                        frames.Add(img.Px);
                    }
                    if (frames.Count == 0) throw new FaceCompilerException("ImageArray " + Name + " at line " + e.Line + " should contain at least 1 image!");
                    // виправлення: exe пише colorGroup і для ImageArray, а читає лише для Image —
                    // кольорові варіанти цифр і значків підмінялися копією основних кадрів
                    var cg = e.Raw("colorGroup");
                    if (!b.Quirks && cg != null) ColorGroup = GroupIndex(cg);
                    break;
                }
                case 4:
                    Name = e.Str("name") ?? ""; refName = e.Raw("ref") ?? new byte[0];
                    interval = e.Int("interval"); repeatCount = e.Int("repeatCount");
                    break;
                case 5:
                {
                    Name = e.Str("name") ?? ""; filename = e.Raw("filename") ?? new byte[0];
                    var d = b.Storage.Read(Bytes.Str(filename));
                    if (d == null) throw new FaceCompilerException("File " + Bytes.Str(filename) + " open fail");
                    fileData = d;
                    break;
                }
                case 6:
                    Name = e.Str("name") ?? "";
                    strs = new byte[FaceTables.Languages.Length][];
                    for (int i = 0; i < strs.Length; i++) strs[i] = new byte[0];
                    foreach (var c in e.All("Item"))
                    {
                        var lang = c.Str("language") ?? "";
                        int i = Array.IndexOf(FaceTables.Languages, lang);
                        if (i < 0) { b.Log.Warn("Language " + lang + " in " + Name + " is unknown!"); continue; }
                        strs[i] = c.Raw("str") ?? new byte[0];
                    }
                    break;
                case 8:
                    Name = Bytes.Str(Required("name")); slotType = Bytes.Str(Required("type"));
                    if (slotType == "appWidget") { slotKind = 3; appWidget = Required("appWidgetID"); }
                    else
                    {
                        slotKind = slotType == "time" ? 1 : slotType == "dualTime" ? 6 : 0;
                        foreach (var c in e.All("Item"))
                        {
                            var r = c.Raw("ref");
                            if (r == null) throw new FaceCompilerException("Error on line " + c.Line + ": field ref is required!");
                            slotItems.Add(r);
                        }
                    }
                    break;
                case 9:
                {
                    Name = Bytes.Str(Required("name"));
                    var wn = e.Raw("widgetName") ?? new byte[0];
                    if (wn.Length > 0 && wn[0] == 0x40) tname = wn; else wname = wn;
                    if (e.Has("bg")) bg = Num.ParseColor(e.Raw("bg"));
                    if (e.Has("w") && e.Has("h")) size = new[] { e.Int("w"), e.Int("h") };
                    var ja = e.Str("jumpApp");
                    if (ja != null)
                    {
                        uint jv;
                        if (Lookup.JumpByName.TryGetValue(ja, out var v)) jump = v;
                        else if (!b.Quirks && ja.StartsWith("unknown:0x", StringComparison.Ordinal)
                                 && uint.TryParse(ja.Substring(10), System.Globalization.NumberStyles.HexNumber, null, out jv)) jump = (byte)(jv & 0xFF);
                        else b.Log.Warn("jumpApp=" + ja + " is unknown on line " + e.Line);
                    }
                    editbox = e.Raw("editbox");
                    preview = e.Raw("preview") ?? new byte[0];
                    foreach (var c in e.All("Item"))
                    {
                        var r = c.Raw("ref");
                        if (r == null) throw new FaceCompilerException("Error on line " + c.Line + ": field ref is required!");
                        witems.Add(Tuple.Create(r, c.Int("x"), c.Int("y")));
                    }
                    args = e.Raw("args");
                    var keys = new[] { "flex_direction", "justify_content", "align_content", "align_items", "gap" };
                    if (keys.Any(e.Has))
                        flex = new[] { e.Str("flex_direction") == "column" ? 1 : 0, ParseFlex(e.Str("justify_content")),
                                       ParseFlex(e.Str("align_content")), ParseFlex(e.Str("align_items")), e.Int("gap") };
                    break;
                }
                case 7:
                    LoadDataItem();
                    break;
            }
            if (Name.Length == 0) Name = DefaultName(-1);
        }

        byte GroupIndex(byte[] cg)
        {
            uint c = Num.ParseColor(cg) & 0xFFFFFF;
            int i = b.Colors.IndexOf(c);
            if (i < 0) throw new FaceCompilerException("Color " + Bytes.Str(cg) + " is not specified in Watchface colorGroupTable!");
            return (byte)i;
        }

        /// <summary>Ім'я ресурсу без атрибута name — «Short_theme_id» (або «Short_id» поза темою).</summary>
        public string DefaultName(int t)
        {
            uint id = (uint)Type << 24 | (Id & 0x7FFFF);
            return t == -1 ? ShortName + "_" + Num.HexUpper(id) : ShortName + "_" + t + "_" + Num.HexUpper(id);
        }

        static readonly string[] DiShort = { "Text", "ImageNumber", "ImageValues", "Pointer", "ArcProgress", "LineProgress" };

        string ShortName
        {
            get
            {
                switch (Type)
                {
                    case 0: return "Layout";
                    case 2: return "Image";
                    case 3: return "ImageArray";
                    case 4: return "Sprite";
                    case 5: return "File";
                    case 6: return "Translation";
                    case 8: return "Slot";
                    case 9: return "Widget";
                    default: return DiShort[Math.Min(kind, 5)];
                }
            }
        }

        byte ParseFormat(byte[] s)
        {
            if (s == null || s.Length == 0) return 0;
            switch (Bytes.Str(s))
            {
                case "RGBA32": case "argb8888": return 0;
                case "RGB565A8": return 6;
                case "indexed8": return 0x10;
                default: b.Log.Warn("Unknown image format: " + Bytes.Str(s) + ", assuming RGBA32"); return 0;
            }
        }

        int ParseFlex(string s)
        {
            if (s == null) return 0;
            if (s == "left") return 0;
            if (s == "center") return 1;
            if (s == "right") return 2;
            if (!b.Quirks) { if (s == "flex-start") return 0; if (s == "flex-end") return 2; }   // виправлення: exe пише flex-*
            return 0;
        }

        RgbaImage LoadImage(byte[] s)
        {
            var d = b.Storage.Read(Bytes.Str(s));
            var img = d == null ? null : ImageDecoder.Decode(d);
            if (img == null) throw new FaceCompilerException("Image not found: " + Bytes.Str(s));
            return img;
        }

        // MARK: DataItem

        void LoadDataItem()
        {
            Name = E.Str("name") ?? "";
            if (!DiKinds.TryGetValue(E.Tag, out kind)) throw new FaceCompilerException("Unknown data format: " + E.Tag);
            switch (E.Str("renderRule") ?? "")
            {
                case "hideWhenUnitMismatch": rr = 2; break;
                case "hideWhenOutRange": rr = 4; break;
                default: rr = 0; break;
            }
            if (kind != 0) src = Lookup.SourceId(E.Raw("source"));
            switch (kind)
            {
                case 0:
                {
                    color = Num.ParseColor(E.Raw("color"));
                    int op = Bytes.Clamp(E.Int("opacity", 100), 0, 100);
                    color = (color & 0xFFFFFF) | ((unchecked((uint)(25500 - op * 255)) / 100 & 0xFF) << 24);
                    fontSize = E.Int("fontSize", 10);
                    fontId = Font(E.Str("fontId"), Lookup.FontIdByName, "fontId");
                    fontWeight = Font(E.Str("fontWeight"), Lookup.FontWeightByName, "fontWeight");
                    letterSpace = E.Int("letterSpace");
                    var a = E.Str("align");
                    talign = a == null ? 0 : a == "left" ? 0 : a == "center" ? 1 : a == "right" ? 2 : 1;
                    var m = E.Str("longMode");
                    longMode = m == null ? 1 : m == "wrap" ? 0 : m == "scroll" ? 2 : m == "scroll_circular" ? 3 : m == "clip" ? 4 : 1;
                    var st = E.Str("style");
                    arc = st != null && st != "normal";
                    if (!arc) { lineSpace = E.Int("lineSpace"); tw = E.Int("w"); th = E.Int("h"); rot = unchecked(E.Int("rotation") * 10); }
                    else
                    {
                        radius = E.Int("radius");
                        var va = E.Str("verticalAlign");
                        valign = va == null ? 0 : va == "top" ? 0 : va == "center" ? 1 : va == "bottom" ? 2 : 0;
                        a0 = unchecked(E.Int("startAngle") * 10); a1 = unchecked(E.Int("span") * 10);
                    }
                    text = Required("string");
                    contents = E.All("Content").Select(c => Lookup.SourceId(c.Raw("source"))).ToList();
                    break;
                }
                case 1:
                {
                    refName = Required("ref");
                    total = E.Int("totalDigits"); dec = E.Int("decimalDigits");
                    var a = E.Str("align");
                    dalign = a == null ? 1 : a == "left" ? 1 : a == "center" ? 2 : a == "right" ? 0 : 1;
                    lz = E.Bool("leadingZero"); tz = E.Bool("trailingZero");
                    decoff = E.Int("decimalOffsetX"); space = E.Int("space"); rot = unchecked(E.Int("rotation") * 10);
                    unit = E.Raw("unitIcon") ?? new byte[0];
                    break;
                }
                case 2:
                {
                    var r = E.Raw("ref");
                    if (r == null) throw new FaceCompilerException("Error on line " + E.Line + ": field ref is required!");
                    refName = r; rot = unchecked(E.Int("rotation") * 10);
                    vals = E.All("Param").Select(p => p.Int("value")).ToList();
                    break;
                }
                default:
                    param = E.Int("param", 1000);
                    refName = Required("ref");
                    Val("valueStart", out vsSrc, out vs); Val("valueRange", out vrSrc, out vr);
                    if (kind == 3)
                    {
                        px = E.Int("pivotX"); py = E.Int("pivotY"); a0 = unchecked(E.Int("angleStart") * 10); a1 = unchecked(E.Int("angleRange") * 10);
                    }
                    else
                    {
                        bgRef = E.Raw("bg") ?? new byte[0];
                        round = E.Str("endingStyle") != "normal";
                        ind = E.Raw("indicatorImage") ?? new byte[0];
                        if (kind == 4)
                        {
                            a0 = unchecked(E.Int("angleStart") * 10); a1 = unchecked(E.Int("angleRange") * 10); px = E.Int("pivotX"); py = E.Int("pivotY");
                            rad = E.Int("barRadius"); bw = E.Int("barWidth"); indr = E.Int("indicatorRadius");
                        }
                        else
                        {
                            sx = E.Int("startX"); sy = E.Int("startY"); ex = E.Int("endX"); ey = E.Int("endY");
                            bw = E.Int("barWidth"); ox = E.Int("offsetX"); oy = E.Int("offsetY");
                        }
                    }
                    break;
            }
        }

        void Val(string key, out bool isSrc, out int v)
        {
            var s = E.Raw(key + "Source");
            if (s != null) { isSrc = true; v = Lookup.SourceId(s); return; }
            isSrc = false; v = E.Int(key);
        }

        uint Font(string s, Dictionary<string, uint> table, string what)
        {
            if (s == null) return 0;
            if (table.TryGetValue(s, out var v)) return v;
            if (!b.Quirks) { var n = Num.ToInt(Bytes.Utf8(s)); if (n.HasValue) return unchecked((uint)n.Value); }   // виправлення: exe пише число
            b.Log.Warn("Unknown " + what + "=" + s + " on line " + E.Line);
            return 0;
        }

        // MARK: Залежності з перевіркою типів

        uint L(byte[] r, int t) => b.Lookup(r, t);
        uint L(byte[] r) => b.Lookup(r, -1);

        public List<uint> Deps()
        {
            var o = new List<uint>();
            switch (Type)
            {
                case 0: if (refName.Length > 0) o.Add(L(refName, -1)); break;
                case 4: o.Add(L(refName, 3)); break;
                case 8: foreach (var s in slotItems) o.Add(L(s, -1)); break;
                case 9:
                    if (tname != null) o.Add(L(tname, 6));
                    if (preview.Length > 0) o.Add(L(preview, 2));
                    if (editbox != null) o.Add(L(editbox, 2));
                    if (args != null) o.Add(L(args, 5));
                    foreach (var it in witems) o.Add(L(it.Item1, -1));
                    break;
                case 7:
                    switch (kind)
                    {
                        case 1: o.Add(L(refName, 3)); if (unit.Length > 0) o.Add(L(unit, 2)); break;
                        case 2: o.Add(L(refName, 3)); break;
                        case 3: o.Add(L(refName, 2)); break;
                        case 4:
                        case 5:
                            if (bgRef.Length > 0) o.Add(L(bgRef, 2));
                            o.Add(L(refName, 2));
                            if (ind.Length > 0) o.Add(L(ind, 2));
                            break;
                    }
                    break;
            }
            return o;
        }

        // MARK: Серіалізація

        public byte[] Serialize()
        {
            var o = new ByteWriter();
            switch (Type)
            {
                case 0:
                    o.U32(L(refName)); o.U16(x); o.U16(y); o.U32(param); o.U32(0);
                    break;
                case 2:
                {
                    var raw = PixelFormat.Encode(fmt, rgba, w, h);
                    var data = comp ? Rle.Block(raw, PixelFormat.Bpp(fmt)) : raw;
                    o.Append(new[] { fmt, (byte)((recolor ? 1 : 0) | (comp ? 4 : 0)), (byte)0, (byte)0 });
                    o.U16(w); o.U16(h); o.U32(data.Length); o.Append(data);
                    break;
                }
                case 3:
                {
                    int E2 = PixelFormat.Bpp(fmt);
                    var raws = frames.Select(f => PixelFormat.Encode(fmt, f, w, h)).ToList();
                    var blobs = comp ? raws.Select(r => Rle.Block(r, E2)).ToList() : raws;
                    var tbl = new ByteWriter();
                    if (comp) foreach (var bl in blobs) tbl.U32(bl.Length);
                    int bodyLen = blobs.Sum(bl => bl.Length);
                    int tot = comp ? 12 + tbl.Count + bodyLen : bodyLen;
                    o.Append(new[] { fmt, (byte)frames.Count, (byte)((recolor ? 1 : 0) | (comp ? 4 : 0)), (byte)0 });
                    o.U16(w); o.U16(h); o.U32(tot); o.Append(tbl.Buf);
                    foreach (var bl in blobs) o.Append(bl);
                    // exe: нестиснутий масив пишеться довжиною total (без 12 байт заголовка) — хвіст обрізано
                    if (b.Quirks && !comp) return o.Buf.Take(tot).ToArray();
                    break;
                }
                case 4:
                    o.U32(L(refName)); o.U16(0); o.U16(interval); o.U32(repeatCount);
                    break;
                case 5:
                    o.U32((fileData.Length & 0xFFFFFF) | ((filename.Length & 0xFF) << 24)); o.Zeros(16); o.Append(filename); o.Append(fileData);
                    break;
                case 6:
                {
                    ulong mask = 0;
                    var lens = new ByteWriter();
                    var body = new List<byte>();
                    for (int i = 0; i < strs.Length; i++)
                    {
                        if (strs[i].Length == 0) continue;
                        mask |= 1UL << i; lens.U32(strs[i].Length); body.AddRange(strs[i]);
                    }
                    o.U64(mask); o.Append(lens.Buf); o.Append(body);
                    break;
                }
                case 8:
                    if (slotType == "appWidget")
                    {
                        var key = Bytes.Str(appWidget);
                        if (!Lookup.AppWidgetByName.TryGetValue(key, out var v)) throw new FaceCompilerException("appWidgetId '" + key + "' is unknown!");
                        o.U16(0); o.U16(0x30); o.U16(v); o.Zeros(8);
                    }
                    else
                    {
                        o.U8(slotItems.Count); o.U8(0); o.U16((slotKind << 4) & 0xF0);
                        foreach (var r in slotItems) o.U32(L(r));
                    }
                    break;
                case 9:
                {
                    if (tname != null) { o.U32(0xFFFFFFFF); o.U32(L(tname)); o.Zeros(24); }
                    else { var nb = wname.Take(0x1F).ToArray(); o.Append(nb); o.Zeros(0x20 - nb.Length); }
                    int fl = 0; uint bgv = 0;
                    if (bg.HasValue) { fl |= 1; bgv = bg.Value; }
                    if (jump.HasValue) fl = ((fl | 2) & 0xF00F) | (jump.Value << 4);
                    var body = new ByteWriter();
                    foreach (var it in witems) { body.U16(it.Item2); body.U16(it.Item3); body.U32(L(it.Item1)); }
                    var tail = new ByteWriter();
                    if (editbox != null) { fl |= 4; tail.U32(L(editbox)); }
                    if (size != null) { fl |= 0x1000; tail.U32(unchecked((((uint)size[0] & 0xFFFF) << 16) + ((uint)size[1] & 0xFFFF))); }
                    if (args != null) { fl |= 0x2000; tail.U32(L(args)); }
                    if (flex != null)
                    {
                        int gap = flex[4];
                        int g16 = (short)gap;
                        int v = ((Math.Abs(g16) & 0xFF) << 11) + ((((ushort)gap) >> 15) << 20)
                                + ((flex[3] & 0xFF) << 8) + ((flex[2] & 0xFF) << 5) + (flex[1] & 0xFF) * 4 + (flex[0] & 0xFF);
                        fl |= 0x4000; tail.U32(v);
                    }
                    o.U32(bgv); o.U32(preview.Length == 0 ? 0 : L(preview)); o.U8(witems.Count); o.U8(0); o.U16(fl);
                    o.Append(body.Buf); o.Append(tail.Buf);
                    break;
                }
                case 7:
                    return SerializeDataItem();
            }
            return o.ToArray();
        }

        byte[] SerializeDataItem()
        {
            var o = new ByteWriter();
            void Head(int b2, int b3, int prm) { o.U16(src); o.U8(b2); o.U8(b3); o.U16(rr); o.U16(prm); }
            void V(bool isSrc, int x0) { if (isSrc) o.U32((uint)x0 & 0xFFFF); else o.U32(unchecked((uint)(x0 << 8))); }
            int clamp = Bytes.Clamp((ushort)param, 30, 1000);
            switch (kind)
            {
                case 0:
                {
                    int w0 = (fontSize & 0xFF) | (((int)fontId << 8) & 0x3F00) | (((int)fontWeight << 14) & 0x3C000) | ((letterSpace << 18) & 0x3FC0000);
                    int w1 = (talign & 7) | ((longMode << 3) & 0x38) | (arc ? 0x40 : 0);
                    o.Zeros(6); o.U16(1000); o.U32(color); o.U32(w0); o.U32(w1);
                    if (!arc) { o.U32((lineSpace & 0xFF) | ((tw << 8) & 0x3FF00) | ((th << 18) & 0xFFC0000)); o.U16(rot); o.U16(0); }
                    else { o.U32((radius & 0x3FF) | ((valign << 10) & 0xC00)); o.U16(a0); o.U16(a1); }
                    o.Zeros(16);
                    o.U32((text.Length & 0xFF) | ((contents.Count << 8) & 0xF00));
                    o.Append(text);
                    foreach (var c in contents) o.U16(c);
                    break;
                }
                case 1:
                    Head((total & 0xF) | ((dec << 4) & 0xF0), (dalign & 3) | (lz ? 4 : 0) | (tz ? 8 : 0) | 0x10, 1000);
                    o.U32(L(refName)); o.U8(decoff); o.U8(space); o.U16(rot); o.U32(unit.Length == 0 ? 0 : L(unit));
                    break;
                case 2:
                    Head(0, 0x20, 1000);
                    o.U32(L(refName)); o.U8(0); o.U8(vals.Count == 0 ? 0 : 2); o.U16(rot);
                    foreach (var v in vals) o.U32(v);
                    break;
                case 3:
                    Head(0, 0x30, clamp);
                    o.U32(L(refName)); V(vsSrc, vs); V(vrSrc, vr); o.U16(px); o.U16(py); o.U16(a0); o.U16(a1);
                    o.U32((vsSrc ? 4 : 0) | (vrSrc ? 8 : 0));
                    break;
                default:
                {
                    int fl = (vsSrc ? 4 : 0) | (vrSrc ? 8 : 0) | (round ? 1 : 0) | (ind.Length == 0 ? 0 : 2);
                    Head(0, kind << 4, clamp);
                    o.U32(L(refName)); o.U32(bgRef.Length == 0 ? 0 : L(bgRef)); o.U32(fl); V(vsSrc, vs); V(vrSrc, vr);
                    if (kind == 4)
                    {
                        o.U16(px); o.U16(py); o.U16(a0); o.U16(a1); o.U16(rad); o.U16(bw);
                        if (ind.Length > 0) { o.U32(L(ind)); o.U16(indr); o.Zeros(6); }
                    }
                    else
                    {
                        o.U16(sx); o.U16(sy); o.U16(ex); o.U16(ey); o.U16(0); o.U16(bw);
                        if (ind.Length > 0) { o.U32(L(ind)); o.U16(ox); o.U16(oy); o.Zeros(4); }
                    }
                    break;
                }
            }
            return o.ToArray();
        }
    }
}
