// SPDX-License-Identifier: MIT
// Список проєктів: теки в %LOCALAPPDATA%\BandFace\Creator\Projects плюс теки, які користувач відкрив або переніс
// деінде (їхні шляхи — у %LOCALAPPDATA%\BandFace\Creator\projects.txt). Створення, відкриття .bin, копія, перенесення.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Media.Imaging;
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

        static string ListFile => Path.Combine(Path.GetDirectoryName(Base), "projects.txt");

        /// <summary>Теки проєктів поза стандартною (відкриті з диска або перенесені)</summary>
        static List<string> External()
        {
            try { return File.Exists(ListFile) ? File.ReadAllLines(ListFile).Where(l => l.Trim().Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList() : new List<string>(); }
            catch (Exception) { return new List<string>(); }
        }

        static void SaveExternal(List<string> l) { try { File.WriteAllLines(ListFile, l.Distinct(StringComparer.OrdinalIgnoreCase)); } catch (Exception) { } }

        static bool InBase(string folder) => string.Equals(Path.GetFullPath(Path.GetDirectoryName(folder.TrimEnd('\\', '/'))).TrimEnd('\\'), Path.GetFullPath(Base).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

        public static bool IsExternal(FaceProject p) => p.Folder != null && !InBase(p.Folder);

        static void Register(string folder)
        {
            if (InBase(folder)) return;
            var l = External();
            if (!l.Contains(folder, StringComparer.OrdinalIgnoreCase)) { l.Add(folder); SaveExternal(l); }
        }

        static void Unregister(string folder)
        {
            var l = External();
            l.RemoveAll(x => string.Equals(x, folder, StringComparison.OrdinalIgnoreCase));
            SaveExternal(l);
        }

        public void Reload()
        {
            Projects.Clear();
            foreach (var d in Directory.GetDirectories(Base).Concat(External().Where(Directory.Exists)))
            {
                var p = FaceProject.Load(d);
                if (p != null) Projects.Add(p);
            }
            Projects.Sort((a, b) => b.Meta.Modified.CompareTo(a.Meta.Modified));
        }

        /// <summary>Назва теки з назви циферблата (без недозволених символів), унікальна в parent</summary>
        public static string FolderFor(string parent, string name)
        {
            var bad = Path.GetInvalidFileNameChars();
            var b = new string((name ?? "").Select(c => bad.Contains(c) ? '_' : c).ToArray()).Trim().TrimEnd('.');
            if (b.Length == 0) b = "BandFace";
            if (b.Length > 60) b = b.Substring(0, 60).Trim();
            var f = Path.Combine(parent, b);
            for (int i = 2; Directory.Exists(f) || File.Exists(f); i++) f = Path.Combine(parent, b + " " + i);
            return f;
        }

        static string NewFolder(string name = null) => FolderFor(Base, name ?? S.Get("untitled"));

        /// <summary>Новий ID циферблата (9 цифр): копія не замінює оригінал на браслеті.</summary>
        public static string NewFaceId() { lock (Rnd) return Rnd.Next(100000000, 1000000000).ToString(); }

        /// <summary>Новий циферблат: великі години й хвилини (з BigWatch).</summary>
        public FaceProject Create(string name, DeviceProfile device)
        {
            var root = new XNode("Watchface");
            root.Set("id", NewFaceId()).Set("name", name);
            root.Add("Resources");
            root.Add("Theme").Set("type", "normal").Set("name", "").Set("bgColor", "#000000");
            var meta = new ProjectMeta { Device = device };
            var folder = NewFolder(name);
            var p = new FaceProject(Path.GetFileName(folder), folder, root, new Dictionary<string, byte[]>(), meta);
            // старт — великі години й хвилини з BigWatch на тих самих місцях
            var imgs = StarterDigits.Png.Select(b64 =>
            {
                var bmp = BitmapFrame.Create(new MemoryStream(Convert.FromBase64String(b64)), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                return Imaging.FromBitmap(bmp);
            }).ToList();
            int dw = imgs[0].W, dh = imgs[0].H;
            // AddDigitImages ставить число за центром: лівий край = cx − ширина цифри
            ElementFactory.AddDigitImages(p, "timeHour", imgs, 0, StarterDigits.X + dw, StarterDigits.HourY + dh / 2);
            ElementFactory.AddDigitImages(p, "timeMinute", imgs, 0, StarterDigits.X + dw, StarterDigits.MinuteY + dh / 2);
            p.Save();
            Projects.Insert(0, p);
            return p;
        }

        /// <summary>Відкрити готовий .bin (розпакування тим самим компілятором).</summary>
        public FaceProject ImportBin(byte[] data, string name, bool asCopy = false)
        {
            var u = FaceProject.Unpack(data);
            var root = u.Item1;
            var folder = NewFolder((root.Str("name") ?? "").Length > 0 ? root.Str("name") : name);
            var p = new FaceProject(Path.GetFileName(folder), folder, root, u.Item2, new ProjectMeta());
            if ((root.Str("name") ?? "").Length == 0) root.Set("name", name);
            if (asCopy) root.Set("id", NewFaceId()).Set("name", (root.Str("name") ?? name) + S.Get("copySuffix"));
            p.Save();
            Projects.Insert(0, p);
            return p;
        }

        /// <summary>Відкрити теку: наш проєкт — на місці (запам'ятовується у списку); просто розпакований циферблат
        /// (manifest.xml + картинки поруч) — копіюється в новий проєкт</summary>
        public FaceProject ImportFolder(string dir)
        {
            dir = Path.GetFullPath(dir).TrimEnd('\\');
            if (FaceProject.IsProjectFolder(dir))
            {
                var open = Projects.FirstOrDefault(x => string.Equals(x.Folder, dir, StringComparison.OrdinalIgnoreCase));
                if (open != null) return open;
                var lp = FaceProject.Load(dir) ?? throw new FaceCompilerException("manifest.xml");
                Register(dir);
                Projects.Insert(0, lp);
                return lp;
            }
            var mf = Path.Combine(dir, "manifest.xml");
            var root = Xml.Parse(File.ReadAllBytes(mf)) ?? throw new FaceCompilerException("manifest.xml");
            var files = new Dictionary<string, byte[]>();
            foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
            {
                var rel = f.Substring(dir.Length).TrimStart(Path.DirectorySeparatorChar, '/');
                if (string.Equals(rel, "manifest.xml", StringComparison.OrdinalIgnoreCase)) continue;
                files[MemoryStorage.Normalize(rel)] = File.ReadAllBytes(f);
            }
            var folder = NewFolder(root.Str("name") ?? Path.GetFileName(dir));
            var p = new FaceProject(Path.GetFileName(folder), folder, root, files, new ProjectMeta());
            p.Save();
            Projects.Insert(0, p);
            return p;
        }

        public FaceProject Duplicate(FaceProject p)
        {
            // копія — поруч з оригіналом
            var folder = FolderFor(Path.GetDirectoryName(p.Folder), p.DisplayName + S.Get("copySuffix"));
            FaceProject.CopyDir(p.Folder, folder);
            Register(folder);
            var c = FaceProject.Load(folder);
            if (c == null) return null;
            // власний ID: інакше копія на браслеті замінила б оригінал
            c.Edit(x => x.Root.Set("name", (x.Root.Str("name") ?? "") + S.Get("copySuffix")).Set("id", NewFaceId()));
            Projects.Insert(0, c);
            return c;
        }

        /// <summary>Перенести проєкт у вибрану теку (усередині створюється тека з назвою циферблата)</summary>
        public static void Move(FaceProject p, string parent)
        {
            var old = p.Folder;
            var target = FolderFor(parent, p.DisplayName);
            p.MoveTo(target);
            Unregister(old);
            Register(target);
        }

        /// <summary>Проєкт у стандартній теці видаляється; тека деінде лише прибирається зі списку (файли лишаються)</summary>
        public void Delete(FaceProject p)
        {
            if (IsExternal(p)) Unregister(p.Folder);
            else try { Directory.Delete(p.Folder, true); } catch (Exception) { }
            Projects.Remove(p);
        }
    }
}
