// SPDX-License-Identifier: MIT
// Елементи інспектора, зібрані в коді: заголовки, рядки, повзунки (зміна записується, коли відпустили),
// числа (колесо миші їх НЕ змінює — воно лише прокручує панель), плитки вибору, перемикачі, вибір кольору з палітрою.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace BandFace.Creator
{
    static class Ui
    {
        static Brush Res(string k) => (Brush)Application.Current.Resources[k];

        // ---------- Меню (однакові в усьому застосунку) ----------

        /// <summary>Пункт меню зі значком (символ Segoe MDL2); danger — червоний (видалення)</summary>
        public static MenuItem MenuAdd(ItemsControl menu, string title, string glyph, Action click, bool danger = false)
        {
            var m = new MenuItem
            {
                Header = title,
                Icon = new TextBlock { Text = glyph, FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 14 },
                Tag = danger ? "danger" : null,
            };
            m.Click += (s, e) => click();
            menu.Items.Add(m);
            return m;
        }

        /// <summary>Нижній рядок меню зі шляхом: дрібно й сіро, задовгий обрізається з початку (кінець видно завжди), повний — у підказці</summary>
        public static void MenuPath(ItemsControl menu, string path, int maxChars = 52)
        {
            if (string.IsNullOrEmpty(path)) return;
            var shown = path.Length <= maxChars ? path : "…" + path.Substring(path.Length - (maxChars - 1));
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 6, 10, 4), ToolTip = path, Focusable = false };
            row.Children.Add(new TextBlock { Text = "\uE707", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 12, Foreground = Res("Sub"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
            row.Children.Add(new TextBlock { Text = shown, FontSize = 11.5, Foreground = Res("Sub"), VerticalAlignment = VerticalAlignment.Center });
            menu.Items.Add(row);
        }

        /// <summary>Меню під елементом, на 4 px нижче; alignRight — по правому краю елемента (для кнопок справа)</summary>
        public static void MenuBelow(ContextMenu menu, FrameworkElement target, bool alignRight = false)
        {
            menu.PlacementTarget = target;
            menu.Placement = PlacementMode.Custom;
            menu.CustomPopupPlacementCallback = (popup, t, off) => new[]
            {
                new CustomPopupPlacement(new Point(alignRight ? t.Width - popup.Width : 0, t.Height + 4), PopupPrimaryAxis.Horizontal),
            };
        }
        static Style St(string k) => (Style)Application.Current.Resources[k];

        public static TextBlock Header(string text) => new TextBlock
        {
            Text = text.ToUpper(CultureInfo.CurrentUICulture), FontSize = 11, FontWeight = FontWeights.SemiBold,
            Foreground = Res("Sub"), Margin = new Thickness(0, 18, 0, 8),
        };

        public static TextBlock Label(string text, double size = 13) => new TextBlock { Text = text, FontSize = size, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };

        public static TextBlock Note(string text) => new TextBlock
        {
            Text = text, FontSize = 12, TextWrapping = TextWrapping.Wrap, Foreground = Res("Sub"), Margin = new Thickness(0, 2, 0, 8),
        };

        /// <summary>Рядок: підпис ліворуч, елемент праворуч</summary>
        public static Grid Row(string label, FrameworkElement control, double controlWidth = 160)
        {
            var g = new Grid { Margin = new Thickness(0, 0, 0, 8) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.Children.Add(Label(label));
            if (controlWidth > 0 && double.IsNaN(control.Width)) control.Width = controlWidth;
            Grid.SetColumn(control, 1);
            g.Children.Add(control);
            return g;
        }

        public static Button Button(string text, Action click, string style = "Btn")
        {
            var b = new Button { Content = text, Style = St(style), Margin = new Thickness(0, 0, 0, 8), HorizontalAlignment = HorizontalAlignment.Stretch };
            b.Click += (s, e) => click();
            return b;
        }

        public static Button Icon(string glyph, string tip, Action click)
        {
            var b = new Button { Content = glyph, Style = St("IconBtn"), ToolTip = tip };
            b.Click += (s, e) => click();
            return b;
        }

        static bool TryInt(string s, out int v) => int.TryParse(s.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out v);

        /// <summary>Ціле число: Enter або вихід з поля — запис. Колесо миші значення не змінює (випадкові зміни під час прокрутки)</summary>
        public static TextBox Number(int value, Action<int> commit, int min = int.MinValue, int max = int.MaxValue)
        {
            var t = new TextBox { Text = value.ToString(CultureInfo.InvariantCulture), HorizontalContentAlignment = HorizontalAlignment.Right };
            int current = value;
            void Commit()
            {
                if (TryInt(t.Text, out var v))
                {
                    v = Math.Max(min, Math.Min(max, v));
                    if (v != current) { current = v; commit(v); }
                    else t.Text = v.ToString(CultureInfo.InvariantCulture);
                }
                else t.Text = current.ToString(CultureInfo.InvariantCulture);
            }
            t.KeyDown += (s, e) => { if (e.Key == Key.Enter) { Commit(); e.Handled = true; } };
            t.LostKeyboardFocus += (s, e) => Commit();
            return t;
        }

        public static FrameworkElement NumberRow(string label, int value, Action<int> commit, int min = int.MinValue, int max = int.MaxValue)
            => Row(label, Number(value, commit, min, max), 90);

        /// <summary>Повзунок із полем: значення записується, коли відпустили повзунок (одна зміна в історії)</summary>
        public static FrameworkElement Slider(string label, double value, double min, double max, double step, Action<double> commit)
        {
            var root = new StackPanel { Margin = new Thickness(0, 0, 0, 10) };
            var top = new Grid();
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            top.Children.Add(Label(label));
            var box = new TextBox { Width = 64, Height = 26, Text = Fmt(value), HorizontalContentAlignment = HorizontalAlignment.Right };
            Grid.SetColumn(box, 1);
            top.Children.Add(box);
            root.Children.Add(top);
            var sl = new Slider
            {
                Minimum = min, Maximum = max, Value = Math.Max(min, Math.Min(max, value)), SmallChange = step, LargeChange = step * 10,
                TickFrequency = step, IsSnapToTickEnabled = true, IsMoveToPointEnabled = true, Margin = new Thickness(0, 4, 0, 0),
            };
            root.Children.Add(sl);
            double committed = value;
            void Commit(double v)
            {
                v = Math.Max(min, Math.Min(max, Math.Round(v / step) * step));
                if (Math.Abs(v - committed) < 1e-9) return;
                committed = v;
                commit(v);
            }
            sl.ValueChanged += (s, e) => box.Text = Fmt(sl.Value);
            sl.PreviewMouseLeftButtonUp += (s, e) => Commit(sl.Value);
            sl.AddHandler(Thumb.DragCompletedEvent, new DragCompletedEventHandler((s, e) => Commit(sl.Value)));
            sl.KeyUp += (s, e) => Commit(sl.Value);
            box.KeyDown += (s, e) =>
            {
                if (e.Key != Key.Enter) return;
                if (double.TryParse(box.Text.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var v)) { sl.Value = v; Commit(v); }
                e.Handled = true;
            };
            box.LostKeyboardFocus += (s, e) =>
            {
                if (double.TryParse(box.Text.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var v)) { sl.Value = v; Commit(v); }
                else box.Text = Fmt(committed);
            };
            return root;
        }

        static string Fmt(double v) => Math.Abs(v - Math.Round(v)) < 1e-9 ? ((int)Math.Round(v)).ToString(CultureInfo.InvariantCulture) : v.ToString("0.#", CultureInfo.InvariantCulture);

        /// <summary>Плитки вибору одного значення</summary>
        public static FrameworkElement Chips(string label, IEnumerable<KeyValuePair<string, string>> items, string selected, Action<string> pick, int columns = 0)
        {
            var root = new StackPanel { Margin = new Thickness(0, 0, 0, 10) };
            if (!string.IsNullOrEmpty(label)) root.Children.Add(new TextBlock { Text = label, FontSize = 13, Margin = new Thickness(0, 0, 0, 6) });
            var list = items.ToList();
            int cols = columns > 0 ? columns : list.Count;
            var g = new UniformGrid { Columns = cols, Rows = (list.Count + cols - 1) / cols };
            foreach (var kv in list)
            {
                var t = new ToggleButton { Content = kv.Value, Style = St("Chip"), IsChecked = kv.Key == selected, Margin = new Thickness(0, 0, 4, g.Rows > 1 ? 4 : 0) };
                var key = kv.Key;
                t.Click += (s, e) => { t.IsChecked = true; if (key != selected) pick(key); };
                g.Children.Add(t);
            }
            root.Children.Add(g);
            return root;
        }

        public static KeyValuePair<string, string> P(string k, string v) => new KeyValuePair<string, string>(k, v);

        public static FrameworkElement Switch(string label, bool value, Action<bool> change, bool enabled = true)
        {
            var c = new CheckBox { Style = St("Switch"), IsChecked = value, IsEnabled = enabled, VerticalAlignment = VerticalAlignment.Center };
            c.Click += (s, e) => change(c.IsChecked == true);
            var row = Row(label, c, 0);
            if (!enabled) row.Opacity = 0.6;
            return row;
        }

        public static ComboBox Combo(IEnumerable<KeyValuePair<string, string>> items, string selected, Action<string> pick)
        {
            var cb = new ComboBox { MaxDropDownHeight = 420 };
            foreach (var kv in items)
            {
                var it = new ComboBoxItem { Content = kv.Value, Tag = kv.Key };
                cb.Items.Add(it);
                if (kv.Key == selected) cb.SelectedItem = it;
            }
            cb.SelectionChanged += (s, e) =>
            {
                if (cb.SelectedItem is ComboBoxItem it && (string)it.Tag != selected) pick((string)it.Tag);
            };
            return cb;
        }

        // MARK: Колір

        public static readonly string[] Palette =
        {
            "#FFFFFF", "#D1D1D6", "#8E8E93", "#3A3A3C", "#000000", "#FF3B30", "#FF9500", "#FFCC00",
            "#34C759", "#30B455", "#00C7BE", "#4DE1FF", "#0A84FF", "#5856D6", "#BF5AF2", "#FF2D55",
            "#AC8E68", "#FFD60A", "#64D2FF", "#FF453A",
        };

        /// <summary>Колір: зразок (палітра в спливному вікні, «Інший…» — системний вибір) і поле #RRGGBB</summary>
        public static FrameworkElement ColorRow(string label, string hex, Action<string> commit)
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            var swatch = new Button { Width = 32, Height = 32, Style = St("Btn"), Padding = new Thickness(0), Background = Imaging.Brush(hex), ToolTip = label };
            var box = new TextBox { Width = 92, Text = hex.ToUpperInvariant(), Margin = new Thickness(8, 0, 0, 0), FontFamily = new FontFamily("Consolas") };
            panel.Children.Add(swatch);
            panel.Children.Add(box);
            string current = hex.ToUpperInvariant();
            void Set(string h)
            {
                var n = ColorVariants.Normalize(h);
                if (n.Length == 0) { box.Text = current; return; }
                box.Text = n; swatch.Background = Imaging.Brush(n);
                if (n != current) { current = n; commit(n); }
            }
            box.KeyDown += (s, e) => { if (e.Key == Key.Enter) { Set(box.Text); e.Handled = true; } };
            box.LostKeyboardFocus += (s, e) => Set(box.Text);
            swatch.Click += (s, e) =>
            {
                var pop = new Popup { PlacementTarget = swatch, Placement = PlacementMode.Bottom, StaysOpen = false, AllowsTransparency = true };
                var grid = new UniformGrid { Columns = 5, Margin = new Thickness(0, 0, 0, 8) };
                foreach (var c in Palette)
                {
                    var b = new Button { Width = 30, Height = 30, Margin = new Thickness(3), Style = St("Btn"), Padding = new Thickness(0), Background = Imaging.Brush(c), ToolTip = c };
                    var cc = c;
                    b.Click += (s2, e2) => { pop.IsOpen = false; Set(cc); };
                    grid.Children.Add(b);
                }
                var other = new Button { Content = S.Get("otherColor"), Style = St("Btn") };
                other.Click += (s2, e2) =>
                {
                    pop.IsOpen = false;
                    var c = Imaging.ParseColor(current);
                    using (var dlg = new System.Windows.Forms.ColorDialog { FullOpen = true, Color = System.Drawing.Color.FromArgb(c.R, c.G, c.B) })
                        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                            Set("#" + dlg.Color.R.ToString("X2") + dlg.Color.G.ToString("X2") + dlg.Color.B.ToString("X2"));
                };
                var sp = new StackPanel();
                sp.Children.Add(grid);
                sp.Children.Add(other);
                pop.Child = new Border { Background = Res("Card"), BorderBrush = Res("CardBorder"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Padding = new Thickness(8), Child = sp };
                pop.IsOpen = true;
            };
            return Row(label, panel, 0);
        }

        public static Border Separator() => new Border { Height = 1, Background = Res("CardBorder"), Margin = new Thickness(0, 8, 0, 4) };
    }
}
