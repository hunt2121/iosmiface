// SPDX-License-Identifier: MIT
// Пробні значення джерел для полотна й зрозумілі назви джерел для вибору.

using System;
using System.Collections.Generic;
using System.Linq;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class SampleData
    {
        /// <summary>Значення для перегляду; live — поточний час і дата; demo — значення, задані в проєкті.</summary>
        public static int Value(string s, bool live = false, DemoValues demo = null)
        {
            s = s ?? "";
            var now = DateTime.Now;
            bool liveTime = live || (demo != null && demo.RealTime), liveDate = live || (demo != null && demo.RealDate);
            int v;
            if (s.StartsWith("time"))
            {
                int oh = 9, om = 55;
                if (demo != null && demo.TryTime(out var th, out var tm)) { oh = th; om = tm; }
                if (s.Contains("Hour")) { v = liveTime ? now.Hour : oh; if (s.Contains("12")) v = v % 12 == 0 ? 12 : v % 12; }
                else if (s.Contains("Minute")) v = liveTime ? now.Minute : om;
                else if (s.Contains("Second")) v = liveTime ? now.Second : 36;
                else v = 0;
                if (s.EndsWith("High")) return v / 10;
                if (s.EndsWith("Low")) return v % 10;
                return v;
            }
            if (s.StartsWith("date"))
            {
                // своя дата: день тижня рахується з неї. Браслет рахує з неділі: 0 — неділя, 6 — субота
                // (в офіційних циферблатах картинки днів тижня йдуть SUN, MON … SAT)
                int day = 30, month = 5, year = 2026, week = 6;
                if (liveDate) { day = now.Day; month = now.Month; year = now.Year; week = (int)now.DayOfWeek; }
                else if (demo != null && demo.TryDate(out var dd, out var dm, out var dy))
                {
                    day = dd; month = dm; year = dy;
                    try { week = (int)new DateTime(dy, dm, dd).DayOfWeek; } catch (ArgumentException) { }
                }
                if (s.Contains("Week")) return week;
                if (s.Contains("Year")) return year % (s.Contains("Low") ? 100 : 10000);
                if (s.Contains("Month")) v = month;
                else if (s.Contains("Day")) v = day;
                else return 1;
                if (s.EndsWith("High")) return v / 10;
                if (s.EndsWith("Low")) return v % 10;
                return v;
            }
            if (demo != null && demo.Values.TryGetValue(s, out var own)) return own;
            var l = s.ToLowerInvariant();
            // стани як у звичайному вигляді: «не турбувати» вимкнено, Bluetooth підключено
            if (l.Contains("disturb")) return 0;
            if (l.Contains("bluetooth")) return 1;
            if (l.Contains("step")) return l.Contains("progress") ? 71 : 7133;
            if (l.Contains("heart")) return 72;
            if (l.Contains("battery")) return 80;
            if (l.Contains("calorie")) return l.Contains("progress") ? 46 : 320;
            if (l.Contains("stand")) return 7;
            if (l.Contains("sleep")) return 7;
            if (l.Contains("oxygen") || l.Contains("spo")) return 98;
            if (l.Contains("pressure") || l.Contains("stress")) return 32;
            if (l.Contains("temperature") || l.Contains("weather")) return 18;
            if (l.Contains("distance")) return 6;
            if (l.Contains("progress")) return 65;
            return 42;
        }

        /// <summary>Межі повзунка «Значення для перегляду»</summary>
        public static (int Min, int Max) DemoRange(string source)
        {
            var l = (source ?? "").ToLowerInvariant();
            if (l.Contains("disturb") || l.Contains("bluetooth")) return (0, 1);
            if (l.Contains("progress") || l.Contains("percent") || l.Contains("battery") || l.Contains("stress")) return (0, 100);
            if (l.Contains("step")) return (0, 30000);
            if (l.Contains("heart")) return (30, 220);
            if (l.Contains("calorie")) return (0, 2000);
            if (l.Contains("oxygen") || l.Contains("spo")) return (70, 100);
            if (l.Contains("temperature") || l.Contains("weather")) return (-30, 45);
            if (l.Contains("distance")) return (0, 50);
            if (l.Contains("stand") || l.Contains("sleep")) return (0, 12);
            return (0, 100);
        }

        /// <summary>Зрозуміла назва джерела (ключ рядка src_…), інакше — як є</summary>
        public static string Title(string source) => S.Has("src_" + source) ? S.Get("src_" + source) : source;
        public static bool HasTitle(string source) => S.Has("src_" + source);

        static readonly string[] GroupPrefixes = { "time", "date", "health", "weather", "system", "app", "dualtime" };

        /// <summary>Група джерела за префіксом (time, date, health…; інакше other)</summary>
        public static string GroupOf(string source)
        {
            // dualtime починається не з time, тож порядок префіксів не заважає
            foreach (var p in GroupPrefixes) if (!string.IsNullOrEmpty(source) && source.StartsWith(p)) return p;
            return "other";
        }

        /// <summary>Значок групи (Segoe MDL2)</summary>
        public static string GroupGlyph(string group)
        {
            switch (group)
            {
                case "time": return "\uE823";     // годинник
                case "date": return "\uE787";     // календар
                case "health": return "\uE95E";   // серце
                case "weather": return "\uE753";  // хмара
                case "system": return "\uE83F";   // батарея
                case "app": return "\uE71D";      // застосунки
                case "dualtime": return "\uE774"; // глобус
                default: return "\uE712";         // інше
            }
        }

        public sealed class Group
        {
            public string Id, Title;
            public List<string> Sources;
        }

        /// <summary>Усі джерела компілятора, згруповані за префіксом.</summary>
        public static List<Group> Groups()
        {
            var unique = FaceCatalog.Sources.Select(x => x.Item1).Distinct().ToList();
            var prefixes = GroupPrefixes;
            var o = new List<Group>();
            var rest = new List<string>(unique);
            foreach (var p in prefixes)
            {
                var g = unique.Where(x => x.StartsWith(p)).ToList();
                rest.RemoveAll(x => x.StartsWith(p));
                if (g.Count > 0) o.Add(new Group { Id = p, Title = S.Get("grp_" + p), Sources = g });
            }
            if (rest.Count > 0) o.Add(new Group { Id = "other", Title = S.Get("grp_other"), Sources = rest });
            return o;
        }
    }
}
