// SPDX-License-Identifier: MIT
// Налаштування редактора для проєкту (editor.json): пристрій, параметри згенерованих елементів, час зміни.
// Формат сумісний з BandFace для iOS, тож проєкти переносяться між телефоном і комп'ютером.

using System;
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Creator
{
    public enum GenKind { Digits, Arc, Line, Pointer, Image, Frames, Label, Texts }

    /// <summary>Параметри, з яких редактор створив ресурс (щоб перемалювати після зміни шрифту, кольору тощо).</summary>
    public sealed class Generator
    {
        public GenKind Kind;
        public string Color = "#FFFFFF";
        public string BgColor = "#3A3A3C";
        public double FontSize = 48;
        public int Weight = 700;
        /// <summary>Стиль системного шрифту, як в iOS: rounded | default | condensed | mono</summary>
        public string Style = "rounded";
        /// <summary>Будь-який шрифт Windows або доданий файл шрифту (назва сімейства); порожньо — за стилем</summary>
        public string Font = "";
        public double Radius = 60;
        public double Width = 10;
        public double Length = 120;
        /// <summary>Одиниця біля числа («%», «°», «км»), малюється тим самим шрифтом</summary>
        public string Unit = "";
        /// <summary>Рядок напису (Label): малюється шрифтом у картинку</summary>
        public string Text = "";
        /// <summary>Дуга: початок і довжина (градуси, 0° — угорі, за годинниковою); трек і заповнення малюються лише в цих межах</summary>
        public double Start = 40, Range = 280; // розріз угорі: 0° + 180° − 280°/2
        /// <summary>Лінія: напрямок у градусах (0° — праворуч, 90° — донизу)</summary>
        public double Angle = 0;
        /// <summary>Кінці дуги й лінії: круглі (типово) або прямі</summary>
        public bool Round = true;
        /// <summary>Набір цифр (П-2): обвідка, тінь, градієнт, ширина літер</summary>
        public double Outline = 0;
        public string OutlineColor = "#000000";
        public double ShadowX = 0, ShadowY = 0;
        public string ShadowColor = "#000000";
        /// <summary>Другий колір градієнта згори донизу; порожньо — суцільний колір</summary>
        public string Color2 = "";
        /// <summary>Ширина літер, % (100 — як у шрифті)</summary>
        public double WidthPct = 100;
        /// <summary>Kind == Texts: рядок для кожної картинки масиву (дні тижня, місяці, AM/PM…)</summary>
        public List<string> Texts = new List<string>();
        /// <summary>Фон під кожним знаком/написом: "" — без фону, circle — коло, capsule — капсула, square — заокруглений квадрат</summary>
        public string Badge = "";
        public string BadgeColor = "#FF9F0A";
        /// <summary>Прозорість заливки тексту, %</summary>
        public double FillAlpha = 100;
        /// <summary>Обведення: положення (0 — зовні, 1 — посередині, 2 — всередині) і прозорість, %</summary>
        public int OutlinePos = 0;
        public double OutlineAlpha = 100;
        /// <summary>Прозорість тіні, %</summary>
        public double ShadowAlpha = 60;
        /// <summary>Напрямок градієнта: 0 — згори донизу, 1 — по діагоналі</summary>
        public int GradDir = 0;
        /// <summary>Інтервал між літерами, px</summary>
        public double Tracking = 0;

        public bool Styled => Outline > 0 || ShadowX != 0 || ShadowY != 0 || !string.IsNullOrEmpty(Color2) || Math.Abs(WidthPct - 100) > 0.01 || FillAlpha < 100 || Tracking != 0;

        /// <summary>Скопіювати вигляд (шрифт, колір, ефекти) з набору, не чіпаючи розміру й тексту</summary>
        public void ApplyStyle(Generator s)
        {
            Font = s.Font; Style = s.Style; Weight = s.Weight; Color = s.Color; Color2 = s.Color2;
            Outline = s.Outline; OutlineColor = s.OutlineColor; ShadowX = s.ShadowX; ShadowY = s.ShadowY; ShadowColor = s.ShadowColor; WidthPct = s.WidthPct;
            Badge = s.Badge; BadgeColor = s.BadgeColor;
            FillAlpha = s.FillAlpha; OutlinePos = s.OutlinePos; OutlineAlpha = s.OutlineAlpha; ShadowAlpha = s.ShadowAlpha; GradDir = s.GradDir; Tracking = s.Tracking;
        }

        public Generator(GenKind kind) { Kind = kind; }
        public Generator Copy() { var c = (Generator)MemberwiseClone(); c.Texts = new List<string>(Texts); return c; }

        static readonly string[] KindNames = { "digits", "arc", "line", "pointer", "image", "frames", "label", "texts" };

        public Dictionary<string, object> ToJson() => new Dictionary<string, object>
        {
            ["kind"] = KindNames[(int)Kind], ["color"] = Color, ["bgColor"] = BgColor, ["fontSize"] = FontSize, ["weight"] = Weight,
            ["style"] = Style, ["font"] = Font, ["radius"] = Radius, ["width"] = Width, ["length"] = Length, ["unit"] = Unit, ["text"] = Text,
            ["start"] = Start, ["range"] = Range, ["angle"] = Angle, ["round"] = Round,
            ["outline"] = Outline, ["outlineColor"] = OutlineColor, ["shadowX"] = ShadowX, ["shadowY"] = ShadowY, ["shadowColor"] = ShadowColor,
            ["color2"] = Color2, ["widthPct"] = WidthPct, ["texts"] = Texts.Cast<object>().ToList(),
            ["badge"] = Badge, ["badgeColor"] = BadgeColor,
            ["fillAlpha"] = FillAlpha, ["outlinePos"] = OutlinePos, ["outlineAlpha"] = OutlineAlpha, ["shadowAlpha"] = ShadowAlpha, ["gradDir"] = GradDir, ["tracking"] = Tracking,
        };

        public static Generator FromJson(Dictionary<string, object> d)
        {
            int k = Array.IndexOf(KindNames, Json.Str(d, "kind", "image"));
            var gen = new Generator(k < 0 ? GenKind.Image : (GenKind)k)
            {
                Color = Json.Str(d, "color", "#FFFFFF"), BgColor = Json.Str(d, "bgColor", "#3A3A3C"),
                FontSize = Json.Num(d, "fontSize", 48), Weight = (int)Json.Num(d, "weight", 700),
                Style = Json.Str(d, "style", "rounded"), Font = Json.Str(d, "font", ""),
                Radius = Json.Num(d, "radius", 60), Width = Json.Num(d, "width", 10), Length = Json.Num(d, "length", 120),
                Unit = Json.Str(d, "unit", ""), Text = Json.Str(d, "text", ""),
                // старі проєкти без цих полів: дуга була повним кільцем, лінія — горизонтальною
                Start = Json.Num(d, "start", 0), Range = Json.Num(d, "range", 360), Angle = Json.Num(d, "angle", 0), Round = Json.Bool(d, "round", true),
                Outline = Json.Num(d, "outline", 0), OutlineColor = Json.Str(d, "outlineColor", "#000000"),
                ShadowX = Json.Num(d, "shadowX", 0), ShadowY = Json.Num(d, "shadowY", 0), ShadowColor = Json.Str(d, "shadowColor", "#000000"),
                Color2 = Json.Str(d, "color2", ""), WidthPct = Json.Num(d, "widthPct", 100),
                Texts = (d.TryGetValue("texts", out var tx) && tx is List<object> tl) ? tl.Select(o => o?.ToString() ?? "").ToList() : new List<string>(),
                Badge = Json.Str(d, "badge", ""), BadgeColor = Json.Str(d, "badgeColor", "#FF9F0A"),
                FillAlpha = Json.Num(d, "fillAlpha", 100), OutlinePos = (int)Json.Num(d, "outlinePos", 0), OutlineAlpha = Json.Num(d, "outlineAlpha", 100),
                ShadowAlpha = Json.Num(d, "shadowAlpha", 60), GradDir = (int)Json.Num(d, "gradDir", 0), Tracking = Json.Num(d, "tracking", 0),
            };
            if (Json.Bool(d, "hollow", false))
            {
                // «лише контур» → заливка 0% і обведення по центру кольором тексту
                gen.FillAlpha = 0; gen.OutlinePos = 1; gen.Outline = Math.Max(1.2, gen.FontSize / 22); gen.OutlineColor = gen.Color; gen.Color2 = "";
            }
            return gen;
        }

        public bool Drawn => Kind != GenKind.Image && Kind != GenKind.Frames;
    }

    /// <summary>Пристрій: розмір екрана полотна. Smart Band 10 і 11 — однаковий екран 212×520.</summary>
    public sealed class DeviceProfile
    {
        public string Id, Title;
        public int Width, Height;
        public double Corner;

        public static readonly DeviceProfile Band10 = new DeviceProfile { Id = "band10", Title = "Xiaomi Smart Band 10", Width = 212, Height = 520, Corner = 106 };
        public static readonly DeviceProfile Band11 = new DeviceProfile { Id = "band11", Title = "Xiaomi Smart Band 11", Width = 212, Height = 520, Corner = 106 };
        public static readonly DeviceProfile[] All = { Band10, Band11 };

        public static DeviceProfile ById(string id) => All.FirstOrDefault(d => d.Id == id) ?? Band10;
    }

    public sealed class ProjectMeta
    {
        public DeviceProfile Device = DeviceProfile.Band10;
        public Dictionary<string, Generator> Generators = new Dictionary<string, Generator>();
        public DateTime Modified = DateTime.UtcNow;
        /// <summary>Циферблат змінювали в редакторі: при збиранні превʼю для браслета малюється заново</summary>
        public bool Edited;
        public string SourceKey;
        /// <summary>Елементи з увімкненою галочкою «Змінюється з кольором циферблата» (діє, щойно в циферблата з'являться кольори)</summary>
        public HashSet<string> ColorFollow = new HashSet<string>();
        /// <summary>Віджети, розмір яких задано вручну (не підганяється під вміст)</summary>
        public HashSet<string> ManualSize = new HashSet<string>();
        /// <summary>Значення для перегляду в редакторі (на браслет не записуються)</summary>
        public DemoValues Demo = new DemoValues();
        /// <summary>Вигляд рамки вибору на браслеті для кожного слота (за назвою слота)</summary>
        public Dictionary<string, SlotFrame> SlotFrames = new Dictionary<string, SlotFrame>();

        public ProjectMeta Copy()
        {
            var m = (ProjectMeta)MemberwiseClone();
            m.Demo = Demo.Copy();
            m.Generators = Generators.ToDictionary(kv => kv.Key, kv => kv.Value.Copy());
            m.ColorFollow = new HashSet<string>(ColorFollow);
            m.ManualSize = new HashSet<string>(ManualSize);
            m.SlotFrames = SlotFrames.ToDictionary(kv => kv.Key, kv => kv.Value.Copy());
            return m;
        }

        public Generator Gen(string name) => name != null && Generators.TryGetValue(name, out var g) ? g : null;

        /// <summary>Як у Foundation: секунди від 2001-01-01 UTC (сумісність з iOS)</summary>
        static readonly DateTime Ref2001 = new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        public string ToJson()
        {
            var gens = new Dictionary<string, object>();
            foreach (var kv in Generators) gens[kv.Key] = kv.Value.ToJson();
            var d = new Dictionary<string, object>
            {
                ["device"] = new Dictionary<string, object> { ["id"] = Device.Id, ["title"] = Device.Title, ["width"] = Device.Width, ["height"] = Device.Height, ["corner"] = Device.Corner },
                ["generators"] = gens,
                ["modified"] = (Modified.ToUniversalTime() - Ref2001).TotalSeconds,
                ["edited"] = Edited,
            };
            if (SourceKey != null) d["sourceKey"] = SourceKey;
            if (ColorFollow.Count > 0) d["colorFollow"] = ColorFollow.Cast<object>().ToList();
            if (ManualSize.Count > 0) d["manualSize"] = ManualSize.Cast<object>().ToList();
            if (SlotFrames.Count > 0) d["slotFrames"] = SlotFrames.ToDictionary(kv => kv.Key, kv => (object)kv.Value.ToJson());
            if (!Demo.IsEmpty) d["demo"] = Demo.ToJson();
            return Json.Write(d);
        }

        public static ProjectMeta FromJson(string s)
        {
            var m = new ProjectMeta();
            try
            {
                var d = Json.Parse(s) as Dictionary<string, object>;
                if (d == null) return m;
                m.Device = DeviceProfile.ById(Json.Str(Json.Obj(d, "device"), "id", "band10"));
                var g = Json.Obj(d, "generators");
                if (g != null)
                    foreach (var kv in g)
                        if (kv.Value is Dictionary<string, object> gd) m.Generators[kv.Key] = Generator.FromJson(gd);
                if (d.TryGetValue("modified", out var mv) && mv is double secs) m.Modified = Ref2001.AddSeconds(secs);
                m.Edited = Json.Bool(d, "edited", false);
                m.SourceKey = Json.Str(d, "sourceKey", null);
                if (d.TryGetValue("colorFollow", out var cf) && cf is List<object> cl) m.ColorFollow = new HashSet<string>(cl.Select(o => o?.ToString() ?? ""));
                if (d.TryGetValue("manualSize", out var ms) && ms is List<object> ml) m.ManualSize = new HashSet<string>(ml.Select(o => o?.ToString() ?? ""));
                var sf = Json.Obj(d, "slotFrames");
                if (sf != null)
                    foreach (var kv in sf)
                        if (kv.Value is Dictionary<string, object> fd) m.SlotFrames[kv.Key] = SlotFrame.FromJson(fd);
                m.Demo = DemoValues.FromJson(Json.Obj(d, "demo"));
            }
            catch (Exception) { }
            return m;
        }
    }

    /// <summary>Вигляд рамки вибору слота на браслеті. Формат editor.json спільний з iOS.</summary>
    public sealed class SlotFrame
    {
        /// <summary>Колір лінії, #RRGGBB</summary>
        public string Color = "#FFFFFF";
        /// <summary>Непрозорість лінії, %</summary>
        public int Alpha = 50;
        /// <summary>Товщина лінії, px</summary>
        public int Width = 3;
        /// <summary>Заливка всередині, %</summary>
        public int Fill = 0;
        /// <summary>0 — за формою віджета, 1 — без рамки</summary>
        public int Shape = 0;
        /// <summary>Заокруглення кутів біля краю екрана, px</summary>
        public int Radius = 16;
        /// <summary>Запас від елементів у режимі «За вмістом», px</summary>
        public int Pad = 7;

        public SlotFrame Copy() => (SlotFrame)MemberwiseClone();
        public bool IsDefault => Same(new SlotFrame());
        public bool Same(SlotFrame o) => string.Equals(Color, o.Color, StringComparison.OrdinalIgnoreCase) && Alpha == o.Alpha && Width == o.Width && Fill == o.Fill && Shape == o.Shape && Radius == o.Radius && Pad == o.Pad;

        static SlotFrame Make(string c, int a, int w, int fill, int r) => new SlotFrame { Color = c, Alpha = a, Width = w, Fill = fill, Radius = r };
        /// <summary>Швидкі стилі: ключ назви, вигляд</summary>
        public static readonly List<KeyValuePair<string, SlotFrame>> Presets = new List<KeyValuePair<string, SlotFrame>>
        {
            new KeyValuePair<string, SlotFrame>("frameWhite", Make("#FFFFFF", 50, 3, 0, 10)),
            new KeyValuePair<string, SlotFrame>("frameThin", Make("#FFFFFF", 35, 2, 0, 10)),
            new KeyValuePair<string, SlotFrame>("frameAccent", Make("#0A84FF", 100, 3, 0, 16)),
            new KeyValuePair<string, SlotFrame>("frameGlow", Make("#FFFFFF", 90, 2, 14, 16)),
        };

        public Dictionary<string, object> ToJson() => new Dictionary<string, object>
        {
            ["color"] = Color, ["alpha"] = (double)Alpha, ["width"] = (double)Width, ["fill"] = (double)Fill,
            ["shape"] = (double)Shape, ["radius"] = (double)Radius, ["pad"] = (double)Pad,
        };

        public static SlotFrame FromJson(Dictionary<string, object> d) => new SlotFrame
        {
            Color = Json.Str(d, "color", "#FFFFFF"), Alpha = (int)Json.Num(d, "alpha", 50), Width = (int)Json.Num(d, "width", 3),
            Fill = (int)Json.Num(d, "fill", 0), Shape = (int)Json.Num(d, "shape", 0), Radius = (int)Json.Num(d, "radius", 16), Pad = (int)Json.Num(d, "pad", 7),
        };
    }

    /// <summary>Значення для перегляду: свої для кожного джерела; час і дата — свої або справжні (з комп'ютера).
    /// Формат editor.json спільний з iOS.</summary>
    public sealed class DemoValues
    {
        public Dictionary<string, int> Values = new Dictionary<string, int>();
        /// <summary>"HH:mm"; null — типовий 10:24</summary>
        public string Time;
        /// <summary>"yyyy-MM-dd"; null — типова 30.05.2026</summary>
        public string Date;
        public bool RealTime, RealDate;

        public bool IsEmpty => Values.Count == 0 && Time == null && Date == null && !RealTime && !RealDate;

        public DemoValues Copy() => new DemoValues { Values = new Dictionary<string, int>(Values), Time = Time, Date = Date, RealTime = RealTime, RealDate = RealDate };

        /// <summary>Свої години й хвилини, якщо задано</summary>
        public bool TryTime(out int h, out int m)
        {
            h = m = 0;
            var p = (Time ?? "").Split(':');
            return p.Length == 2 && int.TryParse(p[0], out h) && int.TryParse(p[1], out m);
        }

        /// <summary>Своя дата, якщо задано</summary>
        public bool TryDate(out int day, out int month, out int year)
        {
            day = month = year = 0;
            var p = (Date ?? "").Split('-');
            return p.Length == 3 && int.TryParse(p[0], out year) && int.TryParse(p[1], out month) && int.TryParse(p[2], out day);
        }

        public Dictionary<string, object> ToJson()
        {
            var d = new Dictionary<string, object>
            {
                ["values"] = Values.ToDictionary(kv => kv.Key, kv => (object)kv.Value),
                ["realTime"] = RealTime, ["realDate"] = RealDate,
            };
            if (Time != null) d["time"] = Time;
            if (Date != null) d["date"] = Date;
            return d;
        }

        public static DemoValues FromJson(Dictionary<string, object> d)
        {
            var r = new DemoValues();
            if (d == null) return r;
            var v = Json.Obj(d, "values");
            if (v != null) foreach (var kv in v) if (kv.Value is double n) r.Values[kv.Key] = (int)n;
            r.Time = Json.Str(d, "time", null);
            r.Date = Json.Str(d, "date", null);
            r.RealTime = Json.Bool(d, "realTime", false);
            r.RealDate = Json.Bool(d, "realDate", false);
            return r;
        }
    }
}
