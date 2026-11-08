// SPDX-License-Identifier: MIT
// «Додати елемент» у два кроки.
// 1) Що додати: плитки з іконкою, назвою й підписом; фільтри Усі / Дані / Шкали / Декор, пошук,
//    праворуч «Як це виглядає» — справжнє превʼю, намальоване тим самим рушієм, що й полотно.
// 2) Що показувати (для чисел, шкал і значків): дані за групами з прикладом значення та пошуком.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using BandFace.Faces;

namespace BandFace.Creator
{
    sealed class AddGallery : Window
    {
        public sealed class Choice { public string Kind, Source; }

        sealed class Item
        {
            public string Kind, Group, Title, Caption;
            public bool NeedsSource;
            public string DefaultSource;
        }

        static readonly Item[] Items =
        {
            new Item { Kind = "digits", Group = "data", NeedsSource = true, DefaultSource = "timeHour" },
            new Item { Kind = "values", Group = "data", NeedsSource = true, DefaultSource = "systemStatusBattery" },
            new Item { Kind = "clock", Group = "gauges" },
            new Item { Kind = "pointer", Group = "gauges", NeedsSource = true, DefaultSource = "timeSecond" },
            new Item { Kind = "arc", Group = "gauges", NeedsSource = true, DefaultSource = "healthStepProgress" },
            new Item { Kind = "line", Group = "gauges", NeedsSource = true, DefaultSource = "systemStatusBattery" },
            new Item { Kind = "image", Group = "decor" },
            new Item { Kind = "animation", Group = "decor" },
            new Item { Kind = "background", Group = "decor" },
        };

        /// <summary>Дані, які найчастіше потрібні цьому елементу — зверху списку</summary>
        static readonly Dictionary<string, string[]> Recommended = new Dictionary<string, string[]>
        {
            ["digits"] = new[] { "timeHour", "timeMinute", "dateDay", "dateMonth", "healthStepCount", "healthHeartRate", "systemStatusBattery" },
            ["values"] = new[] { "systemStatusBattery", "weatherCurrentWeather", "dateWeek", "systemStatusBluetooth" },
            ["pointer"] = new[] { "timeHour", "timeMinute", "timeSecond", "systemStatusBattery" },
            ["arc"] = new[] { "healthStepProgress", "healthCalorieProgress", "healthStandProgress", "systemStatusBattery", "healthHeartRate" },
            ["line"] = new[] { "systemStatusBattery", "healthStepProgress", "healthCalorieProgress", "healthStandProgress" },
        };

