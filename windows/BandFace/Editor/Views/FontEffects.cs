// SPDX-License-Identifier: MIT
// Ефекти тексту (заливка, обведення, розкладка, тінь) — одна панель для інспектора й вікна «Намалювати шрифтом».

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;

namespace BandFace.Creator
{
    static class FontEffects
    {
        static readonly string[] Suggested = { "#FF9500", "#30B455", "#0A84FF", "#FF375F", "#BF5AF2", "#FFD60A", "#64D2FF", "#FF453A", "#AC8E68", "#8E8E93" };

        /// <summary>Додає елементи керування ефектами; change застосовує правку до генератора (і перемальовує)</summary>
        public static void Build(Action<UIElement> add, Generator g, Action<Action<Generator>> change)
        {
            add(Ui.Header(S.Get("feFill")));
            add(Ui.ColorRow(S.Get("color"), g.Color, h => change(x => x.Color = h)));
            add(Ui.Slider(S.Get("feFillAlpha"), g.FillAlpha, 0, 100, 5, v => change(x => x.FillAlpha = v)));
            // градієнт — лише діагональний, вмикається перемикачем
            bool grad = !string.IsNullOrEmpty(g.Color2);
            add(Ui.Switch(S.Get("gradientKind"), grad, on => change(x =>
            {
                if (!on) { x.Color2 = ""; return; }
                if (string.IsNullOrEmpty(x.Color2)) x.Color2 = Suggested.FirstOrDefault(c => !c.Equals(x.Color, StringComparison.OrdinalIgnoreCase)) ?? "#FF375F";
                x.GradDir = 1;
            })));
            if (grad) add(Ui.ColorRow(S.Get("gradientTo"), g.Color2, h => change(x => { x.Color2 = h; x.GradDir = 1; })));

            add(Ui.Header(S.Get("feOutline")));
            add(Ui.Slider(S.Get("feOutlineW"), g.Outline, 0, 12, 0.5, v => change(x => x.Outline = v)));
            if (g.Outline > 0)
            {
                add(Ui.ColorRow(S.Get("outlineColor"), g.OutlineColor, h => change(x => x.OutlineColor = h)));
                add(Ui.Slider(S.Get("feOutlineAlpha"), g.OutlineAlpha, 0, 100, 5, v => change(x => x.OutlineAlpha = v)));
                add(Ui.Chips(S.Get("feOutlinePos"), new[] { Ui.P("0", S.Get("posOut")), Ui.P("1", S.Get("posMid")), Ui.P("2", S.Get("posIn")) }, g.OutlinePos.ToString(), k => change(x => x.OutlinePos = int.Parse(k))));
            }

            add(Ui.Header(S.Get("feLayout")));
            // для числа — відстань між цифрами (цифри на браслеті — окремі картинки)
            bool digits = g.Kind == GenKind.Digits;
            add(Ui.Slider(S.Get(digits ? "feDigitSpace" : "feTracking"), g.Tracking, -5, 20, digits ? 1 : 0.5, v => change(x => x.Tracking = v)));
            add(Ui.Slider(S.Get("letterWidth"), g.WidthPct, 50, 150, 1, v => change(x => x.WidthPct = v)));

            add(Ui.Header(S.Get("feShadow")));
            add(Ui.Slider(S.Get("shadowX"), g.ShadowX, -8, 8, 1, v => change(x => x.ShadowX = v)));
            add(Ui.Slider(S.Get("shadowY"), g.ShadowY, -8, 8, 1, v => change(x => x.ShadowY = v)));
            if (g.ShadowX != 0 || g.ShadowY != 0)
            {
                add(Ui.ColorRow(S.Get("shadowColor"), g.ShadowColor, h => change(x => x.ShadowColor = h)));
                add(Ui.Slider(S.Get("feShadowAlpha"), g.ShadowAlpha, 0, 100, 5, v => change(x => x.ShadowAlpha = v)));
            }
        }
    }
}
