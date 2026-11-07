using System;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace BandFace
{
    /// <summary>
    /// Плавна прокрутка коліщатком, як у застосунках Windows 11: ~56 px на клацання замість трьох «рядків»,
    /// з плавним доїжджанням. Працює для найближчого ScrollViewer під мишею, який ще може прокручуватися
    /// в цьому напрямку; Ctrl+коліщатко лишається масштабу редактора.
    /// </summary>
    static class SmoothScroll
    {
        const double Step = 56;

        sealed class State { public double Target; public bool Running; }
        static readonly ConditionalWeakTable<ScrollViewer, State> States = new ConditionalWeakTable<ScrollViewer, State>();

        public static void Attach(Window w) => w.PreviewMouseWheel += OnWheel;

        static void OnWheel(object sender, MouseWheelEventArgs e)
        {
            if (Keyboard.Modifiers != ModifierKeys.None) return;
            var sv = Find(e.OriginalSource as DependencyObject, e.Delta);
            if (sv == null) return;
            var st = States.GetOrCreateValue(sv);
            if (!st.Running) st.Target = sv.VerticalOffset;
            st.Target = Math.Max(0, Math.Min(sv.ScrollableHeight, st.Target - e.Delta / 120.0 * Step));
            e.Handled = true;
            if (st.Running) return;
            st.Running = true;
            EventHandler tick = null;
            tick = (s, a) =>
            {
                double d = st.Target - sv.VerticalOffset;
                if (Math.Abs(d) < 0.5 || !sv.IsVisible)
                {
                    sv.ScrollToVerticalOffset(st.Target);
                    st.Running = false;
                    CompositionTarget.Rendering -= tick;
                    return;
                }
                sv.ScrollToVerticalOffset(sv.VerticalOffset + d * 0.25);
            };
            CompositionTarget.Rendering += tick;
        }

        /// <summary>Найближчий ScrollViewer угору по дереву, що може прокрутитися в бік delta.</summary>
        static ScrollViewer Find(DependencyObject d, int delta)
        {
            while (d != null)
            {
                // поля введення обробляють коліщатко самі: числові поля редактора ним змінюють значення,
                // XML-редактор прокручується своїм ScrollViewer
                if (d is TextBox) return null;
                if (d is ScrollViewer sv && sv.ScrollableHeight > 0)
                {
                    bool canUp = sv.VerticalOffset > 0, canDown = sv.VerticalOffset < sv.ScrollableHeight;
                    if ((delta > 0 && canUp) || (delta < 0 && canDown)) return sv;
                }
                d = d is Visual || d is System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d);
            }
            return null;
        }
    }
}
