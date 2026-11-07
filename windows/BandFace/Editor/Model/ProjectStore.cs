// SPDX-License-Identifier: MIT
// Список проєктів у %LOCALAPPDATA%\BandFace\Creator\Projects: створення, відкриття .bin, копія, видалення.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using BandFace.Faces;

namespace BandFace.Creator
{
    sealed class ProjectStore
    {
        public readonly List<FaceProject> Projects = new List<FaceProject>();
        static readonly Random Rnd = new Random();

        public static string Base
        {
            get
            {
                var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BandFace", "Creator", "Projects");
                Directory.CreateDirectory(d);
                return d;
            }
        }

        public ProjectStore() { Reload(); }

        public void Reload()
        {
            Projects.Clear();
            foreach (var d in Directory.GetDirectories(Base))
            {
                var p = FaceProject.Load(d);
                if (p != null) Projects.Add(p);
            }
            Projects.Sort((a, b) => b.Meta.Modified.CompareTo(a.Meta.Modified));
        }

        static string NewFolder() => Path.Combine(Base, Guid.NewGuid().ToString().ToUpperInvariant());

        /// <summary>Новий ID циферблата (9 цифр): копія не замінює оригінал на браслеті.</summary>
        public static string NewFaceId() { lock (Rnd) return Rnd.Next(100000000, 1000000000).ToString(); }

        /// <summary>Порожній циферблат: години, хвилини, дата.</summary>
        public FaceProject Create(string name, DeviceProfile device)
        {
            var root = new XNode("Watchface");
            root.Set("id", NewFaceId()).Set("name", name);
            root.Add("Resources");
            root.Add("Theme").Set("type", "normal").Set("name", "").Set("bgColor", "#000000");
            var meta = new ProjectMeta { Device = device };
            var folder = NewFolder();
            var p = new FaceProject(Path.GetFileName(folder), folder, root, new Dictionary<string, byte[]>(), meta);
            int w = device.Width;
            var digits = new Generator(GenKind.Digits) { Color = "#FFFFFF", FontSize = 66, Weight = 800, Style = "rounded" };
            ElementFactory.AddDigits(p, "timeHour", digits, 0, w / 2, 120);
            ElementFactory.AddDigits(p, "timeMinute", digits.Copy(), 0, w / 2, 200);
            // дата — картинками цифр: текст (DataItemText) на браслеті не перевірено (Б-1)
            ElementFactory.AddDigits(p, "dateDay", new Generator(GenKind.Digits) { Color = "#4DE1FF", FontSize = 34, Weight = 700, Style = "rounded" }, 0, w / 2, 280);
            p.Save();
            Projects.Insert(0, p);
            return p;
        }

        /// <summary>Відкрити готовий .bin (розпакування тим самим компілятором).</summary>
        public FaceProject ImportBin(byte[] data, string name, bool asCopy = false)
        {
            var u = FaceProject.Unpack(data);
            var root = u.Item1;
            var folder = NewFolder();
            var p = new FaceProject(Path.GetFileName(folder), folder, root, u.Item2, new ProjectMeta());
            if ((root.Str("name") ?? "").Length == 0) root.Set("name", name);
            if (asCopy) root.Set("id", NewFaceId()).Set("name", (root.Str("name") ?? name) + S.Get("copySuffix"));
            p.Save();
            Projects.Insert(0, p);
            return p;
        }

        /// <summary>Відкрити теку проєкту (manifest.xml + картинки), наприклад, розпаковану WatchfaceCompiler</summary>
        public FaceProject ImportFolder(string dir)
        {
            var mf = Path.Combine(dir, "manifest.xml");
            var root = Xml.Parse(File.ReadAllBytes(mf)) ?? throw new FaceCompilerException("manifest.xml");
            var files = new Dictionary<string, byte[]>();
            foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
            {
                var rel = f.Substring(dir.Length).TrimStart(Path.DirectorySeparatorChar, '/');
                if (string.Equals(rel, "manifest.xml", StringComparison.OrdinalIgnoreCase)) continue;
                files[MemoryStorage.Normalize(rel)] = File.ReadAllBytes(f);
            }
            var folder = NewFolder();
            var p = new FaceProject(Path.GetFileName(folder), folder, root, files, new ProjectMeta());
            p.Save();
            Projects.Insert(0, p);
            return p;
        }

        public FaceProject Duplicate(FaceProject p)
        {
            var folder = NewFolder();
            CopyDir(p.Folder, folder);
            var c = FaceProject.Load(folder);
            if (c == null) return null;
            // власний ID: інакше копія на браслеті замінила б оригінал
            c.Edit(x => x.Root.Set("name", (x.Root.Str("name") ?? "") + S.Get("copySuffix")).Set("id", NewFaceId()));
            Projects.Insert(0, c);
            return c;
        }

        static void CopyDir(string src, string dst)
        {
            Directory.CreateDirectory(dst);
            foreach (var f in Directory.GetFiles(src)) File.Copy(f, Path.Combine(dst, Path.GetFileName(f)));
            foreach (var d in Directory.GetDirectories(src)) CopyDir(d, Path.Combine(dst, Path.GetFileName(d)));
        }

        public void Delete(FaceProject p)
        {
            try { Directory.Delete(p.Folder, true); } catch (Exception) { }
            Projects.Remove(p);
        }
    }
}
