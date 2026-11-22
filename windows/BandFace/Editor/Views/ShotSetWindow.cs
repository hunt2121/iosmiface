// SPDX-License-Identifier: MIT
// «Набір знімків»: ліворуч — готова картинка, праворуч — екрани (кожен — свій стиль, колір, AOD, стани) і оформлення.
// Клік по екрану — меню (назва, стиль, колір, AOD, дублювати, прибрати); «Додати» — меню стилів і їхніх кольорів.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Microsoft.Win32;

namespace BandFace.Creator
{
    sealed class ShotSetWindow : Window
    {
        readonly FaceProject p;
        readonly ShotSet s;
        readonly Image preview = new Image { Stretch = Stretch.Uniform };
        readonly TextBlock sizeText = new TextBlock { FontSize = 12, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
        readonly StackPanel panel = new StackPanel { Margin = new Thickness(0, 0, 16, 16) };
        readonly ScrollViewer scroll;
        readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        readonly Dictionary<string, BitmapSource> thumbs = new Dictionary<string, BitmapSource>();
        BitmapSource image;

        List<int> Styles => p.StyleThemes();
        List<string> ColorsList => ColorVariants.IsEnabled(p) ? ColorVariants.Colors(p) : new List<string>();

        ShotSetWindow(FaceProject project, ShotSet set)
        {
            p = project; s = set;
            Title = S.Get("shotSet");
            Width = 1100; Height = 760; MinWidth = 900; MinHeight = 560;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Segoe UI");
            SetResourceReference(BackgroundProperty, "Bg");
            SetResourceReference(ForegroundProperty, "Text");

            var root = new Grid { Margin = new Thickness(16) };
            root.ColumnDefinitions.Add(new ColumnDefinition());
            root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(440) });
            root.RowDefinitions.Add(new RowDefinition());
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var left = new DockPanel { Margin = new Thickness(0, 0, 16, 0) };
            DockPanel.SetDock(sizeText, Dock.Bottom);
            sizeText.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            left.Children.Add(sizeText);
            var frame = new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(12), Child = preview, Cursor = System.Windows.Input.Cursors.Hand, ToolTip = S.Get("shotZoom") };
            frame.MouseLeftButtonUp += (o, e) => { if (image != null) ShowZoom(); };
            frame.SetResourceReference(Border.BackgroundProperty, "Card");
            left.Children.Add(frame);
            root.Children.Add(left);

            scroll = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            Grid.SetColumn(scroll, 1);
            root.Children.Add(scroll);

            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
            buttons.Children.Add(Ui.Button(S.Get("shotCopy"), Copy));
            var save = Ui.Button(S.Get("shotSavePng"), Save, "PrimaryBtn");
            save.Margin = new Thickness(8, 0, 0, 0);
            buttons.Children.Add(save);
            Grid.SetRow(buttons, 1); Grid.SetColumnSpan(buttons, 2);
            root.Children.Add(buttons);
            Content = root;

