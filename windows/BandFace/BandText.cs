// SPDX-License-Identifier: MIT
// Текст для екрана пристрою. Шрифт пристрою не має кольорових смайлів: замість них — квадратики.
// Перевірено на Mi Band 10: звичайні коди смайлів не показуються (квадратики), з простих символів є ♥ (U+2665) і ★ (U+2605).
// Свої кольорові смайли пристрій малює за власними кодами U+A002…U+A064 — на них і замінюємо.
// Що не має такого коду — замінюємо на ♥ ★ :) або прибираємо.

using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace BandFace
{
    static class BandText
    {
        /// <summary>Кольорові смайли пристрою: він малює їх картинками, якщо замість смайла прийшов його власний код (U+A002…U+A064).
        /// Пари «смайл, код пристрою» — дані про пристрій (з відкритого опису протоколу).</summary>
        static readonly int[] deviceEmoji =
        {
            0x1F60D, 0xA002, 0x1F618, 0xA003, 0x1F602, 0xA004, 0x1F60A, 0xA005, 0x1F60E, 0xA006, 0x1F609, 0xA007,
            0x1F48B, 0xA008, 0x1F44D, 0xA009, 0x1F923, 0xA00A, 0x1F495, 0xA00B, 0x1F600, 0xA00C, 0x1F604, 0xA00D,
            0x1F62D, 0xA00E, 0x1F97A, 0xA00F, 0x1F64F, 0xA011, 0x1F970, 0xA012, 0x1F914, 0xA013, 0x1F525, 0xA014,
            0x1F629, 0xA017, 0x1F614, 0xA018, 0x1F601, 0xA019, 0x1F44C, 0xA01A, 0x1F60F, 0xA01B, 0x1F605, 0xA01C,
            0x1F90D, 0xA01D, 0x1F494, 0xA01E, 0x1F60C, 0xA01F, 0x1F622, 0xA020, 0x1F499, 0xA021, 0x1F49C, 0xA022,
            0x1F3B6, 0xA024, 0x1F633, 0xA025, 0x1F496, 0xA026, 0x1F64C, 0xA027, 0x1F4AF, 0xA028, 0x1F648, 0xA029,
            0x1F60B, 0xA02B, 0x1F611, 0xA02C, 0x1F634, 0xA02D, 0x1F62A, 0xA02E, 0x1F61C, 0xA02F, 0x1F61B, 0xA030,
            0x1F61D, 0xA031, 0x1F61E, 0xA032, 0x1F615, 0xA033, 0x1F497, 0xA034, 0x1F44F, 0xA035, 0x1F610, 0xA036,
            0x1F449, 0xA037, 0x1F49B, 0xA038, 0x1F49E, 0xA039, 0x1F4AA, 0xA03A, 0x1F339, 0xA03B, 0x1F480, 0xA03C,
            0x1F631, 0xA03D, 0x1F498, 0xA03E, 0x1F91F, 0xA03F, 0x1F621, 0xA040, 0x1F4F7, 0xA041, 0x1F338, 0xA042,
            0x1F608, 0xA043, 0x1F448, 0xA044, 0x1F389, 0xA045, 0x1F481, 0xA046, 0x1F64A, 0xA047, 0x1F49A, 0xA048,
            0x1F62B, 0xA049, 0x1F624, 0xA04A, 0x1F493, 0xA04D, 0x1F31A, 0xA04E, 0x1F447, 0xA04F, 0x1F607, 0xA052,
            0x1F44A, 0xA053, 0x1F451, 0xA054, 0x1F613, 0xA055, 0x1F63B, 0xA056, 0x1F534, 0xA057, 0x1F625, 0xA058,
            0x1F929, 0xA059, 0x1F61A, 0xA05A, 0x1F637, 0xA05C, 0x1F44B, 0xA05D, 0x1F4A5, 0xA05E, 0x1F92D, 0xA060,
            0x1F31F, 0xA061, 0x1F971, 0xA062, 0x1F4A9, 0xA063, 0x1F680, 0xA064,
            // «дірки» таблиці, перевірено на Mi Band 10 (тест 0.1.50): ✨ ✔ ♻ ⬅ ✌ ✋ ✅ ☀ ➡ ⚡ ⭐
            0x2728, 0xA010, 0x2714, 0xA015, 0x267B, 0xA016, 0x2B05, 0xA023, 0x270C, 0xA02A, 0x270B, 0xA04B,
            0x2705, 0xA04C, 0x2600, 0xA050, 0x27A1, 0xA051, 0x26A1, 0xA05B, 0x2B50, 0xA05F,
        };

        static readonly Dictionary<int, string> map = new Dictionary<int, string>();

        static void Set(string to, params int[] cps) { foreach (var c in cps) if (!map.ContainsKey(c)) map[c] = to; }

        static BandText()
        {
            for (int i = 0; i + 1 < deviceEmoji.Length; i += 2) map[deviceEmoji[i]] = char.ConvertFromUtf32(deviceEmoji[i + 1]);
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
