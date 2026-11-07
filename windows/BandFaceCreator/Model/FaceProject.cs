// SPDX-License-Identifier: MIT
// Проєкт циферблата: manifest.xml (дерево XNode без втрат) + файли ресурсів + налаштування редактора.
// Будь-який розпакований .bin стає проєктом і після редагування збирається назад тим самим компілятором.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Media.Imaging;
using BandFace.Faces;

namespace BandFace.Creator
{
    public sealed class FaceProject
    {
        public readonly string Id;
        public readonly string Folder;
        public XNode Root { get; private set; }
        /// <summary>Усі файли проєкту, крім manifest.xml і editor.json (шлях → вміст)</summary>
        public Dictionary<string, byte[]> Files { get; private set; }
        public ProjectMeta Meta;
        /// <summary>Лічильник змін — для перемальовування й ключів превʼю</summary>
        public int Revision { get; private set; }
        public event Action Changed;

        sealed class Snapshot { public byte[] Xml; public Dictionary<string, byte[]> Files; public ProjectMeta Meta; }
        readonly List<Snapshot> undo = new List<Snapshot>(), redo = new List<Snapshot>();
        public bool CanUndo => undo.Count > 0;
        public bool CanRedo => redo.Count > 0;

        /// <summary>Розпаковані картинки проєкту, спільні для всіх рендерів</summary>
        public readonly ImageCache Images = new ImageCache();
        readonly HashSet<string> dirty = new HashSet<string>(), removed = new HashSet<string>();
        bool fullSave = true;

        public FaceProject(string id, string folder, XNode root, Dictionary<string, byte[]> files, ProjectMeta meta)
        {
            Id = id; Folder = folder; Root = root; Files = files; Meta = meta;
        }

        // MARK: Доступ до маніфесту

        public XNode Resources
        {
            get
            {
                var r = Root.First("Resources");
                if (r != null) return r;
                r = new XNode("Resources");
                Root.Kids.Insert(0, r);
                return r;
            }
        }
        public List<XNode> Themes => Root.All("Theme");
        public XNode Theme(int i) { var t = Themes; return i >= 0 && i < t.Count ? t[i] : null; }
        public List<XNode> Layouts(int theme) => Theme(theme)?.All("Layout") ?? new List<XNode>();

        public string Name => Root.Str("name") ?? "";
        public string DisplayName => Name.Length == 0 ? S.Get("untitled") : Name;

        public XNode Resource(string name) => name == null ? null : Resources.Elements.FirstOrDefault(e => e.Str("name") == name);
        /// <summary>Ресурс за посиланням «@ім'я»</summary>
        public XNode ResourceRef(string r) => r == null || r.Length < 2 ? null : Resource(r.Substring(1));

        /// <summary>Елемент шару: для обгортки «дія при натисканні» — те, що всередині</summary>
        public XNode ElementOf(XNode layout)
        {
            var r = ResourceRef(layout.Str("ref"));
            if (r == null) return null;
            return ElementFactory.TapInner(this, r) ?? r;
        }

        public string UniqueName(string b)
        {
            var used = new HashSet<string>(Resources.Elements.Select(e => e.Str("name")).Where(n => n != null));
            if (!used.Contains(b)) return b;
            int i = 2;
            while (used.Contains(b + i)) i++;
            return b + i;
        }

        public byte[] File(string path) => path != null && Files.TryGetValue(MemoryStorage.Normalize(path), out var d) ? d : null;

        // MARK: Зміни (з відкатом)

        Snapshot Snap() => new Snapshot { Xml = Xml.Print(Root), Files = new Dictionary<string, byte[]>(Files), Meta = Meta.Copy() };

        /// <summary>Будь-яка зміна проходить тут: знімок для «Скасувати», зміна, збереження.</summary>
        public void Edit(Action<FaceProject> change)
        {
            undo.Add(Snap());
            if (undo.Count > 60) undo.RemoveAt(0);
            redo.Clear();
            change(this);
            Meta.Modified = DateTime.UtcNow;
            Meta.Edited = true;
            Revision++;
            Save();
            Changed?.Invoke();
        }

