// SPDX-License-Identifier: MIT
// «Намалювати шрифтом»: окреме вікно, що перемальовує ВСІ картинки елемента одним шрифтом —
// цифри, дні тижня, місяці, AM/PM, будь-які значки за значенням (свій рядок на кожну картинку), напис.
// Шрифт, розмір, товщина, колір, набори цифр і ефекти живуть тут, а не в інспекторі.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using BandFace.Faces;

namespace BandFace.Creator
{
    sealed class FontArtWindow : Window
    {
        readonly FaceProject project;
        readonly XNode res;
        readonly GenKind kind;
        readonly int slots;
        Generator g;
        readonly StackPanel settings = new StackPanel();
        readonly WrapPanel preview = new WrapPanel();
        readonly TextBlock previewNote = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) };
        TextBox textsBox;
        bool built;

        /// <summary>Готові списки рядків для значків за значенням</summary>
        static readonly (string Key, string[] Items)[] Presets =
        {
            ("fpWeekUkMon", new[] { "ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "НД" }),
            ("fpWeekUkSun", new[] { "НД", "ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ" }),
            ("fpWeekEnMon", new[] { "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" }),
            ("fpWeekEnSun", new[] { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }),
            ("fpWeekUkFull", new[] { "Понеділок", "Вівторок", "Середа", "Четвер", "Пʼятниця", "Субота", "Неділя" }),
            ("fpMonthUk", new[] { "СІЧ", "ЛЮТ", "БЕР", "КВІ", "ТРА", "ЧЕР", "ЛИП", "СЕР", "ВЕР", "ЖОВ", "ЛИС", "ГРУ" }),
            ("fpMonthEn", new[] { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }),
            ("fpAmPm", new[] { "AM", "PM" }),
            ("fpNumbers0", Enumerable.Range(0, 60).Select(i => i.ToString()).ToArray()),
            ("fpNumbers1", Enumerable.Range(1, 60).Select(i => i.ToString()).ToArray()),
        };

        FontArtWindow(FaceProject p, XNode res, Generator start)
        {
            project = p; this.res = res;
            var ek = Elements.Of(res, p);
            kind = ek == ElementKind.Digits ? GenKind.Digits : ek == ElementKind.Label ? GenKind.Label : GenKind.Texts;
            slots = ElementFactory.SlotCount(p, res);
            g = start?.Copy() ?? new Generator(kind) { Color = "#FFFFFF", FontSize = 40, Weight = 700, Style = "rounded" };
            g.Kind = kind;
            if (kind == GenKind.Label && string.IsNullOrEmpty(g.Text)) g.Text = S.Get("labelDefault");
            if (kind == GenKind.Texts && g.Texts.Count == 0) g.Texts = DefaultTexts(res.Str("source") ?? "", slots);
            if (start == null) GuessSize();

            Title = S.Get("fontArtTitle");
            Width = 980; Height = 680; MinWidth = 760; MinHeight = 480;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Segoe UI");
            SetResourceReference(BackgroundProperty, "Bg");
            SetResourceReference(ForegroundProperty, "Text");

            var root = new DockPanel { Margin = new Thickness(20, 16, 20, 16) };
            var head = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
            DockPanel.SetDock(head, Dock.Top);
            head.Children.Add(new TextBlock { Text = S.Get("fontArtTitle"), FontSize = 20, FontWeight = FontWeights.SemiBold });
            var sub = new TextBlock { Text = S.Get("fontArtSub", slots), FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) };
            sub.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            head.Children.Add(sub);
            root.Children.Add(head);

            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
            DockPanel.SetDock(buttons, Dock.Bottom);
            var cancel = new Button { Content = S.Get("cancel"), Style = (Style)FindResource("Btn"), IsCancel = true };
            var ok = new Button { Content = S.Get("fontArtApply"), Style = (Style)FindResource("PrimaryBtn"), IsDefault = true, Margin = new Thickness(10, 0, 0, 0) };
            ok.Click += (s, e) => { CommitTexts(); DialogResult = true; };
            buttons.Children.Add(cancel); buttons.Children.Add(ok);
            root.Children.Add(buttons);

            var body = new Grid();
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(380) });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = settings, Padding = new Thickness(0, 0, 14, 0) };
            body.Children.Add(sv);
            var right = new Border { Style = (Style)FindResource("CardBox"), Margin = new Thickness(16, 0, 0, 0), Padding = new Thickness(16) };
            var rp = new DockPanel();
            var ph = new TextBlock { Text = S.Get("howItLooks").ToUpper(), FontSize = 11, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) };
            DockPanel.SetDock(ph, Dock.Top);
            rp.Children.Add(ph);
            previewNote.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            DockPanel.SetDock(previewNote, Dock.Bottom);
            rp.Children.Add(previewNote);
            rp.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = new Border { Background = Brushes.Black, CornerRadius = new CornerRadius(10), Padding = new Thickness(10), Child = preview } });
            right.Child = rp;
            Grid.SetColumn(right, 1);
            body.Children.Add(right);
            root.Children.Add(body);
            Content = root;
            Loaded += (s, e) => Theme.Apply(this);
            Build();
            built = true;
            RenderPreview();
        }

        /// <summary>Розмір шрифту під висоту наявних картинок</summary>
        void GuessSize()
        {
            var t = ElementFactory.MainImages(project, res);
            var src = t == null ? null : t.Tag == "Image" ? t.Str("src") : t.All("Image").FirstOrDefault()?.Str("src");
            var img = src == null ? null : Imaging.Decode(project.File(src));
            if (img != null) g.FontSize = Math.Max(10, Math.Min(160, Math.Round(img.H * 1.25)));
        }

        static List<string> DefaultTexts(string source, int n)
        {
            var l = source.ToLowerInvariant();
            string[] pick = l.Contains("week") ? Presets[0].Items
                          : l.Contains("month") ? Presets[5].Items
                          : l.Contains("ampm") || l.Contains("isam") || l.Contains("ispm") ? Presets[7].Items
                          : Presets[8].Items;
            return Fit(pick, n);
        }

        static List<string> Fit(IEnumerable<string> items, int n)
        {
            var l = items.Take(Math.Max(1, n)).ToList();
            while (l.Count < n) l.Add("");
            return l;
        }

        // MARK: Налаштування

        void Add(UIElement e) => settings.Children.Add(e);
        static KeyValuePair<string, string> P(string k, string v) => new KeyValuePair<string, string>(k, v);

        void Change(Action<Generator> f) { f(g); if (built) { Rebuild(); RenderPreview(); } }

        void Rebuild()
        {
            // перебудовуємо, зберігаючи прокрутку
            var sv = settings.Parent as ScrollViewer;
            double off = sv?.VerticalOffset ?? 0;
            settings.Children.Clear();
            Build();
            sv?.ScrollToVerticalOffset(off);
        }

        void Build()
        {
            if (kind == GenKind.Texts)
            {
                Add(Ui.Header(S.Get("fontArtTexts")));
                var presets = new List<KeyValuePair<string, string>> { P("", S.Get("fpPick")) };
                presets.AddRange(Presets.Select(x => P(x.Key, S.Get(x.Key) + "  ·  " + string.Join(" ", x.Items.Take(Math.Min(4, x.Items.Length))) + "…")));
                Add(Ui.Combo(presets, "", k =>
                {
                    var ps = Presets.FirstOrDefault(x => x.Key == k);
                    if (ps.Items != null) Change(x => x.Texts = Fit(ps.Items, slots));
                }));
                textsBox = new TextBox { Text = string.Join(", ", g.Texts), TextWrapping = TextWrapping.Wrap, AcceptsReturn = false, MinHeight = 56, Margin = new Thickness(0, 8, 0, 0), VerticalContentAlignment = VerticalAlignment.Top };
                textsBox.LostKeyboardFocus += (s, e) => { if (CommitTexts()) { Rebuild(); RenderPreview(); } };
                textsBox.KeyDown += (s, e) => { if (e.Key == Key.Enter) { if (CommitTexts()) { Rebuild(); RenderPreview(); } e.Handled = true; } };
                Add(textsBox);
                Add(Ui.Note(S.Get("fontArtTextsHint", slots)));
            }
            else if (kind == GenKind.Label)
            {
                Add(Ui.Header(S.Get("labelText")));
                var tb = new TextBox { Text = g.Text };
                tb.LostKeyboardFocus += (s, e) => { var t = tb.Text.Trim(); if (t.Length > 0 && t != g.Text) Change(x => x.Text = t); };
                tb.KeyDown += (s, e) => { if (e.Key == Key.Enter) { var t = tb.Text.Trim(); if (t.Length > 0 && t != g.Text) Change(x => x.Text = t); e.Handled = true; } };
                Add(tb);
            }

            Add(Ui.Header(S.Get("font")));
            var combo = new ComboBox { MaxDropDownHeight = 460 };
            var fonts = new List<KeyValuePair<string, string>> { P("", S.Get("fontStyleDefault")) };
            fonts.AddRange(FontLibrary.AllNames().Select(f => P(f, f)));
            var sample = kind == GenKind.Digits ? "   0123456789" : "   " + string.Join(" ", (kind == GenKind.Texts ? g.Texts : new List<string> { g.Text }).Take(3));
            foreach (var kv in fonts)
            {
                var tb = new TextBlock { Text = kv.Value, FontSize = 13 };
                if (kv.Key.Length > 0) { tb.FontFamily = FontLibrary.Family(kv.Key); tb.Text = kv.Value + sample; }
                var it = new ComboBoxItem { Content = tb, Tag = kv.Key };
                combo.Items.Add(it);
                if (kv.Key == g.Font) combo.SelectedItem = it;
            }
            combo.SelectionChanged += (s, e) => { var f = (combo.SelectedItem as ComboBoxItem)?.Tag as string ?? ""; if (f != g.Font) Change(x => x.Font = f); };
            Add(combo);
            var cov = g.Font.Length > 0 ? FontLibrary.Coverage(g.Font) : "";
            Add(Ui.Note(cov.Length > 0 ? S.Get("fontHas", cov) : S.Get("fontHint")));
            var addFont = new TextBlock { Text = S.Get("addFontFile"), FontSize = 12, Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 0, 10) };
            addFont.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
            addFont.MouseLeftButtonUp += (s, e) => { var added = Actions.AddFonts(this); if (added.Count > 0) Change(x => x.Font = added[0]); else Rebuild(); };
            Add(addFont);
            if (g.Font.Length == 0)
                Add(Ui.Chips(S.Get("fontStyle"), new[] { P("rounded", S.Get("stRounded")), P("default", S.Get("stDefault")), P("condensed", S.Get("stCondensed")), P("mono", S.Get("stMono")) },
                             g.Style, v => Change(x => x.Style = v)));
            Add(Ui.Slider(S.Get("fontSize"), g.FontSize, 8, 200, 1, v => Change(x => x.FontSize = v)));
            Add(Ui.Row(S.Get("weight"), Ui.Combo(new[] { 100, 300, 400, 500, 600, 700, 800, 900 }.Select(w => P(w.ToString(), w + " · " + S.Get("w" + w))), g.Weight.ToString(),
                                                 v => Change(x => x.Weight = int.Parse(v))), 190));
            Add(Ui.ColorRow(S.Get("color"), g.Color, h => Change(x => x.Color = h)));

            // набори й ефекти — для будь-якого тексту, не лише цифр
            Add(Ui.Header(S.Get("digitSet")));
            var sets = new WrapPanel();
            foreach (var st in DigitSets.All())
            {
                var b = new Button { Style = (Style)FindResource("Btn"), Padding = new Thickness(6, 4, 6, 4), Margin = new Thickness(0, 0, 6, 6), ToolTip = st.Name };
                var sp = new StackPanel();
                var row = new StackPanel { Orientation = Orientation.Horizontal, Background = Brushes.Black, HorizontalAlignment = HorizontalAlignment.Center };
                var c = st.Style.Copy(); c.FontSize = 20; c.Outline = Math.Min(c.Outline, 1.5);
                foreach (var f in AssetFactory.TextFrames(c, new[] { "1", "2", "3" })) row.Children.Add(new Image { Source = f.ToBitmap(), Height = 20, Stretch = Stretch.Uniform });
                sp.Children.Add(row);
                sp.Children.Add(new TextBlock { Text = st.Name, FontSize = 11, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 3, 0, 0) });
                b.Content = sp;
                var stl = st.Style;
                b.Click += (s, e) => Change(x => x.ApplyStyle(stl));
                sets.Children.Add(b);
            }
            Add(sets);
            var save = new Button { Content = S.Get("dsSave"), Style = (Style)FindResource("Btn"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 10) };
            save.Click += (s, e) =>
            {
                var n = InputBox.Ask(this, S.Get("digitSet"), S.Get("dsName"), S.Get("dsMine") + " " + (DigitSets.User().Count + 1));
                if (n != null) { DigitSets.Add(n, g); Rebuild(); }
            };
            Add(save);
            bool grad = !string.IsNullOrEmpty(g.Color2);
            Add(Ui.Switch(S.Get("gradient"), grad, v => Change(x => x.Color2 = v ? (x.Color.Equals("#FF375F", StringComparison.OrdinalIgnoreCase) ? "#FFD60A" : "#FF375F") : "")));
            if (grad) Add(Ui.ColorRow(S.Get("gradientTo"), g.Color2, h => Change(x => x.Color2 = h)));
            Add(Ui.Slider(S.Get("outline"), g.Outline, 0, 8, 0.5, v => Change(x => x.Outline = v)));
            if (g.Outline > 0) Add(Ui.ColorRow(S.Get("outlineColor"), g.OutlineColor, h => Change(x => x.OutlineColor = h)));
            Add(Ui.Slider(S.Get("shadowX"), g.ShadowX, -8, 8, 1, v => Change(x => x.ShadowX = v)));
            Add(Ui.Slider(S.Get("shadowY"), g.ShadowY, -8, 8, 1, v => Change(x => x.ShadowY = v)));
            if (g.ShadowX != 0 || g.ShadowY != 0) Add(Ui.ColorRow(S.Get("shadowColor"), g.ShadowColor, h => Change(x => x.ShadowColor = h)));
            Add(Ui.Slider(S.Get("letterWidth"), g.WidthPct, 50, 150, 1, v => Change(x => x.WidthPct = v)));
        }

        bool CommitTexts()
        {
            if (textsBox == null) return false;
            var l = textsBox.Text.Split(',').Select(t => t.Trim()).ToList();
            var fit = Fit(l, slots);
            if (fit.SequenceEqual(g.Texts)) return false;
            g.Texts = fit;
            return true;
        }

        void RenderPreview()
        {
            preview.Children.Clear();
            List<RgbaImage> frames;
            List<string> captions;
            switch (kind)
            {
                case GenKind.Digits: frames = AssetFactory.DigitFrames(g); captions = Enumerable.Range(0, 10).Select(i => i.ToString()).ToList(); break;
                case GenKind.Label: { var li = AssetFactory.LabelImage(g); frames = li == null ? new List<RgbaImage>() : new List<RgbaImage> { li }; captions = new List<string> { "" }; break; }
                default:
                {
                    frames = AssetFactory.TextFrames(g, g.Texts);
                    // при якому значенні показується картинка (для значків за значенням)
                    var prm = res.All("Param");
                    captions = Enumerable.Range(0, frames.Count).Select(i => i < prm.Count ? S.Get("fontArtWhen", prm[i].Int("value")) : "#" + (i + 1)).ToList();
                    break;
                }
            }
            for (int i = 0; i < frames.Count; i++)
            {
                var sp = new StackPanel { Margin = new Thickness(6) };
                var img = new Image { Source = frames[i].ToBitmap(), Stretch = Stretch.None };
                RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.NearestNeighbor);
                sp.Children.Add(img);
                if (captions[i].Length > 0)
                    sp.Children.Add(new TextBlock { Text = captions[i], FontSize = 10, Foreground = Brushes.Gray, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0) });
                preview.Children.Add(sp);
            }
            var w = frames.Count > 0 ? frames[0].W : 0; var h = frames.Count > 0 ? frames[0].H : 0;
            previewNote.Text = S.Get("fontArtNote", frames.Count, w, h);
        }

        /// <summary>Відкрити вікно для елемента; true — картинки перемальовано (одна зміна в історії)</summary>
        public static bool Show(Window owner, FaceProject p, XNode res)
        {
            var name = res.Str("name") ?? "";
            var start = p.Meta.Gen(name);
            if (start != null && !start.Drawn) start = null;
            var w = new FontArtWindow(p, res, start) { Owner = owner };
            if (w.ShowDialog() != true) return false;
            var g = w.g.Copy();
            p.Edit(pr =>
            {
                ElementFactory.Regenerate(pr, name, g);
                ColorVariants.Refresh(pr, res);
            });
            return true;
        }
    }
}
