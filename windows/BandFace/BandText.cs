// SPDX-License-Identifier: MIT
// Текст для екрана пристрою. Шрифт пристрою не має кольорових смайлів: замість них — квадратики.
// Перевірено на Mi Band 10: показуються ♥ (U+2665) і ★ (U+2605); ❤ ❤️ ☺ ✔ ✅ ⭐ і всі смайли поза BMP — ні.
// Тому знайомі смайли замінюємо на те, що пристрій уміє показати, а решту прибираємо.

using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace BandFace
{
    static class BandText
    {
        static readonly Dictionary<int, string> map = new Dictionary<int, string>();

        static void Set(string to, params int[] cps) { foreach (var c in cps) map[c] = to; }

        static BandText()
        {
            // серця
            Set("♥", 0x2764, 0x2763, 0x1F493, 0x1F494, 0x1F495, 0x1F496, 0x1F497, 0x1F498, 0x1F499, 0x1F49A, 0x1F49B, 0x1F49C,
                0x1F49D, 0x1F49E, 0x1F49F, 0x1F5A4, 0x1F90D, 0x1F90E, 0x1F9E1, 0x1FA75, 0x1FA76, 0x1FA77, 0x1F60D, 0x1F970, 0x1F618, 0x1F63B);
            // зірки
            Set("★", 0x2B50, 0x1F31F, 0x2728, 0x1F320, 0x2734, 0x2733);
            // усмішки
            Set(":)", 0x263A, 0x1F600, 0x1F603, 0x1F604, 0x1F601, 0x1F60A, 0x1F642, 0x1F609, 0x1F60B, 0x1F60E, 0x1F917, 0x1F607, 0x1F60C, 0x1F643);
            Set(":D", 0x1F602, 0x1F923, 0x1F606, 0x1F605, 0x1F639);
            Set(":(", 0x2639, 0x1F641, 0x1F622, 0x1F62D, 0x1F61E, 0x1F614, 0x1F61F, 0x1F625, 0x1F97A);
            Set(";)", 0x1F61C, 0x1F61D, 0x1F61B);
            Set("+", 0x1F44D);
        }

        /// <summary>Чи покаже пристрій символ поза звичайним текстом</summary>
        static bool Unsupported(int cp) =>
            cp > 0xFFFF                                   // усе поза BMP — смайли
            || cp == 0x200D || cp == 0xFE0F || cp == 0xFE0E || cp == 0x20E3 // склейки й варіанти
            || (cp >= 0x2300 && cp <= 0x23FF)
            || (cp >= 0x2600 && cp <= 0x27BF && cp != 0x2665 && cp != 0x2605)
            || (cp >= 0x2B00 && cp <= 0x2BFF);

        public static string Clean(string s)
        {
            if (string.IsNullOrEmpty(s)) return s ?? "";
            var sb = new StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                int cp = char.IsSurrogatePair(s, i) ? char.ConvertToUtf32(s, i) : s[i];
                if (cp > 0xFFFF) i++;
                if (map.TryGetValue(cp, out var to))
                {
                    // «:)» не зліплюємо з сусіднім словом
                    if (to.Length > 1 && sb.Length > 0 && !char.IsWhiteSpace(sb[sb.Length - 1])) sb.Append(' ');
                    sb.Append(to);
                }
                else if (!Unsupported(cp)) sb.Append(char.ConvertFromUtf32(cp));
            }
            // після прибирання — без подвійних пробілів і пробілів у кінці рядків
            var r = Regex.Replace(sb.ToString(), @"[ \t]{2,}", " ");
            r = Regex.Replace(r, @"[ \t]+(\r?\n)", "$1");
            return r.Trim();
        }
    }
}
