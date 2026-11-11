// SPDX-License-Identifier: MIT
// Бібліотека наборів цифр (П-2): готові стилі й збережені користувачем
// (%LOCALAPPDATA%\BandFace\Creator\digitsets.json). Набір — це вигляд: шрифт, колір, градієнт, обвідка, тінь, ширина літер.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace BandFace.Creator
{
    static class DigitSets
    {
        public sealed class Set { public string Name; public Generator Style; public bool BuiltIn; // ключ вбудованого стилю (не залежить від мови)
            public string Key; }

        static string File => Path.Combine(Path.GetDirectoryName(ProjectStore.Base), "digitsets.json");
        static string HiddenFile => Path.Combine(Path.GetDirectoryName(ProjectStore.Base), "digitsets-hidden.json");

        static Generator G(Action<Generator> f) { var g = new Generator(GenKind.Digits) { Color = "#FFFFFF" }; f(g); return g; }

        /// <summary>Вбудовані стилі: лише оформлення (шрифт, накреслення й розмір лишаються вибраними)</summary>
        static IEnumerable<Set> BuiltIns() => new[]
        {
            new Set { Key = "stlClean", Name = S.Get("stlClean"), BuiltIn = true, Style = G(g => { }) },
            new Set { Key = "stlSunset", Name = S.Get("stlSunset"), BuiltIn = true, Style = G(g => { g.Color = "#FFD60A"; g.Color2 = "#FF375F"; g.GradDir = 1; }) },
            new Set { Key = "stlNeon", Name = S.Get("stlNeon"), BuiltIn = true, Style = G(g => { g.Color = "#7DF9FF"; g.Outline = 2; g.OutlineColor = "#0A84FF"; g.OutlineAlpha = 70; }) },
            new Set { Key = "stlOutline", Name = S.Get("stlOutline"), BuiltIn = true, Style = G(g => { g.FillAlpha = 0; g.Outline = 1.5; g.OutlinePos = 1; g.OutlineColor = "#FFFFFF"; }) },
            new Set { Key = "stlShadow", Name = S.Get("stlShadow"), BuiltIn = true, Style = G(g => { g.ShadowX = 2; g.ShadowY = 3; g.ShadowColor = "#000000"; g.ShadowAlpha = 70; }) },
            new Set { Key = "stlStroke", Name = S.Get("stlStroke"), BuiltIn = true, Style = G(g => { g.Outline = 2; g.OutlineColor = "#FF9F0A"; }) },
            new Set { Key = "stlOcean", Name = S.Get("stlOcean"), BuiltIn = true, Style = G(g => { g.Color = "#64D2FF"; g.Color2 = "#5E5CE6"; g.GradDir = 1; }) },
            new Set { Key = "stlGlass", Name = S.Get("stlGlass"), BuiltIn = true, Style = G(g => { g.FillAlpha = 45; }) },
            new Set { Key = "stlTerminal", Name = S.Get("stlTerminal"), BuiltIn = true, Style = G(g => { g.Color = "#30D158"; }) },
            new Set { Key = "stlEmboss", Name = S.Get("stlEmboss"), BuiltIn = true, Style = G(g => { g.ShadowX = 1; g.ShadowY = 1; g.ShadowColor = "#000000"; g.ShadowAlpha = 90; g.Outline = 1; g.OutlineColor = "#8E8E93"; g.OutlinePos = 2; }) },
            new Set { Key = "stlGold", Name = S.Get("stlGold"), BuiltIn = true, Style = G(g => { g.Color = "#FFE08A"; g.Color2 = "#B8860B"; g.GradDir = 1; }) },
            new Set { Key = "stlSpaced", Name = S.Get("stlSpaced"), BuiltIn = true, Style = G(g => { g.Tracking = 4; }) },
        };

        static HashSet<string> Hidden()
        {
            try { if (System.IO.File.Exists(HiddenFile) && Json.Parse(System.IO.File.ReadAllText(HiddenFile)) is List<object> l) return new HashSet<string>(l.Select(x => x as string).Where(x => x != null)); }
            catch (Exception) { }
            return new HashSet<string>();
        }

        public static List<Set> User()
        {
            var o = new List<Set>();
            try
            {
                if (!System.IO.File.Exists(File)) return o;
                if (Json.Parse(System.IO.File.ReadAllText(File)) is List<object> list)
                    foreach (var x in list)
                        if (x is Dictionary<string, object> d && Json.Obj(d, "style") is Dictionary<string, object> st)
                            o.Add(new Set { Name = Json.Str(d, "name", "?"), Style = Generator.FromJson(st) });
            }
            catch (Exception) { }
            return o;
        }

        public static List<Set> All() { var h = Hidden(); return BuiltIns().Where(s => !h.Contains(s.Key)).Concat(User()).ToList(); }

        static void Save(List<Set> user)
        {
            try
            {
                var arr = user.Select(s => (object)new Dictionary<string, object> { ["name"] = s.Name, ["style"] = s.Style.ToJson() }).ToList();
                System.IO.File.WriteAllText(File, Json.Write(arr));
            }
            catch (Exception) { }
        }

        public static void Add(string name, Generator style)
        {
            var u = User();
            u.RemoveAll(s => string.Equals(s.Name, name, StringComparison.CurrentCultureIgnoreCase));
            var g = new Generator(GenKind.Digits);
            g.ApplyLook(style);
            u.Add(new Set { Name = name, Style = g });
            Save(u);
        }

        /// <summary>Видалити стиль; вбудований — ховається (запам'ятовується)</summary>
        public static void Remove(Set set)
        {
            if (set.BuiltIn)
            {
                var h = Hidden(); h.Add(set.Key ?? set.Name);
                try { System.IO.File.WriteAllText(HiddenFile, Json.Write(h.Select(x => (object)x).ToList())); } catch (Exception) { }
                return;
            }
            var u = User();
            u.RemoveAll(s => s.Name == set.Name);
            Save(u);
        }
    }
}
