using System;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
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

        public static void Attach(Window w) { }

        /// <summary>Для всіх вікон застосунку одразу (діалоги «Що показувати», галерея тощо)</summary>
        public static void AttachAll() =>
            EventManager.RegisterClassHandler(typeof(Window), UIElement.PreviewMouseWheelEvent, new MouseWheelEventHandler(OnWheel));

        static void OnWheel(object sender, MouseWheelEventArgs e)
        {
            if (Keyboard.Modifiers != ModifierKeys.None) return;
            var sv = Find(e.OriginalSource as DependencyObject, e.Delta);
            if (sv == null) return;
            var st = States.GetOrCreateValue(sv);
            // списки, що гортаються цілими пунктами (шари, зображення, галереї), переводимо на пікселі — плавно, як решта
            if (ItemUnits(sv) && ScrollInfo(sv) is VirtualizingPanel vp && ItemsControl.GetItemsOwner(vp) is ItemsControl owner)
            {
                VirtualizingPanel.SetScrollUnit(owner, ScrollUnit.Pixel);
                sv.UpdateLayout();   // зміщення одразу в пікселях — далі рахуємо від нього
                st.Running = false;
            }
            if (!st.Running) st.Target = sv.VerticalOffset;
            // у пунктах (якщо не вдалося перевести) — ~1,5 пункту на клацання; у пікселях (і XML-редактор) — 56 px
            double step = ItemUnits(sv) ? 1.5 : Step;
            st.Target = Math.Max(0, Math.Min(sv.ScrollableHeight, st.Target - e.Delta / 120.0 * step));
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

        /// <summary>Прокрутка в пунктах, а не в пікселях: лише віртуалізовані списки з ScrollUnit=Item і StackPanel
        /// з логічною прокруткою. Інші IScrollInfo (текст XML-редактора AvalonEdit) рахують у пікселях — раніше їм
        /// діставалося 1,5 «пункту» = 1,5 px на клацання, звідси повільна прокрутка</summary>
        static bool ItemUnits(ScrollViewer sv)
        {
            if (!sv.CanContentScroll) return false;
            var info = ScrollInfo(sv);
            if (info is VirtualizingPanel vp)
            {
                var owner = ItemsControl.GetItemsOwner(vp);
                return owner == null || VirtualizingPanel.GetScrollUnit(owner) == ScrollUnit.Item;
            }
            return info is StackPanel;
        }

        /// <summary>Хто прокручує вміст ScrollViewer (ScrollViewer.ScrollInfo — внутрішня властивість): перший IScrollInfo
        /// у шаблоні, чий ScrollOwner — цей ScrollViewer (панель списку або ScrollContentPresenter)</summary>
        static IScrollInfo ScrollInfo(ScrollViewer sv)
        {
            var queue = new System.Collections.Generic.Queue<DependencyObject>();
            queue.Enqueue(sv);
            for (int n = 0; queue.Count > 0 && n < 200; n++)
            {
                var d = queue.Dequeue();
                for (int i = 0; i < VisualTreeHelper.GetChildrenCount(d); i++)
                {
                    var c = VisualTreeHelper.GetChild(d, i);
                    if (c is IScrollInfo si && si.ScrollOwner == sv) return si;
                    if (!(c is ScrollViewer)) queue.Enqueue(c);
                }
            }
            return null;
        }

        /// <summary>Найближчий ScrollViewer угору по дереву, що може прокрутитися в бік delta.</summary>
        static ScrollViewer Find(DependencyObject d, int delta)
        {
            while (d != null)
            {
                // багаторядкові поля прокручуються самі; однорядкові (числа) коліщатко не змінює — прокручуємо панель
                if (d is TextBox tb && tb.AcceptsReturn) return null;
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
