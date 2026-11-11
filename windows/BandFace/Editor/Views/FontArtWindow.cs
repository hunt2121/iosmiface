// SPDX-License-Identifier: MIT
// «Намалювати шрифтом»: окреме вікно, що перемальовує ВСІ картинки елемента одним шрифтом —
// цифри, дні тижня, місяці, AM/PM, будь-які значки за значенням (свій рядок на кожну картинку), напис.
// Ліворуч — екран браслета в масштабі 1:1 з усім циферблатом (видно справжній розмір), праворуч — налаштування:
// шрифт і його накреслення, «Стиль» (лише оформлення), заливка, обведення, розкладка, тінь і одна «Форма» навколо всього.

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
        /// <summary>Екран браслета в масштабі 1:1 (1 піксель браслета = 1 точка Windows) з усім циферблатом</summary>
        readonly Image screen = new Image { Stretch = Stretch.Fill };
        /// <summary>Усі картинки елемента (для написів за значенням — кожен рядок)</summary>
        readonly WrapPanel frames = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
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
            // відстань між цифрами — це «space» числа: показуємо ту, що вже стоїть
            if (kind == GenKind.Digits && res.Has("space")) g.Tracking = (sbyte)(byte)res.Int("space");
            if (start == null) GuessSize();
            FitWeight();

            var dev = p.Meta.Device;
            Title = S.Get("fontArtTitle");
            Width = 900; Height = 780; MinWidth = 760; MinHeight = 600;
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
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            // ліворуч: екран браслета 1:1 (закруглений, як справжній), під ним — усі картинки елемента
            var left = new StackPanel { Width = dev.Width + 8 };
            var ph = new TextBlock { Text = S.Get("howItLooks").ToUpper(), FontSize = 11, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) };
            ph.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            left.Children.Add(ph);
            screen.Width = dev.Width; screen.Height = dev.Height;
            screen.Clip = new RectangleGeometry(new Rect(0, 0, dev.Width, dev.Height), dev.Corner, dev.Corner);
            RenderOptions.SetBitmapScalingMode(screen, BitmapScalingMode.HighQuality);
            left.Children.Add(new Border
            {
                Width = dev.Width + 8, Height = dev.Height + 8, Background = Brushes.Black, Padding = new Thickness(4),
                CornerRadius = new CornerRadius(dev.Corner + 4), Child = screen, HorizontalAlignment = HorizontalAlignment.Left,
            });
            previewNote.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            left.Children.Add(previewNote);
            if (kind == GenKind.Texts) left.Children.Add(frames);
            var leftScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = left, Padding = new Thickness(0, 0, 8, 0) };
            body.Children.Add(leftScroll);

            var sv = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = settings, Padding = new Thickness(0, 0, 14, 0), Margin = new Thickness(20, 0, 0, 0), CanContentScroll = false };
            Grid.SetColumn(sv, 1);
            body.Children.Add(sv);
            root.Children.Add(body);
            Content = root;
            // темний заголовок вікна ставиться до показу — інакше Windows лишає його білим до перемикання вікон
            SourceInitialized += (s, e) => Theme.Apply(this);
            Loaded += (s, e) => { Theme.Apply(this); RenderPreview(); };
            Build();
            built = true;
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

        void Change(Action<Generator> f) { f(g); FitWeight(); if (built) { Rebuild(); RenderPreview(); } }

        void Rebuild()
        {
            // перебудовуємо, зберігаючи прокрутку
            var sv = settings.Parent as ScrollViewer;
            double off = sv?.VerticalOffset ?? 0;
            settings.Children.Clear();
            Build();
            sv?.ScrollToVerticalOffset(off);
        }

        /// <summary>Товщини, які справді є у вибраному шрифті (без штучного «жирного» від Windows)</summary>
        List<int> Faces()
        {
            if (string.IsNullOrEmpty(g.Font)) return new List<int>();
            try
            {
                return FontLibrary.Family(g.Font).FamilyTypefaces
                    .Where(t => t.Style == FontStyles.Normal && t.Stretch == FontStretches.Normal)
                    .Select(t => t.Weight.ToOpenTypeWeight()).Distinct().OrderBy(w => w).ToList();
            }
            catch (Exception) { return new List<int>(); }
        }

        /// <summary>Для свого шрифту товщина — лише одна з наявних у ньому (найближча)</summary>
        void FitWeight()
        {
            var f = Faces();
            if (f.Count > 0 && !f.Contains(g.Weight)) g.Weight = f.OrderBy(w => Math.Abs(w - g.Weight)).First();
        }

        static string WeightName(int w)
        {
            int k = Math.Max(1, Math.Min(9, (int)Math.Round(w / 100.0))) * 100;
            return S.Get("w" + k);
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

            // Шрифт: сімейство, його накреслення (лише наявні), розмір
            Add(Ui.Header(S.Get("faFont")));
            var combo = new ComboBox { MaxDropDownHeight = 460 };
            var fonts = new List<KeyValuePair<string, string>> { P("", S.Get("fontStyleDefault")) };
            fonts.AddRange(FontLibrary.AllNames().Select(f => P(f, f)));
            var sample = "   " + Sample();
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
            {
                // вбудований шрифт: накреслення й товщина, як в iOS
                Add(Ui.Chips(S.Get("fontFaces"), new[] { P("rounded", S.Get("stRounded")), P("default", S.Get("stDefault")), P("condensed", S.Get("stCondensed")), P("mono", S.Get("stMono")) },
                             g.Style, v => Change(x => x.Style = v)));
                Add(Ui.Chips(S.Get("weight"), new[] { 300, 400, 500, 600, 700, 900 }.Select(w => P(w.ToString(), WeightName(w))), g.Weight.ToString(), v => Change(x => x.Weight = int.Parse(v))));
            }
            else
            {
                // свій шрифт: лише ті накреслення, що є в цьому сімействі
                var faces = Faces();
                if (faces.Count > 1)
                    Add(Ui.Chips(S.Get("fontFaces"), faces.Select(w => P(w.ToString(), WeightName(w))), g.Weight.ToString(), v => Change(x => x.Weight = int.Parse(v))));
            }
            Add(Ui.Slider(S.Get("fontSize"), g.FontSize, 8, 200, 1, v => Change(x => x.FontSize = v)));

            // Стиль: лише оформлення — шрифт, накреслення й розмір лишаються вибраними
            Add(Ui.Header(S.Get("fontStyle")));
            Add(StyleGrid());

            FontEffects.Build(e => Add(e), g, ch => Change(ch));

            // Форма: одна фігура навколо всього напису / числа
            Add(Ui.Header(S.Get("shapeHeader")));
            Add(Ui.Chips(S.Get("shapeFigure"), new[] { P("", S.Get("shapeNone")), P("capsule", S.Get("badgeCapsule")), P("square", S.Get("shapeRect")), P("circle", S.Get("badgeCircle")) },
                         g.Badge ?? "", v => Change(x => x.Badge = v)));
            if (!string.IsNullOrEmpty(g.Badge)) Add(Ui.ColorRow(S.Get("shapeColor"), g.BadgeColor, h => Change(x => x.BadgeColor = h)));
            Add(Ui.Note(S.Get(kind == GenKind.Digits ? "shapeHintDigits" : "shapeHintText")));
        }

        /// <summary>Зразок у вибраному шрифті: цифри або перші написи</summary>
        string Sample()
        {
            switch (kind)
            {
                case GenKind.Digits: return "0123456789";
                case GenKind.Label: return g.Text;
                default: return string.Join(" ", g.Texts.Where(t => t.Length > 0).Take(3));
            }
        }

        /// <summary>Плитки стилів, намальовані вибраним шрифтом; правий клік — «Видалити стиль»; остання — «Зберегти поточний стиль»</summary>
        FrameworkElement StyleGrid()
        {
            var grid = new System.Windows.Controls.Primitives.UniformGrid { Columns = 4, Margin = new Thickness(0, 0, 0, 10) };
            string text = kind == GenKind.Digits ? "12" : kind == GenKind.Label ? g.Text : (g.Texts.FirstOrDefault(t => t.Length > 0) ?? "Aa");
            if (text.Length > 6) text = text.Substring(0, 6);
            foreach (var st in DigitSets.All())
            {
                var c = g.Copy(); c.ApplyLook(st.Style); c.Badge = ""; c.FontSize = 22; c.Kind = GenKind.Texts;
                var b = new Button { Style = (Style)FindResource("Btn"), Height = double.NaN, Padding = new Thickness(4, 6, 4, 5), Margin = new Thickness(0, 0, 6, 6), ToolTip = st.Name, HorizontalContentAlignment = HorizontalAlignment.Stretch };
                var sp = new StackPanel();
                var plate = new Border { Background = Brushes.Black, CornerRadius = new CornerRadius(6), Height = 36, Margin = new Thickness(0, 0, 0, 4) };
                var f = AssetFactory.TextFrames(c, new[] { text }).FirstOrDefault();
                if (f != null)
                {
                    var img = new Image { Source = f.ToBitmap(), Stretch = Stretch.Uniform, MaxHeight = 28, MaxWidth = 64, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                    RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
                    plate.Child = img;
                }
                sp.Children.Add(plate);
                // назва — в один рядок, задовга обрізається трикрапкою
                sp.Children.Add(new TextBlock { Text = st.Name, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, HorizontalAlignment = HorizontalAlignment.Center });
                b.Content = sp;
                var set = st;
                b.Click += (s, e) => Change(x => x.ApplyLook(set.Style));
                var cm = new ContextMenu();
                Ui.MenuAdd(cm, S.Get("styleDelete"), "\uE74D", () => { DigitSets.Remove(set); Rebuild(); }, danger: true);
                b.ContextMenu = cm;
                grid.Children.Add(b);
            }
            var root = new StackPanel();
            root.Children.Add(grid);
            var save = new Button { Content = S.Get("styleSave"), Style = (Style)FindResource("Btn"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 4) };
            save.Click += (s, e) =>
            {
                var n = InputBox.Ask(this, S.Get("fontStyle"), S.Get("styleName"), S.Get("dsMine") + " " + (DigitSets.User().Count + 1));
                if (!string.IsNullOrWhiteSpace(n)) { DigitSets.Add(n.Trim(), g); Rebuild(); }
            };
            root.Children.Add(save);
            root.Children.Add(Ui.Note(S.Get("styleHint")));
            return root;
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

        /// <summary>Циферблат з перемальованим елементом — на копії проєкту, сам проєкт не змінюється до «Намалювати»</summary>
        void RenderPreview()
        {
            var name = res.Str("name") ?? "";
            var copy = new FaceProject(project.Id, null, Xml.Parse(Xml.Print(project.Root)), new Dictionary<string, byte[]>(project.Files), project.Meta.Copy());
            ElementFactory.Regenerate(copy, name, g.Copy());
            double dpi = 1;
            try { dpi = VisualTreeHelper.GetDpi(this).DpiScaleX; } catch (Exception) { }
            screen.Source = new FaceRenderer(copy) { Live = true }.Render(0, Math.Max(1, dpi)).Image;

            List<RgbaImage> fr;
            switch (kind)
            {
                case GenKind.Digits: fr = AssetFactory.DigitFrames(g); break;
                case GenKind.Label: { var li = AssetFactory.LabelImage(g); fr = li == null ? new List<RgbaImage>() : new List<RgbaImage> { li }; break; }
                default: fr = AssetFactory.TextFrames(g, g.Texts); break;
            }
            var w = fr.Count > 0 ? fr[0].W : 0; var h = fr.Count > 0 ? fr[0].H : 0;
            previewNote.Text = S.Get("fontArtNote", fr.Count, w, h);
            if (kind != GenKind.Texts) return;
            // написи за значенням: кожна картинка з підписом, з якого значення вона показується
            frames.Children.Clear();
            var prm = res.All("Param");
            for (int i = 0; i < fr.Count; i++)
            {
                var sp = new StackPanel { Margin = new Thickness(0, 0, 8, 8) };
                var img = new Image { Source = fr[i].ToBitmap(), Stretch = Stretch.Uniform, MaxWidth = dpiSafe(fr[i].W), MaxHeight = 40, HorizontalAlignment = HorizontalAlignment.Center };
                sp.Children.Add(new Border { Background = Brushes.Black, CornerRadius = new CornerRadius(6), Padding = new Thickness(4), Child = img });
                sp.Children.Add(new TextBlock { Text = i < prm.Count ? S.Get("fontArtWhen", prm[i].Int("value")) : "#" + (i + 1), FontSize = 10, Foreground = Brushes.Gray, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 3, 0, 0) });
                frames.Children.Add(sp);
            }
        }

        static double dpiSafe(int w) => Math.Max(8, Math.Min(200, w));
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
