using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using BandFace.Protocol;

namespace BandFace.Store
{
    // Магазин циферблатів — той самий сервер і формат каталогу (schema 3), що й у BandFace для iOS.
    // Каталог кешується на 5 хв сервером; превʼю й файли — за відбитком вмісту, тож на диску лежать назавжди.

    /// <summary>Категорія: ключ і назви за мовами</summary>
    sealed class StoreCategory
    {
        public string Key;
        public Dictionary<string, string> Name = new Dictionary<string, string>();
    }

    sealed class StorePreview { public string Main, Aod; }

    /// <summary>Стиль варіанта: назва з файла, превʼю для кожного кольору, анімація основного кольору</summary>
    sealed class StoreStyle
    {
        public string Name = "";
        public List<StorePreview> Previews = new List<StorePreview>();
        public string Anim;
    }

    /// <summary>Варіант запису (мова, формат часу, пристрій): окремий файл з власним ID на браслеті</summary>
    sealed class StoreVariant
    {
        public string Key, FaceId, Sha256, Download, Clock;
        public int Size;
        public List<string> Langs = new List<string>();
        public List<int> Bands;      // null — усі пристрої запису
        public List<string> Colors = new List<string>();
        public List<StoreStyle> Styles = new List<StoreStyle>();
    }

    /// <summary>Запис магазину з усіма варіантами</summary>
    sealed class StoreEntry
    {
        public string Id, Version = "1.0", Updated, Added, Price;
        public Dictionary<string, string> Name = new Dictionary<string, string>();
        public Dictionary<string, string> About = new Dictionary<string, string>();
        public Dictionary<string, string> WhatsNew = new Dictionary<string, string>();
        public List<string> Kinds = new List<string>();
        public List<int> Bands = new List<int> { 10 };
        public Dictionary<string, StoreVariant> Variants = new Dictionary<string, StoreVariant>();
    }

    sealed class StoreCatalog
    {
        public List<StoreCategory> Categories = new List<StoreCategory>();
        public List<StoreEntry> Faces = new List<StoreEntry>();
    }

    sealed class StoreException : Exception { public StoreException(string m) : base(m) { } }

    static class StoreClient
    {
        public const string BaseUrl = "https://bandface-store.bfapp.workers.dev/";

        static readonly HttpClient Http;

        static StoreClient()
        {
            // .NET Framework 4.8 без цього не вміє TLS 1.2, а Cloudflare інших не приймає
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            Http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
            Http.DefaultRequestHeaders.UserAgent.ParseAdd("BandFace-Windows");
        }

        static string Dir
        {
            get
            {
                var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BandFace", "Store");
                Directory.CreateDirectory(d);
                return d;
            }
        }

        static string CatalogFile => Path.Combine(Dir, "catalog-v3.json");
        static string Local(string path) => Path.Combine(Dir, path.Replace('/', '_'));

        // MARK: Каталог

        /// <summary>Останній завантажений каталог — щоб магазин відкривався без мережі</summary>
        public static StoreCatalog Cached()
        {
            try { return File.Exists(CatalogFile) ? Parse(File.ReadAllText(CatalogFile, Encoding.UTF8)) : null; }
            catch (Exception) { return null; }
        }

        public static async Task<StoreCatalog> FetchAsync()
        {
            var text = await Http.GetStringAsync(BaseUrl + "catalog.json").ConfigureAwait(false);
            var catalog = Parse(text);
            try { File.WriteAllText(CatalogFile, text, Encoding.UTF8); } catch (Exception) { }
            Prune(catalog);
            return catalog;
        }

