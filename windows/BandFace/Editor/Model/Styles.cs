// SPDX-License-Identifier: MIT
// Стилі циферблата: кожен стиль — тема (екран), за якою може йти її власний «Завжди на екрані» (тема type="AOD").
// Порядок тем у файлі: стиль 1, [AOD стилю 1], стиль 2, [AOD стилю 2]… — так його читають браслет, Studio й BandFace.

using System.Collections.Generic;
using System.Linq;
using BandFace.Faces;

namespace BandFace.Creator
{
    static class Styles
    {
        /// <summary>Старі файли без типів тем: дві теми — основна й AOD</summary>
        static bool LegacyAod(FaceProject p)
        {
            var t = p.Themes;
            return t.Count == 2 && t.All(x => !x.Has("type"));
        }

        /// <summary>Тема — «Завжди на екрані» якогось стилю</summary>
        public static bool IsAod(this FaceProject p, int i)
        {
            var t = p.Theme(i);
            if (i <= 0 || t == null) return false;
            return t.Str("type") == "AOD" || (LegacyAod(p) && i == 1);
        }

        /// <summary>Номери тем-стилів (без AOD) у порядку файла</summary>
        public static List<int> StyleThemes(this FaceProject p) =>
            Enumerable.Range(0, p.Themes.Count).Where(i => !p.IsAod(i)).ToList();

        public static List<int> AodThemes(this FaceProject p) =>
            Enumerable.Range(0, p.Themes.Count).Where(i => p.IsAod(i)).ToList();

        /// <summary>AOD стилю (тема одразу за ним) або -1</summary>
        public static int AodOf(this FaceProject p, int style) => p.IsAod(style + 1) ? style + 1 : -1;

        /// <summary>Стиль, до якого належить тема (для AOD — стиль перед ним)</summary>
        public static int StyleOf(this FaceProject p, int i)
        {
            while (i > 0 && p.IsAod(i)) i--;
            return i;
        }

        /// <summary>Номер стилю для людей: 1, 2, 3…</summary>
        public static int StyleNumber(this FaceProject p, int i) => p.StyleThemes().IndexOf(p.StyleOf(i)) + 1;

        /// <summary>«Стиль 2 · Спорт»</summary>
        public static string StyleTitle(this FaceProject p, int s)
        {
            var n = S.Get("styleN", p.StyleNumber(s));
            var name = p.Theme(s)?.Str("name") ?? "";
            return name.Length == 0 ? n : n + " · " + name;
        }

        /// <summary>Новий стиль у кінці. copyOf — копія шарів і кольору фону: шари посилаються на ті самі ресурси,
        /// тож жодна картинка не дублюється. Повертає номер нової теми.</summary>
        public static int AddStyle(FaceProject p, int copyOf)
        {
            XNode t;
            var src = copyOf >= 0 ? p.Theme(copyOf) : null;
            if (src != null)
            {
                t = src.Copy();
                t.Remove("preview");   // превʼю для браслета малюється заново під час збирання
            }
            else
            {
                t = new XNode("Theme");
                t.Set("bgColor", p.Theme(0)?.Str("bgColor") ?? "#000000");
            }
            t.Set("type", "normal").Set("name", "");
            int last = p.Root.Kids.FindLastIndex(k => k.Tag == "Theme");
            p.Root.Kids.Insert(last < 0 ? p.Root.Kids.Count : last + 1, t);
            return p.Themes.Count - 1;
        }

        /// <summary>«Завжди на екрані» для стилю — одразу після нього; спершу лише цифри часу стилю (ті самі ресурси)</summary>
        public static int AddAod(FaceProject p, int style)
        {
            int a = p.AodOf(style);
            if (a >= 0) return a;
            var st = p.Theme(style);
            if (st == null) return style;
            XNode t;
            int src = AodSource(p, style);
            if (src >= 0 && p.Theme(src) != null)
            {
                // AOD стилю, з якого цей скопійовано (або першого) — повна копія: усі шари, фон, приглушення; ті самі ресурси
                t = p.Theme(src).Copy();
                t.Remove("preview");
                t.Set("type", "AOD").Set("name", "");
            }
            else
            {
                // AOD ще ніде немає — як перший: лише цифри часу стилю
                t = new XNode("Theme");
                t.Set("type", "AOD").Set("name", "").Set("bgColor", "#000000");
                foreach (var l in p.Layouts(style)) if (Elements.Of(p.ElementOf(l)) == ElementKind.Digits) t.Kids.Add(l.Copy());
            }
            p.Root.Kids.Insert(p.Root.Kids.IndexOf(st) + 1, t);
            return style + 1;
        }

        /// <summary>AOD для копіювання: інший стиль з AOD і найбільшою кількістю спільних шарів, інакше AOD першого стилю; -1 — AOD ще ніде немає</summary>
        static int AodSource(FaceProject p, int style)
        {
            var mine = new HashSet<string>(p.Layouts(style).Select(l => l.Str("ref")).Where(r => r != null));
            int best = -1, bestShared = 0;
            foreach (int o in p.StyleThemes())
            {
                if (o == style) continue;
                int a = p.AodOf(o);
                if (a < 0) continue;
                int shared = p.Layouts(o).Count(l => l.Str("ref") != null && mine.Contains(l.Str("ref")));
                if (best < 0 || shared > bestShared) { best = a; bestShared = shared; }
            }
            if (best >= 0 && bestShared > 0) return best;
            var styles = p.StyleThemes();
            return styles.Count > 0 ? p.AodOf(styles[0]) : -1;
        }

        /// <summary>Видаляє стиль разом з його AOD (останній стиль лишається завжди)</summary>
        public static void DeleteStyle(FaceProject p, int style)
        {
            if (p.StyleThemes().Count < 2 || p.IsAod(style)) return;
            int a = p.AodOf(style);
            if (a >= 0) ElementFactory.DeleteTheme(p, a);
            ElementFactory.DeleteTheme(p, style);
        }
    }
}