        public void Undo()
        {
            if (undo.Count == 0) return;
            var s = undo[undo.Count - 1];
            undo.RemoveAt(undo.Count - 1);
            redo.Add(Snap());
            Restore(s);
        }

        public void Redo()
        {
            if (redo.Count == 0) return;
            var s = redo[redo.Count - 1];
            redo.RemoveAt(redo.Count - 1);
            undo.Add(Snap());
            Restore(s);
        }

        void Restore(Snapshot s)
        {
            var r = Xml.Parse(s.Xml);
            if (r == null) return;
            Root = r; Files = s.Files; Meta = s.Meta;
            Images.Clear();
            fullSave = true;
            Revision++;
            Save();
            Changed?.Invoke();
        }

        /// <summary>Файли вже на диску (щойно прочитаний проєкт)</summary>
        public void MarkSaved() { fullSave = false; dirty.Clear(); removed.Clear(); }

        public void SetFile(string path, byte[] data)
        {
            var k = MemoryStorage.Normalize(path);
            Files[k] = data; Images.Remove(k); dirty.Add(k); removed.Remove(k);
        }

        public void RemoveFile(string path)
        {
            var k = MemoryStorage.Normalize(path);
            Files.Remove(k); Images.Remove(k); dirty.Remove(k); removed.Add(k);
        }

        // MARK: Збереження

