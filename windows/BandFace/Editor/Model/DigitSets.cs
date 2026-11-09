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
        public sealed class Set { public string Name; public Generator Style; public bool BuiltIn; }

        static string File => Path.Combine(Path.GetDirectoryName(ProjectStore.Base), "digitsets.json");

        static Generator G(Action<Generator> f) { var g = new Generator(GenKind.Digits) { Color = "#FFFFFF", Weight = 700, Style = "rounded" }; f(g); return g; }

        /// <summary>Готові набори (назви — ключі рядків)</summary>
        static IEnumerable<Set> BuiltIns() => new[]
        {
            new Set { Name = S.Get("dsClassic"), BuiltIn = true, Style = G(g => { }) },
            new Set { Name = S.Get("dsNeon"), BuiltIn = true, Style = G(g => { g.Color = "#7DF9FF"; g.Outline = 2; g.OutlineColor = "#0A84FF"; }) },
            new Set { Name = S.Get("dsSunset"), BuiltIn = true, Style = G(g => { g.Color = "#FFD60A"; g.Color2 = "#FF375F"; g.Weight = 800; }) },
            new Set { Name = S.Get("dsShadow"), BuiltIn = true, Style = G(g => { g.ShadowX = 2; g.ShadowY = 3; g.ShadowColor = "#000000"; g.Weight = 800; }) },
            new Set { Name = S.Get("dsNarrow"), BuiltIn = true, Style = G(g => { g.Style = "condensed"; g.WidthPct = 80; g.Weight = 600; }) },
            new Set { Name = S.Get("dsOutline"), BuiltIn = true, Style = G(g => { g.Color = "#000000"; g.Outline = 2; g.OutlineColor = "#FFFFFF"; g.Weight = 800; }) },
        };

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

        public static List<Set> All() => BuiltIns().Concat(User()).ToList();

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
            g.ApplyStyle(style);
            u.Add(new Set { Name = name, Style = g });
            Save(u);
        }

        public static void Remove(string name)
        {
            var u = User();
            u.RemoveAll(s => s.Name == name);
            Save(u);
        }
    }
}