        public static StoreCatalog Parse(string json)
        {
            var root = MiniJson.Parse(json) as Dictionary<string, object> ?? throw new FormatException("catalog");
            if (Str(root, "schema") != "3") throw new FormatException("catalog schema");
            var c = new StoreCatalog();
            foreach (var o in List(root, "categories"))
                if (o is Dictionary<string, object> d) c.Categories.Add(new StoreCategory { Key = Str(d, "key"), Name = Dict(d, "name") });
            foreach (var o in List(root, "faces"))
            {
                if (!(o is Dictionary<string, object> d)) continue;
                var e = new StoreEntry
                {
                    Id = Str(d, "id"), Version = Str(d, "version") ?? "1.0", Updated = Str(d, "updated"), Added = Str(d, "added"),
                    Price = Str(d, "price"), Name = Dict(d, "name"), About = Dict(d, "about"), WhatsNew = Dict(d, "whatsNew"),
                    Kinds = List(d, "kinds").OfType<string>().ToList(),
                    Bands = Ints(List(d, "bands")) ?? new List<int> { 10 },
                };
                if (d.TryGetValue("variants", out var vs) && vs is Dictionary<string, object> variants)
                    foreach (var kv in variants)
                    {
                        if (!(kv.Value is Dictionary<string, object> v)) continue;
                        var variant = new StoreVariant
                        {
                            Key = kv.Key, FaceId = Str(v, "faceId"), Sha256 = Str(v, "sha256"), Download = Str(v, "download"), Clock = Str(v, "clock"),
                            Size = int.TryParse(Str(v, "size"), out var n) ? n : 0,
                            Langs = List(v, "langs").OfType<string>().ToList(),
                            Bands = v.TryGetValue("bands", out var b) && b is List<object> bl ? Ints(bl) : null,
                            Colors = List(v, "colors").OfType<string>().ToList(),
                        };
                        foreach (var so in List(v, "styles"))
                        {
                            if (!(so is Dictionary<string, object> s)) continue;
                            var style = new StoreStyle { Name = Str(s, "name") ?? "", Anim = Str(s, "anim") };
                            foreach (var po in List(s, "previews"))
                                if (po is Dictionary<string, object> p) style.Previews.Add(new StorePreview { Main = Str(p, "main"), Aod = Str(p, "aod") });
                            variant.Styles.Add(style);
                        }
                        if (variant.FaceId != null && variant.Download != null) e.Variants[kv.Key] = variant;
                    }
                if (e.Id != null && e.Variants.Count > 0) c.Faces.Add(e);
            }
            return c;
        }

        static string Str(Dictionary<string, object> d, string k) => d.TryGetValue(k, out var v) ? v as string : null;
        static List<object> List(Dictionary<string, object> d, string k) => d.TryGetValue(k, out var v) && v is List<object> l ? l : new List<object>();
        static Dictionary<string, string> Dict(Dictionary<string, object> d, string k)
        {
            var r = new Dictionary<string, string>();
            if (d.TryGetValue(k, out var v) && v is Dictionary<string, object> m)
                foreach (var kv in m) if (kv.Value is string s) r[kv.Key] = s;
            return r;
        }
        static List<int> Ints(List<object> l)
        {
            var r = l.OfType<string>().Select(s => int.TryParse(s, out var n) ? n : 0).Where(n => n > 0).ToList();
            return r.Count > 0 ? r : null;
        }

        // MARK: Файли превʼю

        /// <summary>Превʼю за шляхом з каталогу («b/&lt;відбиток&gt;.png»): з диска або сервера. Вміст за шляхом ніколи не змінюється.</summary>
        public static async Task<byte[]> FileAsync(string path)
        {
            if (string.IsNullOrEmpty(path)) return null;
            var local = Local(path);
            try { if (File.Exists(local)) return File.ReadAllBytes(local); } catch (Exception) { }
            try
            {
                var data = await Http.GetByteArrayAsync(BaseUrl + path).ConfigureAwait(false);
                try { File.WriteAllBytes(local, data); } catch (Exception) { }
                return data;
            }
            catch (Exception) { return null; }
        }

        /// <summary>Видаляє з диска превʼю, яких уже немає в каталозі</summary>
        static void Prune(StoreCatalog c)
        {
            var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Path.GetFileName(CatalogFile), Path.GetFileName(StatsFile) };
            foreach (var e in c.Faces)
                foreach (var v in e.Variants.Values)
                    foreach (var s in v.Styles)
                    {
                        if (s.Anim != null) keep.Add(Path.GetFileName(Local(s.Anim)));
                        foreach (var p in s.Previews)
                        {
                            if (p.Main != null) keep.Add(Path.GetFileName(Local(p.Main)));
                            if (p.Aod != null) keep.Add(Path.GetFileName(Local(p.Aod)));
                        }
                    }
            try
            {
                foreach (var f in Directory.GetFiles(Dir))
                    if (!keep.Contains(Path.GetFileName(f))) File.Delete(f);
            }
            catch (Exception) { }
        }

        // MARK: Завантаження файла

