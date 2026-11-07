// SPDX-License-Identifier: MIT
// Мінімальний XML у стилі tinyxml2: розбір із номерами рядків і друк з відступом 4 пробіли.
// Значення атрибутів зберігаються як байти UTF-8 без перетворень (exe теж працює з сирими байтами).

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace BandFace.Faces
{
    /// <summary>Елемент XML (значення атрибутів — сирі байти UTF-8).</summary>
    public sealed class XNode
    {
        public readonly string Tag;
        public readonly List<KeyValuePair<string, byte[]>> Attrs = new List<KeyValuePair<string, byte[]>>();
        public List<XNode> Kids = new List<XNode>();
        public int Line;
        public bool IsComment;

        public XNode(string tag, int line = 0) { Tag = tag; Line = line; }
        public static XNode Comment(string text) => new XNode(text) { IsComment = true };

        public byte[] Raw(string k)
        {
            foreach (var a in Attrs) if (a.Key == k) return a.Value;
            return null;
        }
        public string Str(string k) { var r = Raw(k); return r == null ? null : Bytes.Str(r); }
        public bool Has(string k) => Raw(k) != null;
        /// <summary>IntAttribute(name, default)</summary>
        public int Int(string k, int d = 0) => Num.ToInt(Raw(k)) ?? d;
        /// <summary>BoolAttribute(name, default)</summary>
        public bool Bool(string k, bool d = false) => Num.ToBool(Raw(k)) ?? d;
        public IEnumerable<XNode> Elements => Kids.Where(k => !k.IsComment);
        public XNode First(string tag) => Kids.FirstOrDefault(k => !k.IsComment && k.Tag == tag);
        public List<XNode> All(string tag) => Kids.Where(k => !k.IsComment && k.Tag == tag).ToList();

        public XNode Add(string tag) { var e = new XNode(tag); Kids.Add(e); return e; }
        public XNode Set(string k, byte[] v)
        {
            for (int i = 0; i < Attrs.Count; i++)
                if (Attrs[i].Key == k) { Attrs[i] = new KeyValuePair<string, byte[]>(k, v); return this; }
            Attrs.Add(new KeyValuePair<string, byte[]>(k, v));
            return this;
        }
        public XNode Set(string k, string v) => Set(k, Bytes.Utf8(v));
        public XNode Set(string k, int v) => Set(k, v.ToString(System.Globalization.CultureInfo.InvariantCulture));
        public XNode SetU(string k, uint v) => Set(k, v.ToString(System.Globalization.CultureInfo.InvariantCulture));
        public XNode Set(string k, bool v) => Set(k, v ? "true" : "false");
        public void Remove(string k) => Attrs.RemoveAll(a => a.Key == k);

        /// <summary>Глибока копія.</summary>
        public XNode Copy()
        {
            var n = new XNode(Tag, Line) { IsComment = IsComment };
            n.Attrs.AddRange(Attrs);
            n.Kids = Kids.Select(k => k.Copy()).ToList();
            return n;
        }
    }

    public sealed class XmlParseException : Exception
    {
        public XmlParseException(string m) : base(m) { }
    }

    public static class Xml
    {
        static readonly byte[] Amp = Bytes.Utf8("&amp;"), Lt = Bytes.Utf8("&lt;"), Gt = Bytes.Utf8("&gt;"), Quot = Bytes.Utf8("&quot;"), Apos = Bytes.Utf8("&apos;");

        public static void Escape(byte[] v, List<byte> o)
        {
            foreach (var c in v)
            {
                switch (c)
                {
                    case 0x26: o.AddRange(Amp); break;
                    case 0x3C: o.AddRange(Lt); break;
                    case 0x3E: o.AddRange(Gt); break;
                    case 0x22: o.AddRange(Quot); break;
                    case 0x27: o.AddRange(Apos); break;
                    default: o.Add(c); break;
                }
            }
        }

        /// <summary>XMLPrinter: заголовок, відступ 4 пробіли, LF.</summary>
        public static byte[] Print(XNode root)
        {
            var o = new List<byte>(Bytes.Utf8("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"));
            Write(root, 0, o);
            return o.ToArray();
        }

        static void Write(XNode e, int depth, List<byte> o)
        {
            for (int i = 0; i < depth * 4; i++) o.Add(0x20);
            if (e.IsComment) { o.AddRange(Bytes.Utf8("<!--" + e.Tag + "-->\n")); return; }
            o.Add(0x3C); o.AddRange(Bytes.Utf8(e.Tag));
            foreach (var a in e.Attrs)
            {
                o.Add(0x20); o.AddRange(Bytes.Utf8(a.Key)); o.Add(0x3D); o.Add(0x22);
                Escape(a.Value, o); o.Add(0x22);
            }
            if (e.Kids.Count == 0) { o.Add(0x2F); o.Add(0x3E); o.Add(0x0A); return; }
            o.Add(0x3E); o.Add(0x0A);
            foreach (var k in e.Kids) Write(k, depth + 1, o);
            for (int i = 0; i < depth * 4; i++) o.Add(0x20);
            o.Add(0x3C); o.Add(0x2F); o.AddRange(Bytes.Utf8(e.Tag)); o.Add(0x3E); o.Add(0x0A);
        }

        /// <summary>Документ → корінь (перший елемент верхнього рівня).</summary>
        public static XNode Parse(byte[] data) => new Parser(data).Run();

        sealed class Parser
        {
            readonly byte[] d;
            readonly int n;
            int p, line = 1;

            public Parser(byte[] data)
            {
                d = data; n = data.Length;
                if (n >= 3 && d[0] == 0xEF && d[1] == 0xBB && d[2] == 0xBF) p = 3;
            }

            XmlParseException Fail(string m) => new XmlParseException(m + " Line number=" + line);
            void Adv(int k = 1) { for (int i = 0; i < k; i++) if (p < n) { if (d[p] == 0x0A) line++; p++; } }
            bool Starts(string s)
            {
                var b = Encoding.ASCII.GetBytes(s);
                if (p + b.Length > n) return false;
                for (int i = 0; i < b.Length; i++) if (d[p + i] != b[i]) return false;
                return true;
            }
            void SkipWS() { while (p < n && (d[p] == 0x20 || d[p] == 0x09 || d[p] == 0x0A || d[p] == 0x0D)) Adv(); }
            void SkipUntil(string s)
            {
                while (p < n && !Starts(s)) Adv();
                if (p >= n) throw Fail("Error=XML_ERROR_PARSING");
                Adv(s.Length);
            }
            static bool IsNameChar(byte c) =>
                c >= 0x80 || (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
                || c == 0x5F || c == 0x3A || c == 0x2E || c == 0x2D;
            string Name()
            {
                int s = p;
                while (p < n && IsNameChar(d[p])) p++;
                return Encoding.UTF8.GetString(d, s, p - s);
            }

            byte[] Unescape(int start, int end)
            {
                var o = new List<byte>(end - start);
                int i = start;
                while (i < end)
                {
                    if (d[i] == 0x26)
                    {
                        int semi = -1;
                        for (int k = i + 1; k < end && k - i <= 12; k++) if (d[k] == 0x3B) { semi = k; break; }
                        if (semi > 0)
                        {
                            var ent = Encoding.UTF8.GetString(d, i + 1, semi - i - 1);
                            byte[] rep = null;
                            switch (ent)
                            {
                                case "amp": rep = new byte[] { 0x26 }; break;
                                case "lt": rep = new byte[] { 0x3C }; break;
                                case "gt": rep = new byte[] { 0x3E }; break;
                                case "quot": rep = new byte[] { 0x22 }; break;
                                case "apos": rep = new byte[] { 0x27 }; break;
                                default:
                                    uint u;
                                    if ((ent.StartsWith("#x") || ent.StartsWith("#X")) && uint.TryParse(ent.Substring(2), System.Globalization.NumberStyles.HexNumber, null, out u) && u <= 0x10FFFF && (u < 0xD800 || u > 0xDFFF))
                                        rep = Bytes.Utf8(char.ConvertFromUtf32((int)u));
                                    else if (ent.StartsWith("#") && uint.TryParse(ent.Substring(1), out u) && u <= 0x10FFFF && (u < 0xD800 || u > 0xDFFF))
                                        rep = Bytes.Utf8(char.ConvertFromUtf32((int)u));
                                    break;
                            }
                            if (rep != null) { o.AddRange(rep); i = semi + 1; continue; }
                        }
                    }
                    // нормалізація кінців рядків як у tinyxml2: CR LF → LF, CR → LF
                    if (d[i] == 0x0D)
                    {
                        o.Add(0x0A); i++;
                        if (i < end && d[i] == 0x0A) i++;
                        continue;
                    }
                    o.Add(d[i]); i++;
                }
                return o.ToArray();
            }

            public XNode Run()
            {
                XNode root = null;
                var stack = new List<XNode>();
                while (true)
                {
                    while (p < n && d[p] != 0x3C) Adv();     // текст між тегами ігнорується
                    if (p >= n) break;
                    if (Starts("<?")) { SkipUntil("?>"); continue; }
                    if (Starts("<!--"))
                    {
                        Adv(4);
                        int s = p;
                        while (p < n && !Starts("-->")) Adv();
                        if (p >= n) throw Fail("Error=XML_ERROR_PARSING_COMMENT");
                        if (stack.Count > 0) stack[stack.Count - 1].Kids.Add(XNode.Comment(Encoding.UTF8.GetString(d, s, p - s)));
                        Adv(3);
                        continue;
                    }
                    if (Starts("<![CDATA[")) { SkipUntil("]]>"); continue; }
                    if (Starts("<!")) { SkipUntil(">"); continue; }
                    if (Starts("</"))
                    {
                        Adv(2);
                        var nm = Name(); SkipWS();
                        if (p >= n || d[p] != 0x3E) throw Fail("Error=XML_ERROR_PARSING_ELEMENT");
                        Adv();
                        if (stack.Count == 0 || stack[stack.Count - 1].Tag != nm) throw Fail("Error=XML_ERROR_MISMATCHED_ELEMENT");
                        stack.RemoveAt(stack.Count - 1);
                        continue;
                    }
                    Adv();
                    var el = new XNode(Name(), line);
                    if (el.Tag.Length == 0) throw Fail("Error=XML_ERROR_PARSING_ELEMENT");
                    while (true)
                    {
                        SkipWS();
                        if (p >= n) throw Fail("Error=XML_ERROR_PARSING_ELEMENT");
                        if (d[p] == 0x2F)
                        {
                            Adv();
                            if (p >= n || d[p] != 0x3E) throw Fail("Error=XML_ERROR_PARSING_ELEMENT");
                            Adv();
                            if (stack.Count > 0) stack[stack.Count - 1].Kids.Add(el); else if (root == null) root = el;
                            break;
                        }
                        if (d[p] == 0x3E)
                        {
                            Adv();
                            if (stack.Count > 0) stack[stack.Count - 1].Kids.Add(el); else if (root == null) root = el;
                            stack.Add(el);
                            break;
                        }
                        var k = Name();
                        if (k.Length == 0) throw Fail("Error=XML_ERROR_PARSING_ATTRIBUTE");
                        SkipWS();
                        if (p >= n || d[p] != 0x3D) throw Fail("Error=XML_ERROR_PARSING_ATTRIBUTE");
                        Adv(); SkipWS();
                        if (p >= n || (d[p] != 0x22 && d[p] != 0x27)) throw Fail("Error=XML_ERROR_PARSING_ATTRIBUTE");
                        byte q = d[p]; Adv();
                        int s = p;
                        while (p < n && d[p] != q) Adv();
                        if (p >= n) throw Fail("Error=XML_ERROR_PARSING_ATTRIBUTE");
                        var v = Unescape(s, p); Adv();
                        if (el.Raw(k) != null) throw Fail("Error=XML_ERROR_PARSING_ATTRIBUTE");
                        el.Attrs.Add(new KeyValuePair<string, byte[]>(k, v));
                    }
                }
                if (stack.Count > 0) throw Fail("Error=XML_ERROR_MISMATCHED_ELEMENT");
                return root;
            }
        }
    }
}
