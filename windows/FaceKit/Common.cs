// SPDX-License-Identifier: MIT
// Порт WatchfaceCompiler 0.9.8 (з Swift-версії BandFace): спільні типи, байтові помічники, розбір чисел і кольорів як у exe.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace BandFace.Faces
{
    /// <summary>Критична помилка компілятора (exe: «Critical error: …»).</summary>
    public sealed class FaceCompilerException : Exception
    {
        public FaceCompilerException(string message) : base(message) { }
    }

    /// <summary>Налаштування порту.</summary>
    public sealed class FaceCompilerOptions
    {
        /// <summary>Відтворювати відомі помилки exe (для побайтової звірки). Типово — виправлена поведінка.</summary>
        public bool ExeQuirks;
        /// <summary>Кольорові варіанти: копіювати в кожен колір і незмінні картинки (як exe).
        /// false — файл менший, але Smart Band 10 тоді перезавантажується при виборі кольору.</summary>
        public bool ColorCopies = true;
    }

    /// <summary>Журнал повідомлень компілятора.</summary>
    public sealed class FaceCompilerLog
    {
        public readonly List<KeyValuePair<bool, string>> Lines = new List<KeyValuePair<bool, string>>();   // true — попередження
        public Action<bool, string> OnLine;
        internal void Info(string s) { Lines.Add(new KeyValuePair<bool, string>(false, s)); OnLine?.Invoke(false, s); }
        internal void Warn(string s) { Lines.Add(new KeyValuePair<bool, string>(true, s)); OnLine?.Invoke(true, s); }
        public IEnumerable<string> Warnings => Lines.Where(l => l.Key).Select(l => l.Value);
    }

    // MARK: Сховище файлів проєкту

    /// <summary>Доступ до файлів проєкту циферблата (шляхи відносні, з «/»).</summary>
    public interface IFaceStorage
    {
        byte[] Read(string path);
        void Write(string path, byte[] data);
    }

    /// <summary>Файли в пам'яті.</summary>
    public sealed class MemoryStorage : IFaceStorage
    {
        public readonly Dictionary<string, byte[]> Files;
        public MemoryStorage(Dictionary<string, byte[]> files = null) { Files = files ?? new Dictionary<string, byte[]>(); }
        public byte[] Read(string path) { return Files.TryGetValue(Normalize(path), out var d) ? d : null; }
        public void Write(string path, byte[] data) { Files[Normalize(path)] = data; }

        public static string Normalize(string p)
        {
            var parts = new List<string>();
            foreach (var c in p.Replace('\\', '/').Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (c == ".") continue;
                if (c == ".." && parts.Count > 0) { parts.RemoveAt(parts.Count - 1); continue; }
                parts.Add(c);
            }
            return string.Join("/", parts);
        }
    }

    /// <summary>Файли в теці на диску.</summary>
    public sealed class DirectoryStorage : IFaceStorage
    {
        public readonly string Root;
        public DirectoryStorage(string root) { Root = root; }
        string Full(string p) => Path.Combine(Root, MemoryStorage.Normalize(p).Replace('/', Path.DirectorySeparatorChar));
        public byte[] Read(string path) { try { var f = Full(path); return File.Exists(f) ? File.ReadAllBytes(f) : null; } catch (Exception) { return null; } }
        public void Write(string path, byte[] data)
        {
            var f = Full(path);
            Directory.CreateDirectory(Path.GetDirectoryName(f));
            File.WriteAllBytes(f, data);
        }
    }

    // MARK: Байти

    static class Bytes
    {
        public static byte U8(this byte[] a, int o) => o >= 0 && o < a.Length ? a[o] : (byte)0;
        public static ushort U16(this byte[] a, int o) => (ushort)(a.U8(o) | a.U8(o + 1) << 8);
        public static short I16(this byte[] a, int o) => (short)a.U16(o);
        public static uint U32(this byte[] a, int o) => (uint)a.U16(o) | (uint)a.U16(o + 2) << 16;
        public static int I32(this byte[] a, int o) => (int)a.U32(o);
        public static ulong U64(this byte[] a, int o) => (ulong)a.U32(o) | (ulong)a.U32(o + 4) << 32;

        /// <summary>Відрізок; за межами масиву — нулі (exe читає за кінець запису без перевірки).</summary>
        public static byte[] Slice(this byte[] a, int o, int n)
        {
            if (n <= 0) return new byte[0];
            var r = new byte[n];
            if (o >= 0 && o + n <= a.Length) { Buffer.BlockCopy(a, o, r, 0, n); return r; }
            for (int i = 0; i < n; i++) r[i] = a.U8(o + i);
            return r;
        }

        /// <summary>C-рядок у межах n байт.</summary>
        public static byte[] CStr(this byte[] a, int o, int n)
        {
            var r = new List<byte>();
            for (int i = o; i < o + n && i < a.Length && a[i] != 0; i++) r.Add(a[i]);
            return r.ToArray();
        }

        public static byte[] Utf8(string s) => Encoding.UTF8.GetBytes(s);
        public static string Str(byte[] b) => b == null ? "" : Encoding.UTF8.GetString(b);

        public static bool Same(byte[] a, byte[] b)
        {
            if (a == null || b == null) return a == b;
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        public static byte[] Concat(params byte[][] parts)
        {
            int n = 0;
            foreach (var p in parts) n += p.Length;
            var r = new byte[n];
            int o = 0;
            foreach (var p in parts) { Buffer.BlockCopy(p, 0, r, o, p.Length); o += p.Length; }
            return r;
        }

        public static void Put32(byte[] a, int o, uint v) { a[o] = (byte)v; a[o + 1] = (byte)(v >> 8); a[o + 2] = (byte)(v >> 16); a[o + 3] = (byte)(v >> 24); }
        public static byte[] Le32(uint v) => new[] { (byte)v, (byte)(v >> 8), (byte)(v >> 16), (byte)(v >> 24) };

        public static int Clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
        public static double Clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
    }

    sealed class ByteWriter
    {
        public readonly List<byte> Buf = new List<byte>();
        public void U8(int v) => Buf.Add((byte)v);
        public void U16(int v) { U8(v); U8(v >> 8); }
        public void U32(int v) { U16(v); U16(v >> 16); }
        public void U32(uint v) => U32((int)v);
        public void U64(ulong v) { U32((uint)(v & 0xFFFFFFFF)); U32((uint)(v >> 32)); }
        public void Zeros(int n) { for (int i = 0; i < n; i++) Buf.Add(0); }
        public void Append(byte[] b) => Buf.AddRange(b);
        public void Append(IEnumerable<byte> b) => Buf.AddRange(b);
        public int Count => Buf.Count;
        public byte[] ToArray() => Buf.ToArray();
    }

    // MARK: Числа як у tinyxml2 (XMLUtil::ToInt через MSVC sscanf)

    static class Num
    {
        static bool IsSpace(byte c) => c == 0x20 || (c >= 0x09 && c <= 0x0D);

        public static int HexDigit(byte c)
        {
            if (c >= 0x30 && c <= 0x39) return c - 0x30;
            if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
            if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
            return -1;
        }

        /// <summary>%d / %x з переповненням за модулем 2^32; null — якщо не число.</summary>
        public static int? ToInt(byte[] s)
        {
            if (s == null) return null;
            int i = 0;
            while (i < s.Length && IsSpace(s[i])) i++;
            if (i + 1 < s.Length && s[i] == 0x30 && (s[i + 1] | 0x20) == 0x78)
            {
                int j = i + 2, n0 = 0;
                uint v0 = 0;
                while (j < s.Length && HexDigit(s[j]) >= 0) { v0 = unchecked(v0 * 16 + (uint)HexDigit(s[j])); j++; n0++; }
                return n0 > 0 ? unchecked((int)v0) : 0;
            }
            bool neg = false;
            if (i < s.Length && (s[i] == 0x2B || s[i] == 0x2D)) { neg = s[i] == 0x2D; i++; }
            uint v = 0;
            int n = 0;
            while (i < s.Length && s[i] >= 0x30 && s[i] <= 0x39) { v = unchecked(v * 10 + (uint)(s[i] - 0x30)); i++; n++; }
            if (n == 0) return null;
            return unchecked((int)(neg ? 0 - v : v));
        }

        public static bool? ToBool(byte[] s)
        {
            if (s == null) return null;
            var v = ToInt(s);
            if (v.HasValue) return v.Value != 0;
            switch (Bytes.Str(s))
            {
                case "true": case "True": case "TRUE": return true;
                case "false": case "False": case "FALSE": return false;
                default: return null;
            }
        }

        /// <summary>Колір «#RRGGBB»: null → 0x80000000; результат 0x80RRGGBB.</summary>
        public static uint ParseColor(byte[] s)
        {
            if (s == null) return 0x80000000;
            if (s.Length == 0 || s[0] != 0x23) throw new FaceCompilerException("Color must contain #");
            uint v = 0;
            for (int i = 1; i < s.Length; i++)
            {
                int d = HexDigit(s[i]);
                if (d < 0) throw new FaceCompilerException("unknown symbol");
                v = unchecked(v * 16 + (uint)d);
            }
            return (v & 0xFFFFFF) | 0x80000000;
        }

        /// <summary>Список кольорів через кому.</summary>
        public static List<uint> ParseColorList(byte[] s)
        {
            var r = new List<uint>();
            if (s == null) return r;
            int start = 0;
            for (int i = 0; i <= s.Length; i++)
            {
                if (i < s.Length && s[i] != 0x2C) continue;
                var part = Trim(s, start, i);
                if (part.Length > 0) r.Add(ParseColor(part) & 0xFFFFFF);
                start = i + 1;
            }
            return r;
        }

        static byte[] Trim(byte[] s, int a, int b)
        {
            while (a < b && IsSpace(s[a])) a++;
            while (b > a && IsSpace(s[b - 1])) b--;
            return s.Slice(a, b - a);
        }

        public static string Hex6(uint v) => "#" + (v & 0xFFFFFF).ToString("X6");
        public static string HexUpper(uint v, int width = 0) => v.ToString("X" + (width > 0 ? width.ToString() : ""));
    }

    // MARK: Довідники (std::map)

    static class Lookup
    {
        public static readonly Dictionary<string, ushort> SourceByName = First(FaceTables.Sources.Select(p => new KeyValuePair<string, ushort>(p.Item1, p.Item2)));
        public static readonly Dictionary<ushort, string> SourceById = FirstByName(FaceTables.Sources.Select(p => Tuple.Create(p.Item1, (uint)p.Item2))).ToDictionary(k => (ushort)k.Key, k => k.Value);
        public static readonly Dictionary<string, byte> JumpByName = First(FaceTables.JumpApps.Select(p => new KeyValuePair<string, byte>(p.Item2, p.Item1)));
        public static readonly Dictionary<byte, string> JumpById = FirstByName(FaceTables.JumpApps.Select(p => Tuple.Create(p.Item2, (uint)p.Item1))).ToDictionary(k => (byte)k.Key, k => k.Value);
        public static readonly Dictionary<string, ushort> AppWidgetByName = First(FaceTables.AppWidgets.Select(p => new KeyValuePair<string, ushort>(p.Item1, p.Item2)));
        public static readonly Dictionary<ushort, string> AppWidgetById = FirstByName(FaceTables.AppWidgets.Select(p => Tuple.Create(p.Item1, (uint)p.Item2))).ToDictionary(k => (ushort)k.Key, k => k.Value);
        public static readonly Dictionary<string, uint> FontIdByName = First(FaceTables.FontIds.Select(p => new KeyValuePair<string, uint>(p.Item1, p.Item2)));
        public static readonly Dictionary<uint, string> FontIdById = FirstByName(FaceTables.FontIds);
        public static readonly Dictionary<string, uint> FontWeightByName = First(FaceTables.FontWeights.Select(p => new KeyValuePair<string, uint>(p.Item1, p.Item2)));
        public static readonly Dictionary<uint, string> FontWeightById = FirstByName(FaceTables.FontWeights);

        static Dictionary<K, V> First<K, V>(IEnumerable<KeyValuePair<K, V>> pairs)
        {
            var m = new Dictionary<K, V>();
            foreach (var p in pairs) if (!m.ContainsKey(p.Key)) m[p.Key] = p.Value;
            return m;
        }

        /// <summary>id → назва: перша за побайтовим порядком (std::map).</summary>
        static Dictionary<uint, string> FirstByName(IEnumerable<Tuple<string, uint>> pairs)
        {
            var m = new Dictionary<uint, string>();
            foreach (var p in pairs.OrderBy(q => q.Item1, StringComparer.Ordinal))
                if (!m.ContainsKey(p.Item2)) m[p.Item2] = p.Item1;
            return m;
        }

        public static string SourceName(ushort v) => SourceById.TryGetValue(v, out var s) ? s : Num.HexUpper(v, 4);

        /// <summary>Назва джерела → id: рядок лише з шістнадцяткових цифр — число.</summary>
        public static ushort SourceId(byte[] s)
        {
            s = s ?? new byte[0];
            if (s.Length > 0 && s.All(c => Num.HexDigit(c) >= 0))
            {
                ulong v = 0;
                foreach (var c in s)
                {
                    v = v * 16 + (ulong)Num.HexDigit(c);
                    if (v > 0x7FFFFFFF) throw new FaceCompilerException("stoi argument out of range");
                }
                return (ushort)v;
            }
            if (!SourceByName.TryGetValue(Bytes.Str(s), out var id)) throw new FaceCompilerException("Source unknown: " + Bytes.Str(s));
            return id;
        }
    }
}