        /// <summary>Файл варіанта: перевіряються розмір, sha256 і ID на браслеті. Платні — лише через App Store (iOS).</summary>
        public static async Task<FaceFile> DownloadAsync(StoreVariant v)
        {
            HttpResponseMessage r;
            try { r = await Http.GetAsync(BaseUrl + v.Download).ConfigureAwait(false); }
            catch (Exception) { throw new StoreException(S.Get("storeNoNetwork")); }
            using (r)
            {
                if (r.StatusCode == (HttpStatusCode)402) throw new StoreException(S.Get("storePaidOnly"));
                if (!r.IsSuccessStatusCode) throw new StoreException(S.Get("storeDownloadFail", (int)r.StatusCode));
                var data = await r.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                string hash;
                using (var sha = SHA256.Create()) hash = string.Concat(sha.ComputeHash(data).Select(b => b.ToString("x2")));
                if (data.Length != v.Size || hash != v.Sha256) throw new StoreException(S.Get("storeBroken"));
                var face = new FaceFile(data);
                if (face.Id != v.FaceId) throw new StoreException(S.Get("storeBroken"));
                return face;
            }
        }

        // MARK: Перегляди й завантаження

        /// <summary>Відкрили сторінку циферблата: +1 перегляд на сервері (помилки не важливі)</summary>
        public static async Task SendViewAsync(string id)
        {
            try { using (await Http.PostAsync(BaseUrl + "view/" + Uri.EscapeDataString(id), new StringContent("")).ConfigureAwait(false)) { } }
            catch (Exception) { }
        }

        /// <summary>Останні отримані числа — на диску, щоб без мережі показувати хоч застарілі</summary>
        static string StatsFile => Path.Combine(Dir, "stats.json");

        /// <summary>Числа з диска (порожньо, якщо ще жодного разу не отримали)</summary>
        public static Dictionary<string, Tuple<int, int>> CachedStats()
        {
            try { return File.Exists(StatsFile) ? ParseStats(File.ReadAllText(StatsFile, Encoding.UTF8)) ?? new Dictionary<string, Tuple<int, int>>() : new Dictionary<string, Tuple<int, int>>(); }
            catch (Exception) { return new Dictionary<string, Tuple<int, int>>(); }
        }

        /// <summary>Свіжі перегляди й завантаження всіх записів (Item1 — перегляди, Item2 — завантаження) і на диск;
        /// сервер не відповів — останні збережені</summary>
        public static async Task<Dictionary<string, Tuple<int, int>>> StatsAsync()
        {
            try
            {
                var text = await Http.GetStringAsync(BaseUrl + "stats.json").ConfigureAwait(false);
                var r = ParseStats(text);
                if (r == null) return CachedStats();
                try { File.WriteAllText(StatsFile, text, Encoding.UTF8); } catch (Exception) { }
                return r;
            }
            catch (Exception) { return CachedStats(); }
        }

        static Dictionary<string, Tuple<int, int>> ParseStats(string text)
        {
            var root = MiniJson.Parse(text) as Dictionary<string, object>;
            if (root == null || !(root.TryGetValue("stats", out var o) && o is Dictionary<string, object> all)) return null;
            var r = new Dictionary<string, Tuple<int, int>>();
            foreach (var kv in all)
                if (kv.Value is Dictionary<string, object> d)
                    r[kv.Key] = Tuple.Create(ToInt(d, "views"), ToInt(d, "downloads"));
            return r;
        }

        static int ToInt(Dictionary<string, object> d, string k) =>
            d.TryGetValue(k, out var v) && v != null && double.TryParse(Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var x) ? (int)x : 0;

        // MARK: Встановлені з магазину

        /// <summary>ID на браслеті → версія, встановлена з магазину (для «Оновити»)</summary>
        public static Dictionary<string, string> Installed()
        {
            var r = new Dictionary<string, string>();
            foreach (var part in Storage.LoadText("store-installed").Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var kv = part.Split('=');
                if (kv.Length == 2) r[kv[0]] = kv[1];
            }
            return r;
        }

