// SPDX-License-Identifier: MIT
// Налаштування редактора для проєкту (editor.json): пристрій, параметри згенерованих елементів, час зміни.
// Формат сумісний з BandFace для iOS, тож проєкти переносяться між телефоном і комп'ютером.

using System;
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Creator
{
    public enum GenKind { Digits, Arc, Line, Pointer, Image, Frames, Label }

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
        public double Start = 220, Range = 280;
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

        public bool Styled => Outline > 0 || ShadowX != 0 || ShadowY != 0 || !string.IsNullOrEmpty(Color2) || Math.Abs(WidthPct - 100) > 0.01;

        /// <summary>Скопіювати вигляд (шрифт, колір, ефекти) з набору, не чіпаючи розміру й тексту</summary>
        public void ApplyStyle(Generator s)
        {
            Font = s.Font; Style = s.Style; Weight = s.Weight; Color = s.Color; Color2 = s.Color2;
            Outline = s.Outline; OutlineColor = s.OutlineColor; ShadowX = s.ShadowX; ShadowY = s.ShadowY; ShadowColor = s.ShadowColor; WidthPct = s.WidthPct;
        }

        public Generator(GenKind kind) { Kind = kind; }
        public Generator Copy() => (Generator)MemberwiseClone();

        static readonly string[] KindNames = { "digits", "arc", "line", "pointer", "image", "frames", "label" };

        public Dictionary<string, object> ToJson() => new Dictionary<string, object>
        {
            ["kind"] = KindNames[(int)Kind], ["color"] = Color, ["bgColor"] = BgColor, ["fontSize"] = FontSize, ["weight"] = Weight,
            ["style"] = Style, ["font"] = Font, ["radius"] = Radius, ["width"] = Width, ["length"] = Length, ["unit"] = Unit, ["text"] = Text,
            ["start"] = Start, ["range"] = Range, ["angle"] = Angle, ["round"] = Round,
            ["outline"] = Outline, ["outlineColor"] = OutlineColor, ["shadowX"] = ShadowX, ["shadowY"] = ShadowY, ["shadowColor"] = ShadowColor,
            ["color2"] = Color2, ["widthPct"] = WidthPct,
        };

        public static Generator FromJson(Dictionary<string, object> d)
        {
            int k = Array.IndexOf(KindNames, Json.Str(d, "kind", "image"));
            return new Generator(k < 0 ? GenKind.Image : (GenKind)k)
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
            };
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

        public ProjectMeta Copy()
        {
            var m = (ProjectMeta)MemberwiseClone();
            m.Generators = Generators.ToDictionary(kv => kv.Key, kv => kv.Value.Copy());
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
            }
            catch (Exception) { }
            return m;
        }
    }
}