        static string Disk(string root, string rel) => Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar));

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Folder);
                var xml = new List<byte>();
                foreach (var c in Xml.Print(Root)) { if (c == 0x0A) xml.Add(0x0D); xml.Add(c); }
                System.IO.File.WriteAllBytes(Path.Combine(Folder, "manifest.xml"), xml.ToArray());
                System.IO.File.WriteAllText(Path.Combine(Folder, "editor.json"), Meta.ToJson(), new UTF8Encoding(false));
                var filesDir = Path.Combine(Folder, "files");
                // лише змінені файли; повністю — після відкату й при першому збереженні
                if (fullSave && Directory.Exists(filesDir)) Directory.Delete(filesDir, true);
                foreach (var p in removed) { var f = Disk(filesDir, p); if (System.IO.File.Exists(f)) System.IO.File.Delete(f); }
                foreach (var kv in Files)
                {
                    if (!fullSave && !dirty.Contains(kv.Key)) continue;
                    var f = Disk(filesDir, kv.Key);
                    Directory.CreateDirectory(Path.GetDirectoryName(f));
                    System.IO.File.WriteAllBytes(f, kv.Value);
                }
                fullSave = false; dirty.Clear(); removed.Clear();
            }
            catch (Exception) { }
        }

        public static FaceProject Load(string folder)
        {
            try
            {
                var mf = Path.Combine(folder, "manifest.xml");
                if (!System.IO.File.Exists(mf)) return null;
                var root = Xml.Parse(System.IO.File.ReadAllBytes(mf));
                if (root == null) return null;
                var jf = Path.Combine(folder, "editor.json");
                var meta = System.IO.File.Exists(jf) ? ProjectMeta.FromJson(System.IO.File.ReadAllText(jf)) : new ProjectMeta();
                var files = new Dictionary<string, byte[]>();
                var filesDir = Path.Combine(folder, "files");
                if (Directory.Exists(filesDir))
                    foreach (var f in Directory.GetFiles(filesDir, "*", SearchOption.AllDirectories))
                    {
                        var rel = f.Substring(filesDir.Length).TrimStart(Path.DirectorySeparatorChar, '/');
                        files[MemoryStorage.Normalize(rel)] = System.IO.File.ReadAllBytes(f);
                    }
                var p = new FaceProject(Path.GetFileName(folder), folder, root, files, meta);
                p.MarkSaved();
                return p;
            }
            catch (Exception) { return null; }
        }

        /// <summary>Розпаковує .bin у дерево маніфесту й файли (без запису на диск).</summary>
        public static Tuple<XNode, Dictionary<string, byte[]>> Unpack(byte[] data)
        {
            var mem = new MemoryStorage();
            WatchfaceCompiler.Unpack(data, mem);
            if (!mem.Files.TryGetValue("manifest.xml", out var xml)) throw new FaceCompilerException("manifest.xml");
            mem.Files.Remove("manifest.xml");
            var root = Xml.Parse(xml) ?? throw new FaceCompilerException("manifest.xml");
            return Tuple.Create(root, mem.Files);
        }

        // MARK: Збирання

        public MemoryStorage Storage()
        {
            var all = new Dictionary<string, byte[]>(Files) { ["manifest.xml"] = Xml.Print(Root) };
            return new MemoryStorage(all);
        }

        /// <summary>Збирає .bin. Повертає дані й попередження компілятора. Після змін превʼю для браслета малюється заново.</summary>
        public Tuple<byte[], List<string>> Compile()
        {
            var log = new FaceCompilerLog();
            ColorVariants.SyncThemes(this);
            bool needsPreview = Meta.Edited || Themes.Any(t => !t.Has("preview"));
            // кольорові варіанти — з копіями незмінних картинок, як у exe: без них браслет перезавантажується
            var st = needsPreview ? StorageWithFreshPreviews() : Storage();
            if (ColorVariants.IsEnabled(this)) AddBackgroundFill(st);
            // Band 10/11 знає лише indexed8: картинки інших форматів (фото, циферблати від інших браслетів) — у 256 кольорів (Б-1)
            Band10.FixImages(st);
            var data = WatchfaceCompiler.Build(st, null, log);
            return Tuple.Create(data, log.Warnings.ToList());
        }

        /// <summary>Циферблат із вибором кольору: браслет злегка підфарбовує фон теми вибраним кольором, тож найнижчим
        /// шаром кладемо непрозору картинку кольору фону (якщо такого шару ще немає). Проєкт не змінюється.</summary>
        void AddBackgroundFill(MemoryStorage st)
        {
            var root = Xml.Parse(st.Files["manifest.xml"]);
            if (root == null) return;
            var res = root.First("Resources");
            if (res == null) { res = new XNode("Resources"); root.Kids.Insert(0, res); }
            var used = new HashSet<string>(res.Elements.Select(e => e.Str("name")).Where(n => n != null));
            var themes = root.All("Theme");
            for (int t = 0; t < themes.Count; t++)
            {
                var theme = themes[t];
                var first = theme.All("Layout").FirstOrDefault();
                if (first != null && CoversScreen(first, res, st)) continue;
                var fill = AssetFactory.Fill(Meta.Device.Width, Meta.Device.Height, theme.Str("bgColor") ?? "#000000");
                var name = "bgfill_" + t;
                int i = 2;
                while (used.Contains(name)) name = "bgfill_" + t + "_" + i++;
                used.Add(name);
                st.Files[name + ".png"] = fill.Png();
                var e = new XNode("Image");
                e.Set("name", name).Set("src", name + ".png").Set("compressMethod", "RLEReversed").Set("format", fill.BestFormat()).Set("recolorEnable", false);
                res.Kids.Add(e);
                var l = new XNode("Layout");
                l.Set("ref", "@" + name).Set("x", 0).Set("y", 0);
                int idx = theme.Kids.FindIndex(k => k.Tag == "Layout");
                theme.Kids.Insert(idx < 0 ? theme.Kids.Count : idx, l);
            }
            st.Files["manifest.xml"] = Xml.Print(root);
        }

        /// <summary>Шар — непрозора картинка на весь екран у точці 0,0</summary>
        bool CoversScreen(XNode layout, XNode res, MemoryStorage st)
        {
            var r = layout.Str("ref");
            if (layout.Int("x") != 0 || layout.Int("y") != 0 || r == null || r.Length < 2) return false;
            var name = r.Substring(1);
            var img = res.Elements.FirstOrDefault(e => e.Tag == "Image" && e.Str("name") == name);
            var src = img?.Str("src");
            var d = src == null ? null : st.Read(src);
            var png = d == null ? null : Faces.Png.Decode(d);
            if (png == null || png.W < Meta.Device.Width || png.H < Meta.Device.Height) return false;
            for (int i = 3; i < png.Px.Length; i += 4) if (png.Px[i] < 255) return false;
            return true;
        }

        /// <summary>Розмір превʼю, яке браслет показує у списку циферблатів (як в офіційних циферблатах)</summary>
        public const int PreviewW = 134, PreviewH = 328;

        /// <summary>Сховище для збирання, де в кожної теми нове превʼю — зменшений кадр цієї теми. Проєкт не змінюється.</summary>
        public MemoryStorage StorageWithFreshPreviews()
        {
            var root = Root.Copy();
            var all = new Dictionary<string, byte[]>(Files);
            var res = root.First("Resources");
            if (res == null) { res = new XNode("Resources"); root.Kids.Insert(0, res); }
            var used = new HashSet<string>(res.Elements.Select(e => e.Str("name")).Where(n => n != null));
            var renderer = new FaceRenderer(this);
            var themes = root.All("Theme");
            int inserted = 0;
            for (int t = 0; t < themes.Count; t++)
            {
                var theme = themes[t];
                var oldRef = theme.Str("preview");
                var old = oldRef != null && oldRef.Length > 1 ? oldRef.Substring(1) : null;
                var frame = renderer.Render(t, 1).Image;
                var small = Imaging.Render(PreviewW, PreviewH, dc => dc.DrawImage(frame, new System.Windows.Rect(0, 0, PreviewW, PreviewH))).Quantized();
                var name = "preview_" + t;
                int i = 2;
                while (used.Contains(name)) name = "preview_" + t + "_" + i++;
                used.Add(name);
                all[name + ".png"] = small.Png();
                var e = new XNode("Image");
                e.Set("name", name).Set("src", name + ".png").Set("compressMethod", "RLEReversed").Set("format", small.BestFormat()).Set("recolorEnable", false);
                res.Kids.Insert(inserted, e);
                inserted++;
                theme.Set("preview", "@" + name);
                // старе превʼю більше не потрібне, якщо на нього не посилається ні шар, ні інша тема
                if (old != null && References(old, root) == 0)
                {
                    int idx = res.Kids.FindIndex(k => !k.IsComment && k.Str("name") == old);
                    if (idx >= 0)
                    {
                        var src = res.Kids[idx].Str("src");
                        if (src != null) all.Remove(MemoryStorage.Normalize(src));
                        foreach (var img in res.Kids[idx].All("Image")) { var s = img.Str("src"); if (s != null) all.Remove(MemoryStorage.Normalize(s)); }
                        res.Kids.RemoveAt(idx);
                        if (idx < inserted) inserted--;
                    }
                }
            }
            all["manifest.xml"] = Xml.Print(root);
            return new MemoryStorage(all);
        }

        /// <summary>Скільки разів у маніфесті є «@name»</summary>
        static int References(string name, XNode node)
        {
            var r = Bytes.Utf8("@" + name);
            int n = node.Attrs.Count(a => Bytes.Same(a.Value, r));
            foreach (var k in node.Kids) if (!k.IsComment) n += References(name, k);
            return n;
        }
    }

    /// <summary>Розпаковані картинки проєкту (потокобезпечно: мініатюри малюються у фоні)</summary>
    public sealed class ImageCache
    {
        readonly Dictionary<string, BitmapSource> map = new Dictionary<string, BitmapSource>();
        readonly object gate = new object();

        public BitmapSource Get(string key, Func<BitmapSource> make)
        {
            lock (gate) { if (map.TryGetValue(key, out var c)) return c; }
            var img = make();
            if (img == null) return null;
            lock (gate) map[key] = img;
            return img;
        }
        public void Remove(string key) { lock (gate) map.Remove(key); }
        public void Clear() { lock (gate) map.Clear(); }
    }
}
