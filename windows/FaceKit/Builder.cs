// SPDX-License-Identifier: MIT
// Збирання manifest.xml + ресурсів → .bin (порт WatchfaceCompiler 0.9.8: читач маніфесту, фабрика,
// обхід залежностей, серіалізатор).

using System;
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Faces
{
    public sealed class FaceBuilder
    {
        internal readonly IFaceStorage Storage;
        internal readonly FaceCompilerOptions Options;
        internal readonly FaceCompilerLog Log;
        internal bool Quirks => Options.ExeQuirks;

        byte[] header = new byte[0xA8];
        internal List<uint> Colors = new List<uint>();
        readonly SortedDictionary<uint, string> registry = new SortedDictionary<uint, string>();
        readonly Dictionary<string, uint> byName = new Dictionary<string, uint>();
        readonly HashSet<uint> usedIds = new HashSet<uint>();
        readonly Dictionary<int, uint> counters = new Dictionary<int, uint>();
        readonly Dictionary<int, List<BuildItem>> lists = new Dictionary<int, List<BuildItem>>();
        readonly List<BuildTheme> themes = new List<BuildTheme>();

        public FaceBuilder(IFaceStorage storage, FaceCompilerOptions options = null, FaceCompilerLog log = null)
        {
            Storage = storage; Options = options ?? new FaceCompilerOptions(); Log = log ?? new FaceCompilerLog();
        }

        List<BuildItem> ListOf(int t) => lists.TryGetValue(t, out var l) ? l : null;

        // MARK: Реєстр імен

        /// <summary>LOOKUP_ID: "" → 0; перший символ відкидається без перевірки.</summary>
        internal uint Lookup(byte[] r, int want)
        {
            if (r.Length == 0) return 0;
            var key = Bytes.Str(r.Slice(1, r.Length - 1));
            if (!byName.TryGetValue(key, out var id)) throw new FaceCompilerException("Unknown resource with name=" + key);
            if (want != -1 && (int)(id >> 24) != want) throw new FaceCompilerException(key + " is not allowed to reference somewhere");
            return id;
        }

        /// <summary>Призначення id.</summary>
        uint Assign(BuildItem it)
        {
            int t = it.Type;
            if (t != 0 && byName.TryGetValue(it.Name, out var found))
            {
                uint fid = (uint)t << 24 | (found & 0x7FFFF);
                if (usedIds.Contains(fid)) Log.Warn("Found another element with same name: " + it.Name); else usedIds.Add(fid);
                return fid;
            }
            counters.TryGetValue(t, out var n);
            counters[t] = unchecked(n + 1);
            uint id = (uint)t << 24 | n;
            if (!registry.ContainsKey(id))
            {
                registry[id] = it.Name;
                if (byName.TryGetValue(it.Name, out var cur)) { if (id < cur) byName[it.Name] = id; }
                else byName[it.Name] = id;
            }
            return id;
        }

        // MARK: Обхід залежностей теми

        void Walk(BuildTheme ti, BuildItem it)
        {
            foreach (var dep in it.Deps())
            {
                int ty = (int)(dep >> 24);
                if (ty >= 10) throw new FaceCompilerException("Unknown resource with uid=" + dep.ToString("x"));
                var g = ListOf(ty)?.FirstOrDefault(x => x.RealId == dep);
                if (!ti.Tables[ty].Any(x => x.RealId == dep))
                {
                    if (g == null) throw new FaceCompilerException("Unknown resource with uid=" + dep.ToString("x"));
                    ti.Tables[ty].Add(g);
                    Walk(ti, g);
                }
            }
            if (it.Type == 2 || it.Type == 3)
            {
                foreach (var c in ti.ColorGroups)
                {
                    if (c == 0) continue;
                    uint nid = (uint)it.Type << 24 | (c & 0xFF) << 19 | (it.Id & 0x7FFFF);
                    var g = ListOf(it.Type)?.FirstOrDefault(x => x.RealId == nid);
                    if (g != null) ti.Tables[it.Type].Add(g);
                    else if (Options.ColorCopies) ti.Tables[it.Type].Add(it.Clone((byte)(c & 0xFF)));
                }
            }
        }

        static uint Get32(byte[] a, int o) => a.U32(o);

        // MARK: Читання маніфесту

        void Load()
        {
            Log.Info("Reading manifest.xml...");
            var data = Storage.Read("manifest.xml");
            if (data == null) throw new FaceCompilerException("Error opening manifest.xml! Aborting...");
            XNode w;
            try { w = Xml.Parse(data); }
            catch (XmlParseException e) { throw new FaceCompilerException("Error opening manifest.xml: " + e.Message); }
            if (w == null || w.Tag != "Watchface") throw new FaceCompilerException("Watchface should have id parameter!");
            header = new byte[0xA8];
            Bytes.Put32(header, 0, 0x1234A55A); Bytes.Put32(header, 4, 0x10000); Bytes.Put32(header, 8, 0x10000); Bytes.Put32(header, 0x10, 0x800);
            Colors = new List<uint>();
            if (w.Has("recolorTable")) Colors.AddRange(Num.ParseColorList(w.Raw("recolorTable")));
            header[0x1D] = (byte)Colors.Count;
            if (w.Has("colorGroupTable")) Colors.AddRange(Num.ParseColorList(w.Raw("colorGroupTable")));
            Bytes.Put32(header, 0x18, (uint)Colors.Count);
            registry.Clear(); byName.Clear(); usedIds.Clear(); counters.Clear(); lists.Clear(); themes.Clear();
            var res = w.First("Resources");
            if (res != null)
                foreach (var e in res.Elements)
                {
                    var it = BuildItem.Create(this, e);
                    if (!lists.ContainsKey(it.Type)) lists[it.Type] = new List<BuildItem>();
                    lists[it.Type].Add(it);
                    it.Id = Assign(it);
                }
            var themeEls = w.All("Theme");
            if (themeEls.Count == 0) throw new FaceCompilerException("No themes found in watchface!");
            for (int t = 0; t < themeEls.Count; t++)
            {
                var te = themeEls[t];
                var ti = new BuildTheme();
                Bytes.Put32(ti.Entry, 0, Num.ParseColor(te.Raw("bgColor")));
                if (te.Str("type") == "AOD")
                {
                    Bytes.Put32(ti.Entry, 0x9C, (Get32(ti.Entry, 0x9C) & ~2u) | 1); header[0x1E] |= 4;
                }
                var cgt = te.Raw("colorGroupTable");
                if (cgt == null && !Quirks) cgt = te.Raw("colorGroup");   // виправлення: exe пише «colorGroup», а читає «colorGroupTable»
                if (cgt != null)
                {
                    foreach (var c in Num.ParseColorList(cgt))
                    {
                        int i = Colors.IndexOf(c);
                        if (i < 0) throw new FaceCompilerException("Color #" + Num.HexUpper(c, 6) + " is not specified in Watchface colorGroupTable!");
                        ti.ColorGroups.Add((uint)i);
                    }
                    Bytes.Put32(ti.Entry, 0x9C, (Get32(ti.Entry, 0x9C) & ~0x3FCu) | ((uint)(ti.ColorGroups.Count * 4) & 0x3FC));
                }
                var nm = te.Raw("name");
                if (nm != null)
                {
                    if (nm.Length > 0 && nm[0] == 0x40) throw new FaceCompilerException("translations in theme headers are not supported yet");
                    for (int i = 0; i < nm.Length && i < 0x40; i++) ti.Entry[0x58 + i] = nm[i];
                }
                var pv = te.Raw("preview");
                if (pv != null)
                {
                    if (pv.Length == 0 || pv[0] != 0x40) throw new FaceCompilerException("theme preview should be a reference, starts with @. Got: " + Bytes.Str(pv));
                    var key = Bytes.Str(pv.Slice(1, pv.Length - 1));
                    var g = ListOf(2)?.FirstOrDefault(x => x.Name == key);
                    if (g == null) throw new FaceCompilerException("Reference to theme " + t + " preview (" + Bytes.Str(pv) + ") not resolved!");
                    ti.Preview = g;
                }
                themes.Add(ti); header[0x1C] = (byte)themes.Count;
                foreach (var le in te.All("Layout"))
                {
                    var it = new BuildItem(this, le, 0) { Theme = t };
                    it.Name = it.DefaultName(t);      // «Layout_t_0» (id ще не призначено)
                    it.Id = Assign(it);
                    ti.Tables[0].Add(it);
                    Walk(ti, it);
                }
                var files = ListOf(5);
                if (files != null) ti.Tables[5].AddRange(files);
            }
            var wid = w.Raw("id");
            if (wid == null) throw new FaceCompilerException("Watchface should have id parameter!");
            if (wid.Length != 9 && wid.Length != 12) throw new FaceCompilerException("Watchface id must be 9 or 12 digits long!");
            if (!wid.All(c => c >= 0x30 && c <= 0x39)) throw new FaceCompilerException("Watchface id must use digits only!");
            for (int i = 0; i < wid.Length; i++) header[0x28 + i] = wid[i];
            var name = w.Raw("name") ?? new byte[0];
            if (name.Length > 0 && name[0] == 0x40) throw new FaceCompilerException("translation in watchface header is not supported yet");
            for (int i = 0; i < name.Length && i < 0x40; i++) header[0x68 + i] = name[i];
            int anyAOD = (header[0x1E] >> 2) & 1;
            bool slots = themes.Any(x => x.Tables[8].Count > 0);
            int fl = header[0x1E] & ~2;
            if (themes.Count - anyAOD > 1 || slots || Colors.Count > 0) fl |= 2;
            header[0x1E] = (byte)fl;
        }

        // MARK: Серіалізація

        public byte[] Build()
        {
            Log.Info("Packing from project directory");
            Load();
            int off = 0xA8 + 4 * Colors.Count + themes.Sum(x => 0xA0 + 4 * x.ColorGroups.Count);
            foreach (var ti in themes)
                for (int ty = 0; ty < 10; ty++)
                {
                    Bytes.Put32(ti.Entry, 8 + 8 * ty, (uint)ti.Tables[ty].Count); Bytes.Put32(ti.Entry, 12 + 8 * ty, (uint)off);
                    off += 16 * ti.Tables[ty].Count;
                }
            var blobs = new List<byte[]>();
            foreach (var ti in themes)
                if (ti.Preview != null)
                {
                    var d = ti.Preview.Serialize();
                    Bytes.Put32(ti.Entry, 4, (uint)off); blobs.Add(d); off += d.Length;
                }
            Bytes.Put32(header, 0x20, Get32(themes[0].Entry, 4));
            var recs = new ByteWriter();
            foreach (var ti in themes)
                for (int ty = 0; ty < 10; ty++)
                    foreach (var it in ti.Tables[ty])
                    {
                        var d = it.Serialize();
                        recs.U32(it.RealId); recs.U32(0); recs.U32(off); recs.U32(d.Length);
                        blobs.Add(d); off += d.Length;
                    }
            var o = new List<byte>(off);
            o.AddRange(header);
            foreach (var c in Colors) o.AddRange(Bytes.Le32(c));
            foreach (var ti in themes) { o.AddRange(ti.Entry); foreach (var c in ti.ColorGroups) o.AddRange(Bytes.Le32(c)); }
            o.AddRange(recs.Buf);
            foreach (var bl in blobs) o.AddRange(bl);
            Log.Info("Saved");
            return o.ToArray();
        }
    }

    sealed class BuildTheme
    {
        public readonly byte[] Entry = new byte[0xA0];
        public readonly List<BuildItem>[] Tables = Enumerable.Range(0, 10).Select(_ => new List<BuildItem>()).ToArray();
        public readonly List<uint> ColorGroups = new List<uint>();
        public BuildItem Preview;
    }
}