        readonly TextBox search = new TextBox();
        readonly StackPanel filters = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 10) };
        readonly ListBox tiles = new ListBox { BorderThickness = new Thickness(0), Background = Brushes.Transparent };
        readonly ListBox sources = new ListBox { BorderThickness = new Thickness(0), Background = Brushes.Transparent };
        readonly TextBlock title = new TextBlock { FontSize = 20, FontWeight = FontWeights.SemiBold };
        readonly TextBlock subtitle = new TextBlock { FontSize = 12, Margin = new Thickness(0, 2, 0, 10), TextWrapping = TextWrapping.Wrap };
        readonly Image preview = new Image { Stretch = Stretch.Uniform };
        readonly TextBlock previewTitle = new TextBlock { FontSize = 14, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 12, 0, 2), TextWrapping = TextWrapping.Wrap };
        readonly TextBlock previewText = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap };
        readonly Button back = new Button(), next = new Button();
        readonly Grid body = new Grid();
        readonly Border previewFace = new Border();
        string filter = "all";
        int step = 1;
        Item item;
        Choice result;

        AddGallery()
        {
            Title = S.Get("addElement");
            Width = 880; Height = 620; MinWidth = 720; MinHeight = 500;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Segoe UI");
            SetResourceReference(BackgroundProperty, "Bg");
            SetResourceReference(ForegroundProperty, "Text");
            subtitle.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            previewText.SetResourceReference(TextBlock.ForegroundProperty, "Sub");

            var root = new DockPanel { Margin = new Thickness(20, 16, 20, 16) };
            var top = new StackPanel();
            DockPanel.SetDock(top, Dock.Top);
            top.Children.Add(title);
            top.Children.Add(subtitle);
            top.Children.Add(search);
            top.Children.Add(filters);
            root.Children.Add(top);

            var buttons = new DockPanel { Margin = new Thickness(0, 14, 0, 0) };
            DockPanel.SetDock(buttons, Dock.Bottom);
            back.Style = (Style)FindResource("Btn");
            next.Style = (Style)FindResource("PrimaryBtn");
            next.Margin = new Thickness(10, 0, 0, 0);
            next.IsDefault = true;
            var cancel = new Button { Content = S.Get("cancel"), Style = (Style)FindResource("Btn"), IsCancel = true };
            var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            right.Children.Add(cancel);
            right.Children.Add(next);
            DockPanel.SetDock(right, Dock.Right);
            buttons.Children.Add(right);
            buttons.Children.Add(new Border { Child = back, HorizontalAlignment = HorizontalAlignment.Left });
            root.Children.Add(buttons);

            // ліворуч — плитки або список даних, праворуч — «Як це виглядає»
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
            tiles.ItemContainerStyle = (Style)FindResource("LayerItem");
            ScrollViewer.SetHorizontalScrollBarVisibility(tiles, ScrollBarVisibility.Disabled);
            var wrap = new FrameworkElementFactory(typeof(WrapPanel));
            tiles.ItemsPanel = new ItemsPanelTemplate(wrap);
            tiles.SelectionChanged += (s, e) => { item = (tiles.SelectedItem as ListBoxItem)?.Tag as Item; UpdatePreview(); };
            tiles.MouseDoubleClick += (s, e) => { if (item != null) Next(); };
            sources.ItemContainerStyle = (Style)FindResource("LayerItem");
            ScrollViewer.SetHorizontalScrollBarVisibility(sources, ScrollBarVisibility.Disabled);
            sources.SelectionChanged += (s, e) => UpdatePreview();
            sources.MouseDoubleClick += (s, e) => { if (SelectedSource != null) Next(); };
            var left = new Border { Style = (Style)FindResource("CardBox"), Padding = new Thickness(8), Margin = new Thickness(0), Child = new Grid { Children = { tiles, sources } } };
            body.Children.Add(left);

            var pane = new StackPanel { Margin = new Thickness(16, 0, 0, 0) };
            pane.Children.Add(new TextBlock { Text = S.Get("howItLooks").ToUpper(), FontSize = 11, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) });
            previewFace.Child = preview;
            previewFace.BorderThickness = new Thickness(3);
            previewFace.BorderBrush = new SolidColorBrush(Color.FromRgb(0x8A, 0x8A, 0x8A));
            previewFace.Background = Brushes.Black;
            previewFace.HorizontalAlignment = HorizontalAlignment.Center;
            pane.Children.Add(previewFace);
            pane.Children.Add(previewTitle);
            pane.Children.Add(previewText);
            Grid.SetColumn(pane, 1);
            body.Children.Add(pane);
            root.Children.Add(body);
            Content = root;

            back.Click += (s, e) => { if (step == 2) ShowStep(1); };
            next.Click += (s, e) => Next();
            search.TextChanged += (s, e) => { if (step == 1) FillTiles(); else FillSources(); };
            PreviewKeyDown += (s, e) =>
            {
                // стрілки зі строки пошуку — одразу в список
                if ((e.Key == Key.Down || e.Key == Key.Up) && search.IsKeyboardFocused)
                {
                    var lb = step == 1 ? tiles : sources;
                    int i = Math.Max(0, Math.Min(lb.Items.Count - 1, lb.SelectedIndex + (e.Key == Key.Down ? 1 : -1)));
                    while (i < lb.Items.Count && !((ListBoxItem)lb.Items[i]).IsEnabled) i++;
                    if (i < lb.Items.Count) { lb.SelectedIndex = i; lb.ScrollIntoView(lb.SelectedItem); }
                    e.Handled = true;
                }
            };
            Loaded += (s, e) => { Theme.Apply(this); search.Focus(); };
            ShowStep(1);
        }

        // MARK: Кроки

        void ShowStep(int s)
        {
            step = s;
            search.Text = "";
            tiles.Visibility = s == 1 ? Visibility.Visible : Visibility.Collapsed;
            sources.Visibility = s == 2 ? Visibility.Visible : Visibility.Collapsed;
            filters.Visibility = s == 1 ? Visibility.Visible : Visibility.Collapsed;
            back.Visibility = s == 2 ? Visibility.Visible : Visibility.Collapsed;
            back.Content = "← " + S.Get("backStep");
            if (s == 1)
            {
                title.Text = S.Get("addElement");
                subtitle.Text = S.Get("addStep1");
                FillFilters();
                FillTiles();
            }
            else
            {
                title.Text = S.Get("pickData") + " — " + S.Get("kind_" + item.Kind);
                subtitle.Text = S.Get("addStep2");
                FillSources();
            }
            UpdateNext();
            search.Focus();
        }

        void Next()
        {
            if (step == 1)
            {
                if (item == null) return;
                if (item.NeedsSource) { ShowStep(2); return; }
                result = new Choice { Kind = item.Kind };
                DialogResult = true;
                return;
            }
            var src = SelectedSource;
            if (src == null) return;
            result = new Choice { Kind = item.Kind, Source = src };
            DialogResult = true;
        }

        void UpdateNext()
        {
            next.Content = step == 1 && item != null && item.NeedsSource ? S.Get("nextStep") + " →" : S.Get("add");
            next.IsEnabled = step == 1 ? item != null : SelectedSource != null;
        }

        // MARK: Крок 1 — плитки

        void FillFilters()
        {
            filters.Children.Clear();
            foreach (var f in new[] { "all", "data", "gauges", "decor" })
            {
                var t = new System.Windows.Controls.Primitives.ToggleButton { Content = S.Get("flt_" + f), Style = (Style)FindResource("Chip"), IsChecked = f == filter, Padding = new Thickness(12, 0, 12, 0), Height = 30, Margin = new Thickness(0, 0, 6, 0) };
                var key = f;
                t.Click += (s, e) => { filter = key; FillFilters(); FillTiles(); };
                filters.Children.Add(t);
            }
        }

        void FillTiles()
        {
            var q = search.Text.Trim();
            var keep = item;
            tiles.Items.Clear();
            foreach (var it in Items)
            {
                if (filter != "all" && it.Group != filter) continue;
                var t = S.Get("kind_" + it.Kind); var c = S.Get("cap_" + it.Kind);
                if (q.Length > 0 && t.IndexOf(q, StringComparison.CurrentCultureIgnoreCase) < 0 && c.IndexOf(q, StringComparison.CurrentCultureIgnoreCase) < 0) continue;
                var sp = new StackPanel { Width = 150, Height = 118, Margin = new Thickness(4) };
                sp.Children.Add(new Border { Height = 44, Child = Icon(it.Kind), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(2, 4, 0, 8) });
                sp.Children.Add(new TextBlock { Text = t, FontSize = 14, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
                var cap = new TextBlock { Text = c, FontSize = 11.5, TextWrapping = TextWrapping.Wrap, MaxHeight = 32, TextTrimming = TextTrimming.CharacterEllipsis };
                cap.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
                sp.Children.Add(cap);
                var li = new ListBoxItem { Content = sp, Tag = it, ToolTip = c };
                tiles.Items.Add(li);
                if (it == keep) tiles.SelectedItem = li;
            }
            if (tiles.SelectedItem == null && tiles.Items.Count > 0) tiles.SelectedIndex = 0;
            item = (tiles.SelectedItem as ListBoxItem)?.Tag as Item;
            UpdatePreview();
        }

        /// <summary>Однотонні значки в стилі Windows (без емодзі)</summary>
        FrameworkElement Icon(string kind)
        {
            var c = new Canvas { Width = 40, Height = 40 };
            Shape S1(Shape s) { s.SetResourceReference(Shape.StrokeProperty, "Accent"); s.StrokeThickness = 3; s.StrokeStartLineCap = s.StrokeEndLineCap = PenLineCap.Round; return s; }
            TextBlock T(string t, double size, string font = "Segoe UI") { var tb = new TextBlock { Text = t, FontSize = size, FontWeight = FontWeights.Bold, FontFamily = new FontFamily(font) }; tb.SetResourceReference(TextBlock.ForegroundProperty, "Accent"); return tb; }
            switch (kind)
            {
                case "digits": { var t = T("12", 26); Canvas.SetTop(t, 1); c.Children.Add(t); break; }
                case "values":
                    c.Children.Add(S1(new Rectangle { Width = 26, Height = 14, RadiusX = 3, RadiusY = 3, Margin = new Thickness(2, 13, 0, 0) }));
                    c.Children.Add(S1(new Line { X1 = 33, Y1 = 17, X2 = 33, Y2 = 23 }));
                    var fill = new Rectangle { Width = 14, Height = 8, Margin = new Thickness(6, 16, 0, 0) };
                    fill.SetResourceReference(Shape.FillProperty, "Accent");
                    c.Children.Add(fill);
                    break;
                case "clock":
                    c.Children.Add(S1(new Ellipse { Width = 34, Height = 34, Margin = new Thickness(3) }));
                    c.Children.Add(S1(new Line { X1 = 20, Y1 = 20, X2 = 20, Y2 = 10 }));
                    c.Children.Add(S1(new Line { X1 = 20, Y1 = 20, X2 = 27, Y2 = 24 }));
                    break;
                case "pointer":
                    c.Children.Add(S1(new Line { X1 = 20, Y1 = 34, X2 = 30, Y2 = 8 }));
                    var dot = new Ellipse { Width = 8, Height = 8, Margin = new Thickness(16, 30, 0, 0) };
                    dot.SetResourceReference(Shape.FillProperty, "Accent");
                    c.Children.Add(dot);
                    break;
                case "arc":
                {
                    var g = Geometry.Parse("M 9,31 A 15,15 0 1 1 31,31");
                    c.Children.Add(S1(new Path { Data = g }));
                    var t = new Path { Data = Geometry.Parse("M 9,31 A 15,15 0 0 1 20,5"), StrokeThickness = 5, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
                    t.SetResourceReference(Shape.StrokeProperty, "Accent");
                    c.Children.Add(t);
                    break;
                }
                case "line":
                    c.Children.Add(S1(new Line { X1 = 4, Y1 = 20, X2 = 36, Y2 = 20, Opacity = 0.45 }));
                    var l2 = new Line { X1 = 4, Y1 = 20, X2 = 24, Y2 = 20, StrokeThickness = 5, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
                    l2.SetResourceReference(Shape.StrokeProperty, "Accent");
                    c.Children.Add(l2);
                    break;
                case "image":
                    c.Children.Add(S1(new Rectangle { Width = 32, Height = 26, RadiusX = 3, RadiusY = 3, Margin = new Thickness(4, 7, 0, 0) }));
                    c.Children.Add(S1(new Path { Data = Geometry.Parse("M 8,29 L 16,20 L 22,25 L 27,19 L 32,25") }));
                    break;
                case "animation":
                    c.Children.Add(S1(new Rectangle { Width = 32, Height = 26, RadiusX = 3, RadiusY = 3, Margin = new Thickness(4, 7, 0, 0) }));
                    var play = new Path { Data = Geometry.Parse("M 16,14 L 26,20 L 16,26 Z") };
                    play.SetResourceReference(Shape.FillProperty, "Accent");
                    c.Children.Add(play);
                    break;
                case "background":
                    c.Children.Add(S1(new Rectangle { Width = 18, Height = 34, RadiusX = 9, RadiusY = 9, Margin = new Thickness(11, 3, 0, 0) }));
                    var bg = new Rectangle { Width = 12, Height = 28, RadiusX = 6, RadiusY = 6, Margin = new Thickness(14, 6, 0, 0), Opacity = 0.45 };
                    bg.SetResourceReference(Shape.FillProperty, "Accent");
                    c.Children.Add(bg);
                    break;
            }
            return c;
        }

        // MARK: Крок 2 — дані

        string SelectedSource => step == 2 ? (sources.SelectedItem as ListBoxItem)?.Tag as string : null;

        static string GroupOf(string s)
        {
            if (s.StartsWith("time") || s.StartsWith("dualtime") || s == "miscIs24H" || s == "miscIsAM" || s == "miscIsPM" || s == "miscTimeSection") return "time";
            if (s.StartsWith("date") || s.StartsWith("miscdate")) return "date";
            if (s.StartsWith("healthStep") || s.StartsWith("healthCalorie") || s.StartsWith("healthStand") || s.StartsWith("healthExercise")
                || s.StartsWith("healthEnergy") || s.Contains("Vitality") || s.StartsWith("appSport") || s.StartsWith("healthMisc")) return "activity";
            if (s.StartsWith("health") || s.StartsWith("system")) return "body";
            if (s.StartsWith("weather")) return "weather";
            return "other";
        }

        static string Example(string src)
        {
            int v = SampleData.Value(src);
            var l = src.ToLowerInvariant();
            if (l.Contains("progress") || l.Contains("battery") || l.Contains("humidity") || l.Contains("chanceofrain")) return v + " %";
            if (l.Contains("heartrate")) return v + " bpm";
            if (l.Contains("temperature")) return v + "°";
            if (src == "timeHour" || src == "timeMinute" || src == "timeSecond") return v.ToString("00");
            return v.ToString();
        }

        void FillSources()
        {
            var q = search.Text.Trim();
            var keep = SelectedSource ?? item?.DefaultSource;
            sources.Items.Clear();
            var all = FaceCatalog.Sources.Select(x => x.Item1).Distinct().ToList();
            bool Match(string x) => q.Length == 0 || x.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0
                                    || SampleData.Title(x).IndexOf(q, StringComparison.CurrentCultureIgnoreCase) >= 0;
            ListBoxItem sel = null;
            void Group(string titleKey, IEnumerable<string> list)
            {
                var items = list.Where(Match).ToList();
                if (items.Count == 0) return;
                var h = new TextBlock { Text = S.Get(titleKey).ToUpper(), FontSize = 11, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 2) };
                h.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
                sources.Items.Add(new ListBoxItem { Content = h, IsEnabled = false, Focusable = false });
                foreach (var x in items)
                {
                    var g = new Grid();
                    g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    var sp = new StackPanel();
                    sp.Children.Add(new TextBlock { Text = SampleData.Title(x), FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis });
                    if (SampleData.HasTitle(x)) { var k = new TextBlock { Text = x, FontSize = 11, Opacity = 0.6 }; sp.Children.Add(k); }
                    g.Children.Add(sp);
                    var ex = new Border { CornerRadius = new CornerRadius(4), Padding = new Thickness(7, 1, 7, 1), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 4, 0),
                        Child = new TextBlock { Text = Example(x), FontSize = 12, FontFamily = new FontFamily("Segoe UI Semibold") } };
                    ex.SetResourceReference(Border.BackgroundProperty, "ChipBg");
                    Grid.SetColumn(ex, 1);
                    g.Children.Add(ex);
                    var li = new ListBoxItem { Content = g, Tag = x, ToolTip = S.Get("exampleValue", Example(x)) };
                    sources.Items.Add(li);
                    if (sel == null && x == keep) sel = li;
                }
            }
            if (item != null && Recommended.TryGetValue(item.Kind, out var rec)) Group("grp_recommended", rec.Where(all.Contains));
            foreach (var g in new[] { "time", "date", "activity", "body", "weather", "other" })
                Group("grp2_" + g, all.Where(x => GroupOf(x) == g));
            if (sel == null) sel = sources.Items.Cast<ListBoxItem>().FirstOrDefault(i => i.IsEnabled);
            if (sel != null) { sources.SelectedItem = sel; sources.ScrollIntoView(sel); }
            UpdatePreview();
        }

        // MARK: Превʼю

        void UpdatePreview()
        {
            UpdateNext();
            if (item == null) { preview.Source = null; previewTitle.Text = ""; previewText.Text = ""; return; }
            previewTitle.Text = step == 2 && SelectedSource != null ? S.Get("kind_" + item.Kind) + " · " + SampleData.Title(SelectedSource) : S.Get("kind_" + item.Kind);
            previewText.Text = S.Get("about_" + item.Kind);
            try
            {
                var p = Sample(item.Kind, SelectedSource ?? item.DefaultSource);
                var dev = p.Meta.Device;
                double scale = 300.0 / dev.Height;
                double dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
                preview.Source = new FaceRenderer(p).Render(0, scale * dpi).Image;
                preview.Width = dev.Width * scale; preview.Height = dev.Height * scale;
                double rad = dev.Corner * scale;
                preview.Clip = new RectangleGeometry(new Rect(0, 0, preview.Width, preview.Height), rad, rad);
                previewFace.CornerRadius = new CornerRadius(rad + 3);
            }
            catch (Exception) { preview.Source = null; }
        }

        static RgbaImage SampleArt(int w, int h, string a, string b)
            => Imaging.Render(w, h, dc => dc.DrawRoundedRectangle(new LinearGradientBrush(Imaging.ParseColor(a), Imaging.ParseColor(b), 45), null, new Rect(0, 0, w, h), 14, 14));

        /// <summary>Тимчасовий проєкт (без теки) з одним елементом у центрі</summary>
        static FaceProject Sample(string kind, string src)
        {
            var root = new XNode("Watchface");
            root.Set("id", "1").Set("name", "preview");
            root.Add("Resources");
            root.Add("Theme").Set("type", "normal").Set("name", "").Set("bgColor", "#000000");
            var p = new FaceProject("gallery", null, root, new Dictionary<string, byte[]>(), new ProjectMeta());
            int cx = p.Meta.Device.Width / 2, cy = p.Meta.Device.Height / 2;
            switch (kind)
            {
                case "digits": ElementFactory.AddDigits(p, src, new Generator(GenKind.Digits) { Color = "#FFFFFF", FontSize = 48, Weight = 700, Style = "rounded" }, 0, cx, cy - 30); break;
                case "values":
                {
                    var imgs = new[] { "#FF453A", "#FFD60A", "#30B455" }.Select(c => SampleArt(56, 56, c, c)).ToList();
                    ElementFactory.AddValues(p, src, imgs, 0, cx, cy);
                    break;
                }
                case "clock": ElementFactory.AddAnalogClock(p, 0, cx, cy); break;
                case "pointer": ElementFactory.AddPointer(p, src, new Generator(GenKind.Pointer) { Color = "#FFFFFF", Width = 6, Length = 80 }, 0, cx, cy); break;
                case "arc": ElementFactory.AddArc(p, src, new Generator(GenKind.Arc) { Color = "#30B455", BgColor = "#3A3A3C", Radius = 60, Width = 10 }, 0, cx, cy); break;
                case "line": ElementFactory.AddLine(p, src, new Generator(GenKind.Line) { Color = "#0A6CF0", BgColor = "#3A3A3C", Width = 8, Length = 140 }, 0, cx, cy); break;
                case "image": ElementFactory.AddImage(p, SampleArt(120, 90, "#5E8BFF", "#B05EFF"), 0, cx, cy); break;
                case "animation": ElementFactory.AddAnimation(p, new List<RgbaImage> { SampleArt(90, 90, "#FF9500", "#FF375F") }, 100, 0, cx, cy); break;
                case "background": ElementFactory.AddBackground(p, SampleArt(p.Meta.Device.Width, p.Meta.Device.Height, "#1E3C72", "#2A5298"), 0); break;
            }
            return p;
        }

        /// <summary>Для знімків екрана: вікно без очікування, на кроці 1 або 2 (дуга)</summary>
        public static Window Demo(Window owner, int step)
        {
            var w = new AddGallery { Owner = owner, ShowActivated = false };
            if (step == 2) { w.item = Items.First(i => i.Kind == "arc"); w.ShowStep(2); }
            w.Show();
            return w;
        }

        public static Choice Pick(Window owner)
        {
            var w = new AddGallery { Owner = owner };
            return w.ShowDialog() == true ? w.result : null;
        }
    }
}
