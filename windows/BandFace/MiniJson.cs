using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace BandFace
{
    /// <summary>Мінімальний JSON-розбірник (щоб не підключати зайві бібліотеки): об'єкт → Dictionary, масив → List, число → рядок.</summary>
    static class MiniJson
    {
        public static object Parse(string s)
        {
            int i = 0;
            var v = Value(s, ref i);
            return v;
        }

        static void Ws(string s, ref int i) { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }

        static object Value(string s, ref int i)
        {
            Ws(s, ref i);
            if (i >= s.Length) throw new FormatException("json");
            char c = s[i];
            if (c == '{')
            {
                var d = new Dictionary<string, object>();
                i++; Ws(s, ref i);
                if (s[i] == '}') { i++; return d; }
                while (true)
                {
                    Ws(s, ref i);
                    var k = Str(s, ref i);
                    Ws(s, ref i);
                    if (s[i++] != ':') throw new FormatException("json");
                    d[k] = Value(s, ref i);
                    Ws(s, ref i);
                    if (s[i] == ',') { i++; continue; }
                    if (s[i] == '}') { i++; return d; }
                    throw new FormatException("json");
                }
            }
            if (c == '[')
            {
                var l = new List<object>();
                i++; Ws(s, ref i);
                if (s[i] == ']') { i++; return l; }
                while (true)
                {
                    l.Add(Value(s, ref i));
                    Ws(s, ref i);
                    if (s[i] == ',') { i++; continue; }
                    if (s[i] == ']') { i++; return l; }
                    throw new FormatException("json");
                }
            }
            if (c == '"') return Str(s, ref i);
            int st = i;
            while (i < s.Length && ",}] \t\r\n".IndexOf(s[i]) < 0) i++;
            var t = s.Substring(st, i - st);
            if (t == "null") return null;
            if (t == "true") return "true";
            if (t == "false") return "false";
            return t; // число як рядок
        }

        static string Str(string s, ref int i)
        {
            if (s[i] != '"') throw new FormatException("json");
            i++;
            var sb = new StringBuilder();
            while (s[i] != '"')
            {
                if (s[i] == '\\')
                {
                    i++;
                    switch (s[i])
                    {
                        case 'n': sb.Append('\n'); break;
                        case 'r': sb.Append('\r'); break;
                        case 't': sb.Append('\t'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'u': sb.Append((char)int.Parse(s.Substring(i + 1, 4), NumberStyles.HexNumber)); i += 4; break;
                        default: sb.Append(s[i]); break;
                    }
                    i++;
                }
                else sb.Append(s[i++]);
            }
            i++;
            return sb.ToString();
        }
    }
}