        public static void SetInstalled(string faceId, string version)
        {
            var map = Installed();
            if (version == null) map.Remove(faceId); else map[faceId] = version;
            Storage.SaveText("store-installed", string.Join(";", map.Select(kv => kv.Key + "=" + kv.Value)));
        }
    }

    /// <summary>Версії «1.0», «1.10»: порівняння за числами (1.10 &gt; 1.9)</summary>
    static class StoreVersions
    {
        public static bool Older(string a, string b)
        {
            var x = (a ?? "").Split('.').Select(s => int.TryParse(s, out var n) ? n : 0).ToArray();
            var y = (b ?? "").Split('.').Select(s => int.TryParse(s, out var n) ? n : 0).ToArray();
            for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
            {
                int d = (i < x.Length ? x[i] : 0) - (i < y.Length ? y[i] : 0);
                if (d != 0) return d < 0;
            }
            return false;
        }
    }

    /// <summary>Вибір варіанта, як в iOS: пристрій → мова Windows → «для всіх інших»; серед них — збіг формату часу</summary>
    static class StoreVariants
    {
        /// <summary>Мови користувача: мова інтерфейсу Windows, далі мова регіону</summary>
        public static List<string> Languages
        {
            get
            {
                var r = new List<string>();
                foreach (var c in new[] { CultureInfo.CurrentUICulture, CultureInfo.CurrentCulture })
                {
                    var code = c.TwoLetterISOLanguageName.ToLowerInvariant();
                    if (code.Length == 2 && !r.Contains(code)) r.Add(code);
                }
                return r;
            }
        }

        /// <summary>12- чи 24-годинний час у регіональних параметрах Windows</summary>
        public static string Clock => CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern.Contains("h") ? "12h" : "24h";

        public static Dictionary<string, StoreVariant> ForBand(StoreEntry e, int band)
        {
            var fit = e.Variants.Where(kv => kv.Value.Bands == null || kv.Value.Bands.Contains(band)).ToDictionary(kv => kv.Key, kv => kv.Value);
            return fit.Count > 0 ? fit : e.Variants;
        }

        public static string Choose(StoreEntry e, int band)
        {
            var variants = ForBand(e, band);
            var clock = Clock;
            Func<List<string>, string> best = keys =>
                keys.FirstOrDefault(k => variants[k].Clock == clock) ?? keys.FirstOrDefault(k => variants[k].Clock == null) ?? keys.FirstOrDefault();
            var all = variants.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList();
            foreach (var lang in Languages)
            {
                var match = all.Where(k => variants[k].Langs.Contains(lang)).ToList();
                if (match.Count > 0) return best(match);
            }
            return best(all.Where(k => variants[k].Langs.Contains("*")).ToList()) ?? best(all);
        }

        /// <summary>«Англійська · 12 год» — назва мовою інтерфейсу</summary>
        public static string Label(StoreVariant v)
        {
            var code = v.Key.Length >= 2 ? v.Key.Substring(0, 2) : v.Key;
            // англійська з AM/PM — це англійська для США
            if (code == "en" && v.Clock == "12h")
            {
                return LanguageName("en") + " (" + S.Get("usShort") + ")";   // «Англійська (США)», а не «(Сполучені Штати)»
            }
            var title = LanguageName(code);
            return v.Clock == "12h" ? title + " · " + S.Get("clock12short") : v.Clock == "24h" ? title + " · " + S.Get("clock24short") : title;
        }

        public static string LanguageName(string code)
        {
            try
            {
                var n = new CultureInfo(code).NativeName;
                int p = n.IndexOf(" (", StringComparison.Ordinal);
                if (p > 0) n = n.Substring(0, p);
                return n.Length > 0 ? char.ToUpper(n[0]) + n.Substring(1) : code;
            }
            catch (Exception) { return code; }
        }

        /// <summary>Текст мовою користувача, інакше першою мовою варіанта, інакше англійською чи українською</summary>
        public static string Text(Dictionary<string, string> dict, StoreVariant v)
        {
            if (dict == null) return "";
            var order = Languages.Concat(v?.Langs.Where(l => l != "*") ?? Enumerable.Empty<string>()).Concat(new[] { "en", "uk" }).ToList();
            // англійська з AM/PM (США) — свій опис «en-US», якщо автор його написав; стоїть перед звичайною англійською
            int en = order.IndexOf("en");
            if (v != null && v.Clock == "12h" && v.Langs.Contains("en") && en >= 0) order.Insert(en, "en-US");
            foreach (var l in order) if (dict.TryGetValue(l, out var s) && !string.IsNullOrEmpty(s)) return s;
            return dict.Values.FirstOrDefault(s => !string.IsNullOrEmpty(s)) ?? "";
        }

        /// <summary>Стиль і колір: превʼю (основне й AOD) — якщо такого кольору немає, перший</summary>
        public static StorePreview Look(StoreVariant v, int style, int color)
        {
            if (v == null || style < 0 || style >= v.Styles.Count) return null;
            var p = v.Styles[style].Previews;
            return color >= 0 && color < p.Count ? p[color] : p.FirstOrDefault();
        }
    }
}