            timer.Tick += (o, e) => { timer.Stop(); Recompose(); };
            Closed += (o, e) => { p.Meta.Shots = s.Remember ? s : null; p.Save(); };
            SourceInitialized += (o, e) => Theme.Apply(this);
            Loaded += (o, e) => { Theme.Apply(this); Rebuild(); Recompose(); };
        }

        /// <summary>Набір: запам'ятований для циферблата або поточний стиль у поточному кольорі</summary>
        public static void Open(Window owner, FaceProject p, int theme, int variant)
        {
            ShotSet set = null;
            if (p.Meta.Shots != null)
            {
                set = p.Meta.Shots.Copy();
                int n = p.StyleThemes().Count, c = ColorVariants.IsEnabled(p) ? ColorVariants.Colors(p).Count : 1;
                set.Screens = set.Screens.Where(x => x.Style < n && x.Color < c).ToList();
                if (set.Screens.Count == 0) set = null;
            }
            if (set == null) set = ShotSet.Start(Math.Max(0, p.StyleThemes().IndexOf(p.StyleOf(theme))), variant, p.IsAod(theme));
            new ShotSetWindow(p, set) { Owner = owner }.ShowDialog();
        }

        void Changed() { Rebuild(); timer.Stop(); timer.Start(); }

        void Recompose()
        {
            image = ShotComposer.Compose(p, s);
            preview.Source = image;
            sizeText.Text = image == null ? "" : $"{image.PixelWidth} × {image.PixelHeight}";
        }

        // ---------- Панель ----------

        void Rebuild()
        {
            double off = scroll.VerticalOffset;
            panel.Children.Clear();
            ScreensBlock();
            FormatBlock();
            ScreenLookBlock();
            BackgroundBlock();
            TextBlockSection();
            LookBlock();
            panel.Children.Add(Ui.Header(S.Get("shotSaving")));
            panel.Children.Add(Ui.Switch(S.Get("shotRemember"), s.Remember, v => { s.Remember = v; Changed(); }));
            panel.Children.Add(Ui.Note(S.Get("shotRememberNote")));
            Dispatcher.BeginInvoke(new Action(() => scroll.ScrollToVerticalOffset(off)), DispatcherPriority.Loaded);
        }

        void ScreensBlock()
        {
            panel.Children.Add(Ui.Header(S.Get("shotScreensN", s.Count)));

            var wrap = new WrapPanel();
            foreach (var sc in s.Screens) wrap.Children.Add(Card(sc));
            wrap.Children.Add(AddCard());
            panel.Children.Add(wrap);
            panel.Children.Add(Ui.Note(S.Get("shotScreensNote")));
        }

        BitmapSource Thumb(ShotScreen sc)
        {
            var t = ShotComposer.Theme(p, sc);
            int st = sc.Bluetooth ? 1 : sc.Battery ? 2 : 0;
            var key = t + "-" + sc.Color + "-" + st + "-" + string.Join(",", sc.Widgets.OrderBy(kv => kv.Key).Select(kv => kv.Key + "=" + kv.Value));
            if (thumbs.TryGetValue(key, out var b)) return b;
            var r = new FaceRenderer(p) { ColorVariant = sc.Color, SlotChoice = sc.Widgets, BluetoothOff = st == 1, LowBattery = st == 2 };
            return thumbs[key] = r.Render(t, 1).Image;
        }

        static Brush Res(string k) => (Brush)Application.Current.Resources[k];

        FrameworkElement Capsule(BitmapSource img, bool dashed)
        {
            if (dashed)
            {
                var g = new Grid { Width = 58, Height = 135 };
                g.Children.Add(new Rectangle { RadiusX = 29, RadiusY = 29, StrokeThickness = 2, StrokeDashArray = new DoubleCollection { 3, 2 }, Stroke = Res("Sub") });
                g.Children.Add(new TextBlock { Text = "", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 20, Foreground = Res("Accent"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
                return g;
            }
            var inner = new Border { Width = 53, Height = 130, CornerRadius = new CornerRadius(26.5), Background = Brushes.Black, ClipToBounds = true };
            var im = new Image { Source = img, Stretch = Stretch.UniformToFill };
            RenderOptions.SetBitmapScalingMode(im, BitmapScalingMode.HighQuality);
            inner.Child = im;
            inner.Clip = new RectangleGeometry(new Rect(0, 0, 53, 130), 26.5, 26.5);
            return new Border { CornerRadius = new CornerRadius(29), Padding = new Thickness(2.5), Background = Res("Accent"), Child = inner };
        }

        FrameworkElement Card(ShotScreen sc)
        {
            var col = new StackPanel { Width = 96, Margin = new Thickness(0, 0, 4, 14) };
            var btn = new Button { Content = Capsule(Thumb(sc), false), Background = Brushes.Transparent, BorderThickness = new Thickness(0), Padding = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Center, ToolTip = ShotComposer.Name(p, sc) };
            btn.Click += (o, e) => { var m = CardMenu(sc); Ui.MenuBelow(m, btn); m.IsOpen = true; };
            col.Children.Add(btn);
            col.Children.Add(new TextBlock { Text = ShotComposer.Name(p, sc), FontSize = 12, FontWeight = FontWeights.Medium, TextTrimming = TextTrimming.CharacterEllipsis, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) });
            var line = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Height = 14, Margin = new Thickness(0, 3, 0, 0) };
            var cs = ColorsList;
            if (cs.Count > 0) line.Children.Add(new Ellipse { Width = 11, Height = 11, Fill = Imaging.Brush(cs[Math.Min(sc.Color, cs.Count - 1)]), VerticalAlignment = VerticalAlignment.Center });
            if (sc.Aod)
            {
                var tag = new Border { CornerRadius = new CornerRadius(3), Padding = new Thickness(4, 0, 4, 0), Margin = new Thickness(5, 0, 0, 0), Child = new TextBlock { Text = "AOD", FontSize = 9, FontWeight = FontWeights.Bold } };
                tag.SetResourceReference(Border.BackgroundProperty, "NavSel");
                line.Children.Add(tag);
            }
            col.Children.Add(line);
            bool bt = p.UsesSource("bluetooth"), bat = p.UsesSource("battery");
            if (bt || bat)
            {
                var chips = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
                if (bt) chips.Children.Add(Chip(1, sc.Bluetooth, S.Get("shotBtOff"), v => { sc.Bluetooth = v; Changed(); }));
                if (bat) chips.Children.Add(Chip(2, sc.Battery, S.Get("shotLowBattery"), v => { sc.Battery = v; Changed(); }));
                col.Children.Add(chips);
            }
            return col;
        }

        FrameworkElement Chip(int state, bool on, string tip, Action<bool> set)
        {
            var fg = on ? Brushes.White : (Brush)Application.Current.Resources["Text"];
            var t = new ToggleButton
            {
                Width = 30, Height = 30, Margin = new Thickness(2, 0, 2, 0), IsChecked = on, ToolTip = tip,
                Content = new Image { Width = 18, Height = 18, Source = ShotComposer.StateImage(state, 18, fg, on ? Brushes.White : Brushes.Red) },
                Style = (Style)Application.Current.Resources["Chip"],
            };
            t.Click += (o, e) => set(t.IsChecked == true);
            return t;
        }

        ContextMenu CardMenu(ShotScreen sc)
        {
            var m = new ContextMenu();
            Ui.MenuAdd(m, S.Get("shotName"), "", () =>
            {
                var v = InputBox.Ask(this, S.Get("shotName"), S.Get("shotNameNote"), ShotComposer.Name(p, sc));
                if (v != null) { sc.Name = v == ShotComposer.DefaultName(p, sc) ? "" : v; Changed(); }
            });
            if (!string.IsNullOrEmpty(sc.Name)) Ui.MenuAdd(m, S.Get("shotNameReset"), "", () => { sc.Name = ""; Changed(); });
            m.Items.Add(new Separator());
            var st = Styles;
            if (st.Count > 1)
            {
                var sm = new MenuItem { Header = S.Get("shotStyle") + ": " + p.StyleTitle(st[Math.Min(sc.Style, st.Count - 1)]) };
                for (int i = 0; i < st.Count; i++)
                {
                    int k = i;
                    var it = new MenuItem { Header = p.StyleTitle(st[i]), IsCheckable = true, IsChecked = sc.Style == i };
                    it.Click += (o, e) => { sc.Style = k; if (p.AodOf(st[k]) < 0) sc.Aod = false; Changed(); };
                    sm.Items.Add(it);
                }
                m.Items.Add(sm);
            }
            var cs = ColorsList;
            if (cs.Count > 0)
            {
                var cm = new MenuItem { Header = S.Get("shotColor") + ": " + ShotComposer.ColorName(sc.Color) };
                for (int i = 0; i < cs.Count; i++)
                {
                    int k = i;
                    var it = new MenuItem { Header = ShotComposer.ColorName(i), IsCheckable = true, IsChecked = sc.Color == i, Icon = new Ellipse { Width = 12, Height = 12, Fill = Imaging.Brush(cs[i]) } };
                    it.Click += (o, e) => { sc.Color = k; Changed(); };
                    cm.Items.Add(it);
                }
                m.Items.Add(cm);
            }
            var slots = p.Slots(ShotComposer.Theme(p, sc));
            if (slots.Count > 0)
            {
                var wm = new MenuItem { Header = S.Get("shotWidgets"), Icon = new TextBlock { Text = "\uF0E2", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 14 } };
                for (int n = 0; n < slots.Count; n++)
                {
                    var slot = slots[n];
                    var name = slot.Str("name") ?? "";
                    var ws = WidgetSlots.Widgets(p, slot);
                    int cur = Math.Min(sc.Widgets.TryGetValue(name, out var ci) ? ci : WidgetSlots.Shown(p, slot), Math.Max(0, ws.Count - 1));
                    if (n > 0) wm.Items.Add(new Separator());
                    wm.Items.Add(new MenuItem { Header = S.Get("shotSlotN", n + 1), IsEnabled = false });
                    for (int i = 0; i < ws.Count; i++)
                    {
                        int k = i;
                        var it = new MenuItem { Header = ws[i].Str("widgetName") ?? S.Get("shotWidget"), IsCheckable = true, IsChecked = i == cur };
                        it.Click += (o, e) => { sc.Widgets[name] = k; Changed(); };
                        wm.Items.Add(it);
                    }
                }
                m.Items.Add(wm);
            }
            if (p.AodOf(st[Math.Min(sc.Style, st.Count - 1)]) >= 0)
            {
                var a = new MenuItem { Header = S.Get("shotAod"), IsCheckable = true, IsChecked = sc.Aod };
                a.Click += (o, e) => { sc.Aod = !sc.Aod; Changed(); };
                m.Items.Add(a);
            }
            m.Items.Add(new Separator());
            Ui.MenuAdd(m, S.Get("shotDuplicate"), "", () =>
            {
                var c = sc.Copy(); c.Id = Guid.NewGuid().ToString().ToUpperInvariant(); c.Name = "";
                s.Screens.Insert(s.Screens.IndexOf(sc) + 1, c); Changed();
            });
            Ui.MenuAdd(m, S.Get("shotRemove"), "", () => { s.Screens.Remove(sc); Changed(); }, danger: true);
            return m;
        }

        FrameworkElement AddCard()
        {
            var col = new StackPanel { Width = 96, Margin = new Thickness(0, 0, 4, 14) };
            var btn = new Button { Content = Capsule(null, true), Background = Brushes.Transparent, BorderThickness = new Thickness(0), Padding = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Center, ToolTip = S.Get("shotAdd") };
            btn.Click += (o, e) =>
            {
                var m = new ContextMenu();
                var st = Styles;
                m.Items.Add(new MenuItem { Header = S.Get("shotNewScreen"), IsEnabled = false });
                for (int i = 0; i < st.Count; i++) AddItem(m, i, false);
                var aods = Enumerable.Range(0, st.Count).Where(i => p.AodOf(st[i]) >= 0).ToList();
                if (aods.Count > 0)
                {
                    m.Items.Add(new Separator());
                    m.Items.Add(new MenuItem { Header = S.Get("shotAod"), IsEnabled = false });
                    foreach (var i in aods) AddItem(m, i, true);
                }
                Ui.MenuBelow(m, btn); m.IsOpen = true;
            };
            col.Children.Add(btn);
            var t = new TextBlock { Text = S.Get("shotAdd"), FontSize = 12, FontWeight = FontWeights.Medium, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
            t.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
            col.Children.Add(t);
            return col;
        }

        void AddItem(ContextMenu m, int style, bool aod)
        {
            var title = p.StyleTitle(Styles[style]) + (aod ? " · AOD" : "");
            var cs = ColorsList;
            if (cs.Count == 0)
            {
                var it = new MenuItem { Header = title };
                it.Click += (o, e) => { s.Screens.Add(new ShotScreen { Style = style, Aod = aod }); Changed(); };
                m.Items.Add(it);
                return;
            }
            var sub = new MenuItem { Header = title };
            for (int i = 0; i < cs.Count; i++)
            {
                int k = i;
                var it = new MenuItem { Header = ShotComposer.ColorName(i), Icon = new Ellipse { Width = 12, Height = 12, Fill = Imaging.Brush(cs[i]) } };
                it.Click += (o, e) => { s.Screens.Add(new ShotScreen { Style = style, Aod = aod, Color = k }); Changed(); };
                sub.Items.Add(it);
            }
            m.Items.Add(sub);
        }

        void FormatBlock()
        {
            panel.Children.Add(Ui.Header(S.Get("shotFormat")));
            panel.Children.Add(Ui.Chips(null, new[] { Ui.P("auto", S.Get("shotAuto")), Ui.P("square", "1 : 1"), Ui.P("story", "9 : 16"), Ui.P("wide", "16 : 9") },
                s.Format, v => { s.Format = v; Changed(); }));
            panel.Children.Add(Ui.Note(S.Get("shotFormatNote")));
        }

        void ScreenLookBlock()
        {
            panel.Children.Add(Ui.Header(S.Get("shotScreens")));
            panel.Children.Add(Ui.Chips(S.Get("shotSize"), new[] { Ui.P("0", S.Get("shotLarge")), Ui.P("1", S.Get("shotMedium")), Ui.P("2", S.Get("shotSmall")) },
                s.Size.ToString(), v => { s.Size = int.Parse(v); Changed(); }));
            panel.Children.Add(Ui.Chips(S.Get("shotFrame"), new[] { Ui.P("capsule", S.Get("shotCapsule")), Ui.P("band", S.Get("shotBand")) },
                s.Band ? "band" : "capsule", v => { s.Band = v == "band"; Changed(); }));
            var time = new TextBox { Width = 80, Text = s.Time ?? p.Meta.Demo.Time ?? "09:55" };
            void Commit()
            {
                var parts = time.Text.Split(':', '.', ' ').Where(x => x.Length > 0).ToArray();
                if (parts.Length == 2 && int.TryParse(parts[0], out var h) && int.TryParse(parts[1], out var mm) && h >= 0 && h < 24 && mm >= 0 && mm < 60)
                {
                    var v = $"{h:00}:{mm:00}";
                    if (v != s.Time) { s.Time = v; Changed(); }
                }
                else time.Text = s.Time ?? p.Meta.Demo.Time ?? "09:55";
            }
            time.LostFocus += (o, e) => Commit();
            time.KeyDown += (o, e) => { if (e.Key == System.Windows.Input.Key.Enter) Commit(); };
            panel.Children.Add(Ui.Row(S.Get("shotTime"), time, 80));
        }

        void BackgroundBlock()
        {
            panel.Children.Add(Ui.Header(S.Get("shotBackground")));
            var row = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
            foreach (var key in ShotSet.Backgrounds)
            {
                bool on = s.Background == key;
                var dot = new Ellipse { Width = 30, Height = 30, Fill = ShotComposer.BackgroundBrush(p, key), Stroke = Res("CardBorder"), StrokeThickness = 1 };
                var ring = new Border { Width = 38, Height = 38, CornerRadius = new CornerRadius(19), BorderThickness = new Thickness(2), BorderBrush = on ? Res("Accent") : Brushes.Transparent, Child = dot, HorizontalAlignment = HorizontalAlignment.Center };
                var cell = new StackPanel { Width = 58, Margin = new Thickness(0, 0, 2, 4), Cursor = System.Windows.Input.Cursors.Hand, Background = Brushes.Transparent };
                cell.Children.Add(ring);
                var label = new TextBlock { Text = S.Get("shotBg_" + key), FontSize = 10.5, HorizontalAlignment = HorizontalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 4, 0, 0) };
                label.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
                cell.Children.Add(label);
                var k = key;
                cell.MouseLeftButtonUp += (o, e) => { s.Background = k; Changed(); };
                row.Children.Add(cell);
            }
            panel.Children.Add(row);
            var custom = s.Background.StartsWith("#") ? s.Background : "#3A6EA5";
            panel.Children.Add(Ui.Row(S.Get("shotBg_custom"), Ui.ColorRow(S.Get("shotBg_custom"), custom, h => { s.Background = h; Changed(); }), 140));
        }

        void TextBlockSection()
        {
            panel.Children.Add(Ui.Header(S.Get("shotText")));
            TextRow(S.Get("shotTitle"), s.Title, ShotComposer.AutoTitle(p), v => s.Title = v);
            TextRow(S.Get("shotAbove"), s.Above, ShotComposer.AutoAbove(p), v => s.Above = v);
            TextRow(S.Get("shotBelow"), s.Below, ShotComposer.AutoBelow(p), v => s.Below = v);
            panel.Children.Add(Ui.Note(S.Get("shotTextNote")));
        }

        /// <summary>Рядок тексту: порожньо — без рядка; кнопка ↺ — автоматичний текст</summary>
        void TextRow(string label, string value, string auto, Action<string> set)
        {
            var box = new TextBox { Text = value ?? auto, Width = 210 };
            void Commit()
            {
                var t = box.Text.Trim();
                string v = t == auto ? null : t;
                if (v != value) { set(v); Changed(); }
            }
            box.LostFocus += (o, e) => Commit();
            box.KeyDown += (o, e) => { if (e.Key == System.Windows.Input.Key.Enter) Commit(); };
            var line = new StackPanel { Orientation = Orientation.Horizontal };
            line.Children.Add(box);
            var reset = Ui.Icon("", S.Get("shotAutoText"), () => { set(null); Changed(); });
            reset.Margin = new Thickness(6, 0, 0, 0);
            reset.IsEnabled = value != null;
            line.Children.Add(reset);
            panel.Children.Add(Ui.Row(label, line, 250));
        }

        void LookBlock()
        {
            panel.Children.Add(Ui.Header(S.Get("shotLook")));
            panel.Children.Add(Ui.Switch(S.Get("shotRounded"), s.Rounded, v => { s.Rounded = v; Changed(); }, !s.Band));
            panel.Children.Add(Ui.Switch(S.Get("shotCaptions"), s.Captions, v => { s.Captions = v; Changed(); }));
            panel.Children.Add(Ui.Switch(S.Get("shotShadow"), s.Shadow, v => { s.Shadow = v; Changed(); }));
            panel.Children.Add(Ui.Switch(S.Get("shotCreditOpt"), s.Credit, v => { s.Credit = v; Changed(); }));
        }

        /// <summary>Готова картинка в окремому вікні: 100 % пікселів, Ctrl + коліщатко — масштаб, перетягування — прокрутка</summary>
        void ShowZoom()
        {
            var img = new Image { Source = image, Stretch = Stretch.Uniform, Width = image.PixelWidth / 2.0, Height = image.PixelHeight / 2.0 };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            var sv = new ScrollViewer { Content = img, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = Brushes.Black };
            double z = 1;
            var w = new Window { Title = S.Get("shotSet"), Width = Math.Min(1200, image.PixelWidth / 2.0 + 40), Height = Math.Min(900, image.PixelHeight / 2.0 + 60), Owner = this, Content = sv, WindowStartupLocation = WindowStartupLocation.CenterOwner };
            sv.PreviewMouseWheel += (o, e) =>
            {
                if ((System.Windows.Input.Keyboard.Modifiers & System.Windows.Input.ModifierKeys.Control) == 0) return;
                z = Math.Max(0.25, Math.Min(4, z * (e.Delta > 0 ? 1.15 : 1 / 1.15)));
                img.Width = image.PixelWidth / 2.0 * z; img.Height = image.PixelHeight / 2.0 * z;
                e.Handled = true;
            };
            Point? from = null; double h0 = 0, v0 = 0;
            img.MouseLeftButtonDown += (o, e) => { from = e.GetPosition(sv); h0 = sv.HorizontalOffset; v0 = sv.VerticalOffset; img.CaptureMouse(); };
            img.MouseMove += (o, e) => { if (from is Point f) { var q = e.GetPosition(sv); sv.ScrollToHorizontalOffset(h0 - (q.X - f.X)); sv.ScrollToVerticalOffset(v0 - (q.Y - f.Y)); } };
            img.MouseLeftButtonUp += (o, e) => { from = null; img.ReleaseMouseCapture(); };
            w.SourceInitialized += (o, e) => Theme.Apply(w);
            w.ShowDialog();
        }

        // ---------- Готово ----------

        string FileName()
        {
            var t = s.Title ?? ShotComposer.AutoTitle(p);
            if (string.IsNullOrWhiteSpace(t)) t = S.Get("shotSet");
            return new string(t.Select(c => System.IO.Path.GetInvalidFileNameChars().Contains(c) ? '-' : c).ToArray()).Trim() + ".png";
        }

        void Save()
        {
            Recompose();
            if (image == null) return;
            var dlg = new SaveFileDialog { Filter = "PNG|*.png", DefaultExt = ".png", FileName = FileName() };
            if (dlg.ShowDialog(this) != true) return;
            try
            {
                var enc = new PngBitmapEncoder();
                enc.Frames.Add(BitmapFrame.Create(image));
                using (var f = File.Create(dlg.FileName)) enc.Save(f);
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "BandFace", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        void Copy()
        {
            Recompose();
            if (image == null) return;
            try { Clipboard.SetImage(image); } catch (Exception) { }
        }
    }
}
