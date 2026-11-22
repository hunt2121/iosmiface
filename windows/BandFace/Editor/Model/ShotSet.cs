// SPDX-License-Identifier: MIT
// «Набір знімків»: кілька екранів циферблата (стилі, кольори, AOD, стани) на одній оформленій картинці.
// Формат спільний з iOS (поле shots у параметрах редактора).

using System;
using System.Collections.Generic;
using System.Linq;
using BandFace.Faces;

namespace BandFace.Creator
{
    public sealed class ShotScreen
    {
        public string Id = Guid.NewGuid().ToString().ToUpperInvariant();
        /// <summary>Номер стилю з 0 (за порядком стилів, без AOD)</summary>
        public int Style;
        /// <summary>«Завжди на екрані» цього стилю</summary>
        public bool Aod;
        /// <summary>Кольоровий варіант: 0 — основний</summary>
        public int Color;
        /// <summary>Свій підпис; порожньо — «Стиль 1 · Колір 2»</summary>
        public string Name = "";
        /// <summary>Ще екран цього стилю з від'єднаним Bluetooth / із зарядом 15 %</summary>
        public bool Bluetooth, Battery;
        /// <summary>Віджети в слотах: назва слота → номер віджета (без запису — як у редакторі)</summary>
        public Dictionary<string, int> Widgets = new Dictionary<string, int>();

        public ShotScreen Copy() { var c = (ShotScreen)MemberwiseClone(); c.Widgets = new Dictionary<string, int>(Widgets); return c; }

        public Dictionary<string, object> ToJson() => new Dictionary<string, object>
        {
            ["id"] = Id, ["style"] = Style, ["aod"] = Aod, ["color"] = Color, ["name"] = Name, ["bluetooth"] = Bluetooth, ["battery"] = Battery,
            ["widgets"] = Widgets.ToDictionary(kv => kv.Key, kv => (object)kv.Value),
        };

        public static ShotScreen FromJson(Dictionary<string, object> d)
        {
            var r = Make(d);
            var w = Json.Obj(d, "widgets");
            if (w != null) foreach (var kv in w) if (kv.Value is double n) r.Widgets[kv.Key] = (int)n;
            return r;
        }

        static ShotScreen Make(Dictionary<string, object> d) => new ShotScreen
        {
            Id = Json.Str(d, "id", Guid.NewGuid().ToString().ToUpperInvariant()),
            Style = (int)Json.Num(d, "style", 0), Aod = Json.Bool(d, "aod", false), Color = (int)Json.Num(d, "color", 0),
            Name = Json.Str(d, "name", ""), Bluetooth = Json.Bool(d, "bluetooth", false), Battery = Json.Bool(d, "battery", false),
        };
    }

    public sealed class ShotSet
    {
        public List<ShotScreen> Screens = new List<ShotScreen>();
        /// <summary>auto, square (1:1), story (9:16), wide (16:9)</summary>
        public string Format = "auto";
        /// <summary>0 — великі, 1 — середні, 2 — малі</summary>
        public int Size = 1;
        /// <summary>Рамка «Браслет» замість капсули</summary>
        public bool Band;
        /// <summary>Свій час на екранах "HH:mm"; null — як у циферблаті</summary>
        public string Time;
        /// <summary>dark, black, white, light, blue, face або свій колір "#RRGGBB"</summary>
        public string Background = "dark";
        /// <summary>Тексти; null — автоматичні, "" — без рядка</summary>
        public string Title, Above, Below;
        public bool Rounded = true, Captions = true, Shadow = true, Credit, Remember = true;

        public static readonly string[] Backgrounds = { "dark", "black", "white", "light", "blue", "face" };

        public ShotSet Copy()
        {
            var s = (ShotSet)MemberwiseClone();
            s.Screens = Screens.Select(x => x.Copy()).ToList();
            return s;
        }

        public static ShotSet Start(int style, int color, bool aod) =>
            new ShotSet { Screens = new List<ShotScreen> { new ShotScreen { Style = style, Color = color, Aod = aod } } };

        /// <summary>Скільки екранів буде на картинці (зі станами)</summary>
        public int Count => Screens.Sum(s => s.Bluetooth && s.Battery ? 2 : 1);

        public Dictionary<string, object> ToJson()
        {
            var d = new Dictionary<string, object>
            {
                ["screens"] = Screens.Select(s => (object)s.ToJson()).ToList(),
                ["format"] = Format, ["size"] = Size, ["band"] = Band, ["background"] = Background,
                ["rounded"] = Rounded, ["captions"] = Captions, ["shadow"] = Shadow, ["credit"] = Credit, ["remember"] = Remember,
            };
            if (Time != null) d["time"] = Time;
            if (Title != null) d["title"] = Title;
            if (Above != null) d["above"] = Above;
            if (Below != null) d["below"] = Below;
            return d;
        }

        public static ShotSet FromJson(Dictionary<string, object> d)
        {
            if (d == null) return null;
            var s = new ShotSet
            {
                Format = Json.Str(d, "format", "auto"), Size = (int)Json.Num(d, "size", 1), Band = Json.Bool(d, "band", false),
                Time = Json.Str(d, "time", null), Background = Json.Str(d, "background", "dark"),
                Title = Json.Str(d, "title", null), Above = Json.Str(d, "above", null), Below = Json.Str(d, "below", null),
                Rounded = Json.Bool(d, "rounded", true), Captions = Json.Bool(d, "captions", true), Shadow = Json.Bool(d, "shadow", true),
                Credit = Json.Bool(d, "credit", false), Remember = Json.Bool(d, "remember", true),
            };
            if (d.TryGetValue("screens", out var v) && v is List<object> list)
                foreach (var o in list) if (o is Dictionary<string, object> sd) s.Screens.Add(ShotScreen.FromJson(sd));
            return s;
        }
    }

    static class ShotSources
    {
        /// <summary>Слоти теми (місця, де віджет вибирають на браслеті) у порядку шарів</summary>
        public static List<XNode> Slots(this FaceProject p, int theme) =>
            p.Layouts(theme).Select(l => p.ResourceRef(l.Str("ref"))).Where(r => r != null && r.Tag == "Slot").ToList();

        /// <summary>Є елемент, що показує стан Bluetooth / заряд (тоді є сенс у знімках із цими станами)</summary>
        public static bool UsesSource(this FaceProject p, string key)
        {
            bool Scan(XNode n) => (n.Str("source")?.ToLowerInvariant().Contains(key) ?? false) || n.Kids.Any(Scan);
            return Scan(p.Root);
        }
    }
}
