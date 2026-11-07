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
        /// <summary>Значення для перегляду; live — поточний час і дата.</summary>
        public static int Value(string s, bool live = false)
        {
            s = s ?? "";
            var now = DateTime.Now;
            int v;
            if (s.StartsWith("time"))
            {
                if (s.Contains("Hour")) { v = live ? now.Hour : 10; if (s.Contains("12")) v = v % 12 == 0 ? 12 : v % 12; }
                else if (s.Contains("Minute")) v = live ? now.Minute : 24;
                else if (s.Contains("Second")) v = live ? now.Second : 36;
                else v = 0;
                if (s.EndsWith("High")) return v / 10;
                if (s.EndsWith("Low")) return v % 10;
                return v;
            }
            if (s.StartsWith("date"))
            {
                // день тижня: 0 — понеділок
                if (s.Contains("Week")) return live ? ((int)now.DayOfWeek + 6) % 7 : 4;
                if (s.Contains("Year")) return (live ? now.Year : 2026) % (s.Contains("Low") ? 100 : 10000);
                if (s.Contains("Month")) v = live ? now.Month : 5;
                else if (s.Contains("Day")) v = live ? now.Day : 30;
                else return 1;
                if (s.EndsWith("High")) return v / 10;
                if (s.EndsWith("Low")) return v % 10;
                return v;
            }
            var l = s.ToLowerInvariant();
            // стани як у звичайному вигляді: «не турбувати» вимкнено, Bluetooth підключено
            if (l.Contains("disturb")) return 0;
            if (l.Contains("bluetooth")) return 1;
            if (l.Contains("step")) return l.Contains("progress") ? 84 : 8412;
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

        /// <summary>Зрозуміла назва джерела (ключ рядка src_…), інакше — як є</summary>
        public static string Title(string source) => S.Has("src_" + source) ? S.Get("src_" + source) : source;
        public static bool HasTitle(string source) => S.Has("src_" + source);

        public sealed class Group
        {
            public string Id, Title;
            public List<string> Sources;
        }

        /// <summary>Усі джерела компілятора, згруповані за префіксом.</summary>
        public static List<Group> Groups()
        {
            var unique = FaceCatalog.Sources.Select(x => x.Item1).Distinct().ToList();
            var prefixes = new[] { "time", "date", "health", "weather", "system", "app", "dualtime" };
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
