// SPDX-License-Identifier: MIT
// Панель властивостей: без вибору — циферблат (назва, ID, пристрій, фон, екрани, кольори, розмір файла);
// з вибором — елемент (дані, вигляд, колір, кольорові варіанти, правило показу, дія натискання, позиція).

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using BandFace.Faces;
using Microsoft.Win32;

namespace BandFace.Creator
{
    public partial class EditorView
    {
        bool focusName;
        int inspectorToken;
        /// <summary>Розмір .bin рахується один раз на версію проєкту</summary>
        string sizeKey, sizeText;

        void Add(UIElement e) => InspectorPanel.Children.Add(e);
        void EditRes(Action a) => project.Edit(_ => a());
        static KeyValuePair<string, string> P(string k, string v) => Ui.P(k, v);

        void BuildInspector()
        {
            double offset = InspectorScroll.VerticalOffset;
            var keep = selected;
            InspectorPanel.Children.Clear();
            inspectorToken++;
            if (project == null) return;
            if (selected != null && project.Layouts(theme).Contains(selected)) BuildElement(selected);
            else BuildFace();
            // після зміни властивості панель лишається на тому ж місці
            if (keep == selected) InspectorScroll.ScrollToVerticalOffset(offset); else InspectorScroll.ScrollToTop();
        }

        TextBlock Title(string t) => new TextBlock { Text = t, FontSize = 20, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 6, 0, 2), TextTrimming = TextTrimming.CharacterEllipsis };

        // MARK: Циферблат

        const int MaxNameBytes = 63;

        void BuildFace()
        {
            Add(Title(S.Get("face")));
            Add(Ui.Note(S.Get("faceHint")));

            Add(Ui.Header(S.Get("name")));
            var name = new TextBox { Text = project.Name };
            var bytes = Ui.Note("");
            void Count()
            {
                int n = Encoding.UTF8.GetByteCount(name.Text);
                bytes.Text = S.Get("nameBytes", n, MaxNameBytes);
                bytes.Foreground = n > MaxNameBytes ? (Brush)FindResource("Err") : (Brush)FindResource("Sub");
            }
            void CommitName()
            {
                var t = name.Text.Trim();
                if (t == project.Name || Encoding.UTF8.GetByteCount(t) > MaxNameBytes) return;
                project.Edit(p => p.Root.Set("name", t));
            }
            name.TextChanged += (s, e) => Count();
            name.KeyDown += (s, e) => { if (e.Key == Key.Enter) { CommitName(); e.Handled = true; } };
            name.LostKeyboardFocus += (s, e) => CommitName();
            Count();
            Add(name);
            Add(bytes);
            if (focusName)
            {
                focusName = false;
                Dispatcher.BeginInvoke(new Action(() => { name.Focus(); name.SelectAll(); }), DispatcherPriority.Input);
            }

            Add(Ui.Header(S.Get("faceId")));
            var idRow = new Grid { Margin = new Thickness(0, 0, 0, 4) };
            idRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            idRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            // ID можна ввести вручну: рівно 9 цифр (як у нових циферблатів), перша не 0
            var idBox = new TextBox { Text = project.Root.Str("id") ?? "", MaxLength = 9, FontFamily = new FontFamily("Consolas"), FontSize = 14, Margin = new Thickness(0, 0, 8, 0), VerticalContentAlignment = VerticalAlignment.Center };
            void CommitId()
            {
                var t = idBox.Text.Trim();
                if (t == (project.Root.Str("id") ?? "")) return;
                if (System.Text.RegularExpressions.Regex.IsMatch(t, "^[1-9][0-9]{8}$")) project.Edit(p => p.Root.Set("id", t));
                else { MessageBox.Show(Owner, S.Get("idInvalid"), "BandFace", MessageBoxButton.OK, MessageBoxImage.Warning); idBox.Text = project.Root.Str("id") ?? ""; }
            }
            idBox.KeyDown += (s, e) => { if (e.Key == Key.Enter) { CommitId(); e.Handled = true; } };
            // лише цифри — і при наборі, і при вставці
            idBox.PreviewTextInput += (s, e) => { if (!e.Text.All(char.IsDigit)) e.Handled = true; };
            DataObject.AddPastingHandler(idBox, (s, e) =>
            {
                var txt = e.DataObject.GetData(typeof(string)) as string ?? "";
                if (!txt.Trim().All(char.IsDigit)) e.CancelCommand();
            });
            idBox.LostKeyboardFocus += (s, e) => CommitId();
            idRow.Children.Add(idBox);
            var newId = new Button { Content = S.Get("newId"), Style = (Style)FindResource("Btn") };
            newId.Click += (s, e) => project.Edit(p => p.Root.Set("id", ProjectStore.NewFaceId()));
            Grid.SetColumn(newId, 1);
            idRow.Children.Add(newId);
            Add(idRow);
            Add(Ui.Note(S.Get("faceIdHint")));

            Add(Ui.Header(S.Get("device")));
            Add(Ui.Combo(DeviceProfile.All.Select(d => P(d.Id, d.Title)), project.Meta.Device.Id,
                         id => project.Edit(p => p.Meta.Device = DeviceProfile.ById(id))));
            Add(Ui.Note(S.Get("deviceHint")));

            Add(Ui.Header(S.Get("background")));
            var th = project.Theme(theme);
            Add(Ui.ColorRow(S.Get("bgColor"), th?.Str("bgColor") ?? "#000000", h => project.Edit(p => p.Theme(theme)?.Set("bgColor", h))));
            Add(Ui.Button(S.Get("bgImage") + "…", AddBackground));

            Add(Ui.Header(S.Get("screens")));
            if (project.Themes.Count < 2)
            {
                Add(Ui.Note(S.Get("aodHint")));
                Add(Ui.Button(S.Get("addAod"), () =>
                {
                    project.Edit(p =>
                    {
                        var t = p.Root.Add("Theme");
                        t.Set("type", "AOD").Set("name", "").Set("bgColor", "#000000");
                        // у режимі «завжди на екрані» — лише час, без секундних і кольорових деталей
                        foreach (var l in p.Layouts(0)) if (Elements.Of(p.ElementOf(l)) == ElementKind.Digits) t.Kids.Add(l.Copy());
                    });
                    ShowTheme(1);
                }));
            }
            else
            {
                Add(Ui.Note(theme == 0 ? S.Get("nowMain") : S.Get("nowAod")));
                Add(Ui.Button(theme == 0 ? S.Get("goAod") : S.Get("goMain"), () => ShowTheme(theme == 0 ? 1 : 0)));
                // приглушення всього екрана AOD — чорний напівпрозорий шар поверх
                Add(Ui.Slider(S.Get("aodDim") + ", %", AodDim.Percent(project), 0, 90, 1, v =>
                {
                    int pc = (int)Math.Round(v);
                    if (pc != AodDim.Percent(project)) project.Edit(p => AodDim.Set(p, pc));
                }));
                Add(Ui.Note(S.Get("aodDimHint")));
                Add(Ui.Button(S.Get("deleteAod"), () =>
                {
                    if (MessageBox.Show(Owner, S.Get("deleteAodAsk"), "BandFace", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
                    theme = 0;
                    project.Edit(p => ElementFactory.DeleteTheme(p, 1));
                }, "DangerBtn"));
            }

            BuildColorVariants();

            Add(Ui.Header(S.Get("file")));
            var size = Ui.Note(S.Get("sizeCounting"));
            Add(size);
            Add(Ui.Button(S.Get("exportBin") + "…", () => Actions.ExportBin(Owner, project), "PrimaryBtn"));
            int token = inspectorToken;
            var key = project.Id + "#" + project.Revision;
            if (sizeKey == key) size.Text = sizeText;
            else
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (token != inspectorToken) return;
                    try
                    {
                        var r = project.Compile();
                        sizeText = S.Get("sizeIs", (r.Item1.Length + 1023) / 1024);
                    }
                    catch (Exception ex) { sizeText = S.Get("buildFail", ex.Message); }
                    sizeKey = key;
                    size.Text = sizeText;
                }), DispatcherPriority.ContextIdle);

            Add(Ui.Header(S.Get("keys")));
            Add(Ui.Note(S.Get("keysHint")));
        }

        static readonly string[] Suggested = { "#FF9500", "#30B455", "#0A84FF", "#FF375F", "#BF5AF2", "#FFD60A", "#64D2FF", "#FF453A", "#AC8E68", "#8E8E93" };

        void BuildColorVariants()
        {
            Add(Ui.Header(S.Get("faceColors")));
            var cols = ColorVariants.Colors(project);
            if (cols.Count < 2)
            {
                Add(Ui.Note(S.Get("cvIntro")));
                Add(Ui.Button(S.Get("cvEnable"), () =>
                {
                    var b = FirstGeneratorColor() ?? "#FFFFFF";
                    var next = Suggested.FirstOrDefault(c => c != b) ?? "#FF9500";
                    variant = 0;
                    project.Edit(p => ColorVariants.Enable(p, b, next));
                }));
                return;
            }
            for (int i = 0; i < cols.Count; i++)
            {
                int idx = i;
                var row = new Grid();
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.Children.Add(Ui.ColorRow(i == 0 ? S.Get("baseColor") : S.Get("colorN", i), cols[i], h =>
                {
                    var list = ColorVariants.Colors(project);
                    if (idx >= list.Count || list.Contains(ColorVariants.Normalize(h))) return;
                    list[idx] = h;
                    project.Edit(p => ColorVariants.SetColors(p, list));
                }));
                if (i > 0)
                {
                    var del = Ui.Icon("", S.Get("deleteColor"), () =>
                    {
                        var list = ColorVariants.Colors(project);
                        list.RemoveAt(idx);
                        variant = 0;
                        project.Edit(p => ColorVariants.SetColors(p, list));
                    });
                    del.Margin = new Thickness(8, 0, 0, 8);
                    del.Foreground = (Brush)FindResource("Err");
                    Grid.SetColumn(del, 1);
                    row.Children.Add(del);
                }
                Add(row);
            }
            if (cols.Count < ColorVariants.MaxColors)
                Add(Ui.Button("+ " + S.Get("addColor"), () =>
                {
                    var list = ColorVariants.Colors(project);
                    list.Add(Suggested.FirstOrDefault(c => !list.Contains(c)) ?? "#FFFFFF");
                    variant = list.Count - 1;
                    project.Edit(p => ColorVariants.SetColors(p, list));
                }));
            Add(Ui.Note(S.Get("cvHowTo")));
            Add(Ui.Button(S.Get("cvDisable"), () => { variant = 0; project.Edit(ColorVariants.Disable); }, "DangerBtn"));
        }

        string FirstGeneratorColor()
        {
            foreach (var l in project.Layouts(0))
            {
                var g = project.Meta.Gen(project.ResourceRef(l.Str("ref"))?.Str("name"));
                if (g != null && g.Drawn) return ColorVariants.Normalize(g.Color);
            }
            return null;
        }

        // MARK: Елемент

        void BuildElement(XNode layout)
        {
            var res = project.ElementOf(layout);
            var kind = Elements.Of(res, project);
            var resName = res?.Str("name") ?? "";
            var gen = project.Meta.Gen(resName);

            var head = new Grid();
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var titles = new StackPanel();
            titles.Children.Add(Title(Elements.Title(kind)));
            titles.Children.Add(new TextBlock { Text = resName, FontSize = 12, Foreground = (Brush)FindResource("Sub"), TextTrimming = TextTrimming.CharacterEllipsis });
            head.Children.Add(titles);
            var acts = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            acts.Children.Add(Ui.Icon("", S.Get("duplicate") + " (Ctrl+D)", DuplicateSelected));
            var del = Ui.Icon("", S.Get("delete") + " (Delete)", DeleteSelected);
            del.Foreground = (Brush)FindResource("Err");
            del.Margin = new Thickness(6, 0, 0, 0);
            acts.Children.Add(del);
            Grid.SetColumn(acts, 1);
            head.Children.Add(acts);
            Add(head);
            if (res == null) { Add(Ui.Note(S.Get("missingRes"))); BuildPosition(layout); return; }
            if (kind != ElementKind.Slot) slotWidget = null;
            // віджет і слот — власні налаштування (макет погоджено 9 листопада)
            if (kind == ElementKind.Widget && WidgetSlots.IsUserWidget(project, res))
            {
                WidgetSection(res, new Point(layout.Int("x"), layout.Int("y")), layout);
                BuildPosition(layout);
                return;
            }
            if (kind == ElementKind.Slot)
            {
                SlotSection(res, layout);
                BuildPosition(layout);
                return;
            }

            if (res.Has("source"))
            {
                Add(Ui.Header(S.Get("data")));
                var src = res.Str("source");
                var btn = new Button { Style = (Style)FindResource("Btn"), HorizontalContentAlignment = HorizontalAlignment.Stretch, Height = double.NaN, Padding = new Thickness(10, 8, 10, 8), Margin = new Thickness(0, 0, 0, 8) };
                // значок групи · назва (або технічне імʼя) і підпис · стрілка
                btn.Content = SourceRow(src, true);
                btn.HorizontalAlignment = HorizontalAlignment.Stretch;
                btn.Click += (s, e) =>
                {
                    var n = SourcePicker.Pick(Owner, src);
                    if (n != null && n != src) EditRes(() => res.Set("source", n));
                };
                Add(btn);
                DemoSection(src);
            }

            Add(Ui.Header(S.Get("look")));
            switch (kind)
            {
                case ElementKind.Digits: DigitsLook(layout, res, gen); break;
                case ElementKind.Label: LabelLook(res, gen); break;
                case ElementKind.Text: Add(Ui.Note(S.Get("textUnsupported"))); break;
                case ElementKind.Pointer: case ElementKind.Arc: case ElementKind.Line: GaugeLook(res, kind, gen); break;
                case ElementKind.Animation:
                    Add(Ui.Slider(S.Get("interval"), res.Int("interval", 100), 30, 2000, 10, v => EditRes(() => res.Set("interval", (int)v))));
                    Add(Ui.NumberRow(S.Get("repeats"), res.Int("repeatCount"), v => EditRes(() => res.Set("repeatCount", v)), 0, 1000));
                    Add(Ui.Button(S.Get("replaceFrames") + "…", () =>
                    {
                        var imgs = PickImages(true, 1000);
                        var arr = project.ResourceRef(res.Str("ref"));
                        if (imgs.Count == 0 || arr == null) return;
                        var f0 = Imaging.Fit(imgs[0], 200);
                        var frames = imgs.Select(i => Imaging.Contain(i, f0.W, f0.H)).ToList();
                        project.Edit(p =>
                        {
                            res.Remove("ref");
                            ElementFactory.Collect(p, "@" + (arr.Str("name") ?? ""));
                            res.Set("ref", "@" + ElementFactory.AddFrames(p, frames, "frames"));
                        });
                    }));
                    break;
                case ElementKind.Values:
                {
                    Add(Ui.Note(S.Get("valuesHint")));
                    var prm = res.All("Param");
                    for (int i = 0; i < prm.Count; i++)
                    {
                        var pr = prm[i];
                        Add(Ui.NumberRow(S.Get("threshold", i + 1), pr.Int("value"), v => EditRes(() => pr.Set("value", v))));
                    }
                    if (gen != null && gen.Kind == GenKind.Texts)
                        Add(Ui.ColorRow(S.Get("color"), gen.Color, h => Regen(res.Str("name") ?? "", gen, g => g.Color = h)));
                    Add(Ui.Button(S.Get("replaceImages") + "…", () =>
                    {
                        var imgs = PickImages(true, 200);
                        if (imgs.Count > 0) project.Edit(p => { ElementFactory.ReplaceValueImages(p, res, imgs); p.Meta.Generators.Remove(res.Str("name") ?? ""); });
                    }));
                    break;
                }
                case ElementKind.Image:
                    // заміна картинки — у блоці «Зображення» нижче
                    if (res.Tag != "Image") Add(Ui.Note(S.Get("framesNote")));
                    break;
                default:
                    Add(Ui.Note(S.Get("otherNote")));
                    break;
            }

            BuildImageActions(res);
            BuildVariantRow(res);

            if (res.Tag.StartsWith("DataItem", StringComparison.Ordinal))
            {
                Add(Ui.Header(S.Get("showWhen")));
                Add(Ui.Chips(null, new[] { P("alwaysShow", S.Get("rrAlways")), P("hideWhenOutRange", S.Get("rrData")), P("hideWhenUnitMismatch", S.Get("rrUnit")) },
                             res.Str("renderRule") ?? "alwaysShow", v => EditRes(() => res.Set("renderRule", v))));
            }

            Add(Ui.Header(S.Get("tap")));
            var cur = ElementFactory.TapApp(project, layout) ?? "";
            var apps = new List<KeyValuePair<string, string>> { P("", S.Get("tapNone")) };
            apps.AddRange(ElementFactory.Apps.Select(a => P(a, S.App(a))).OrderBy(x => x.Value, StringComparer.CurrentCultureIgnoreCase));
            int t0 = theme;
            Add(Ui.Row(S.Get("tapOpens"), Ui.Combo(apps, cur, a => project.Edit(p => ElementFactory.SetTapApp(p, layout, t0, a.Length == 0 ? null : a))), 190));

            BuildPosition(layout);
        }

        void Regen(string name, Generator gen, Action<Generator> change)
        {
            var g = gen.Copy();
            change(g);
            project.Edit(p => ElementFactory.Regenerate(p, name, g));
        }

        // MARK: Цифри

        /// <summary>Рядок джерела даних: плитка зі значком групи, назва й технічне імʼя (якщо назва є), стрілка › (для кнопки)</summary>
        /// <summary>«Значення для перегляду»: однакове для всіх елементів з цим джерелом, на браслет не записується.
        /// Час і дата — свої або справжні (з комп'ютера).</summary>
        void DemoSection(string src)
        {
            var demo = project.Meta.Demo;
            if (src.StartsWith("time"))
            {
                bool real = demo.RealTime;
                if (!demo.TryTime(out var h, out var m)) { h = 10; m = 24; }
                Add(Ui.Chips(S.Get("demoTime"), new[] { Ui.P("own", S.Get("demoOwn")), Ui.P("real", S.Get("demoReal")) }, real ? "real" : "own",
                    k => project.Edit(p => p.Meta.Demo.RealTime = k == "real"), 2));
                if (!real)
                {
                    Add(Ui.NumberRow(S.Get("demoHours"), h, v => project.Edit(p => p.Meta.Demo.Time = $"{v:00}:{m:00}"), 0, 23));
                    Add(Ui.NumberRow(S.Get("demoMinutes"), m, v => project.Edit(p => p.Meta.Demo.Time = $"{h:00}:{v:00}"), 0, 59));
                }
                Add(Ui.Note(S.Get(real ? "demoRealTimeHint" : "demoTimeHint")));
                return;
            }
            if (src.StartsWith("date"))
            {
                bool real = demo.RealDate;
                if (!demo.TryDate(out var d, out var mo, out var y)) { d = 30; mo = 5; y = 2026; }
                Add(Ui.Chips(S.Get("demoDate"), new[] { Ui.P("own", S.Get("demoOwn")), Ui.P("real", S.Get("demoReal")) }, real ? "real" : "own",
                    k => project.Edit(p => p.Meta.Demo.RealDate = k == "real"), 2));
                if (!real)
                {
                    string Fmt(int dd, int mm, int yy) => $"{yy:0000}-{mm:00}-{dd:00}";
                    Add(Ui.NumberRow(S.Get("demoDay"), d, v => project.Edit(p => p.Meta.Demo.Date = Fmt(Math.Min(v, DateTime.DaysInMonth(y, mo)), mo, y)), 1, 31));
                    Add(Ui.NumberRow(S.Get("demoMonth"), mo, v => project.Edit(p => p.Meta.Demo.Date = Fmt(Math.Min(d, DateTime.DaysInMonth(y, v)), v, y)), 1, 12));
                    Add(Ui.NumberRow(S.Get("demoYear"), y, v => project.Edit(p => p.Meta.Demo.Date = Fmt(Math.Min(d, DateTime.DaysInMonth(v, mo)), mo, v)), 2000, 2099));
                }
                Add(Ui.Note(S.Get(real ? "demoRealDateHint" : "demoDateHint")));
                return;
            }
            var r = SampleData.DemoRange(src);
            int cur = SampleData.Value(src, false, demo);
            Add(Ui.Slider(S.Get("demoValue"), cur, Math.Min(r.Min, cur), Math.Max(r.Max, cur), 1, v => project.Edit(p => p.Meta.Demo.Values[src] = (int)Math.Round(v))));
            var note = Ui.Note(S.Get("demoHint"));
            if (demo.Values.ContainsKey(src))
            {
                var reset = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run(S.Get("demoDefault")));
                reset.Click += (s, e) => project.Edit(p => p.Meta.Demo.Values.Remove(src));
                note.Inlines.Add(new System.Windows.Documents.Run(" "));
                note.Inlines.Add(reset);
            }
            Add(note);
        }

        internal static FrameworkElement SourceRow(string src, bool chevron)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var tile = new Border { Width = 30, Height = 30, CornerRadius = new CornerRadius(7), Margin = new Thickness(0, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center };
            tile.SetResourceReference(Border.BackgroundProperty, "ChipBg");
            var glyph = new TextBlock { Text = SampleData.GroupGlyph(SampleData.GroupOf(src)), FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 15, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            glyph.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
            tile.Child = glyph;
            g.Children.Add(tile);
            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(new TextBlock { Text = SampleData.Title(src), FontSize = 13, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
            if (SampleData.HasTitle(src))
            {
                var id = new TextBlock { Text = src, FontSize = 11, FontFamily = new FontFamily("Cascadia Mono, Consolas"), TextTrimming = TextTrimming.CharacterEllipsis };
                id.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
                texts.Children.Add(id);
            }
            Grid.SetColumn(texts, 1); g.Children.Add(texts);
            if (chevron)
            {
                var ch = new TextBlock { Text = "\uE76C", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
                ch.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
                Grid.SetColumn(ch, 2); g.Children.Add(ch);
            }
            return g;
        }

        static readonly int[] WeightValues = { 100, 200, 300, 400, 500, 600, 700, 800, 900 };

        void DigitsLook(XNode layout, XNode res, Generator gen)
        {
            var name = res.Str("name") ?? "";
            if (gen != null && gen.Drawn)
            {
                // шрифт, розмір, ефекти — у вікні «Намалювати шрифтом» (блок «Зображення» нижче); тут лише швидкий колір
                Add(Ui.Note(S.Get("fontSummary", gen.Font.Length > 0 ? gen.Font : S.Get("st" + char.ToUpper(gen.Style[0]) + gen.Style.Substring(1)), (int)gen.FontSize)));
                Add(Ui.ColorRow(S.Get("color"), gen.Color, h => Regen(name, gen, g => g.Color = h)));
                // одиниця біля числа — тим самим шрифтом
                var unit = new TextBox { Text = gen.Unit, Width = 70 };
                void CommitUnit(string u) { if (u != gen.Unit) Regen(name, gen, g => g.Unit = u); }
                unit.KeyDown += (s, e) => { if (e.Key == Key.Enter) { CommitUnit(unit.Text.Trim()); e.Handled = true; } };
                unit.LostKeyboardFocus += (s, e) => CommitUnit(unit.Text.Trim());
                var up = new StackPanel { Orientation = Orientation.Horizontal };
                up.Children.Add(unit);
                foreach (var u in new[] { "%", "°", "км", ":", "/", "bpm" })
                {
                    var b = new Button { Content = u, Style = (Style)FindResource("Btn"), Width = 36, Padding = new Thickness(0), Margin = new Thickness(6, 0, 0, 0) };
                    var uu = u;
                    b.Click += (s, e) => CommitUnit(uu);
                    up.Children.Add(b);
                }
                Add(Ui.Row(S.Get("unit"), up, 0));
            }
            else Add(Ui.Note(S.Get("digitsNoGen")));
            // «Число росте»: діє лише коли кількість цифр змінюється (без нулів попереду)
            bool fixedWidth = res.Bool("leadingZero") && res.Int("totalDigits") > 0;
            Add(Ui.GrowChips(S.Get("grow"), new[] { S.Get("growRight"), S.Get("growCenter"), S.Get("growLeft") },
                             res.Str("align") ?? "left", v => SetNumberAlign(layout, res, v), !fixedWidth,
                             fixedWidth ? S.Get("growNoEffect", res.Int("totalDigits")) : S.Get("growHint")));
            Add(Ui.NumberRow(S.Get("totalDigits"), res.Int("totalDigits"), v => EditRes(() => res.Set("totalDigits", v)), 0, 9));
            Add(Ui.NumberRow(S.Get("digitSpace"), res.Int("space"), v => EditRes(() => res.Set("space", v)), -20, 60));
            Add(Ui.Switch(S.Get("leadingZero"), res.Bool("leadingZero"), v => EditRes(() => res.Set("leadingZero", v))));
        }

        /// <summary>Набір цифр: готові й свої стилі, ефекти (градієнт, обвідка, тінь, ширина), застосування до всіх чисел</summary>
        void DigitEffects(string name, Generator gen)
        {
            Add(Ui.Header(S.Get("digitSet")));
            var sets = DigitSets.All();
            var combo = new ComboBox { MaxDropDownHeight = 420, Margin = new Thickness(0, 0, 0, 8) };
            combo.Items.Add(new ComboBoxItem { Content = S.Get("dsPick"), IsEnabled = false });
            foreach (var st in sets)
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal };
                var prev = AssetFactory.DigitFrames(Sized(st.Style, 22));
                foreach (var d in new[] { 1, 2, 3, 4 }) if (d < prev.Count) row.Children.Add(new Image { Source = prev[d].ToBitmap(), Height = 22, Stretch = Stretch.Uniform, Margin = new Thickness(0, 0, 1, 0) });
                row.Children.Add(new TextBlock { Text = "  " + st.Name + (st.BuiltIn ? "" : "  ·  " + S.Get("dsMine")), VerticalAlignment = VerticalAlignment.Center });
                combo.Items.Add(new ComboBoxItem { Content = row, Tag = st });
            }
            combo.SelectedIndex = 0;
            combo.SelectionChanged += (s, e) =>
            {
                if ((combo.SelectedItem as ComboBoxItem)?.Tag is DigitSets.Set st) Regen(name, gen, g => g.ApplyStyle(st.Style));
            };
            Add(combo);
            var acts = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 10) };
            var save = new Button { Content = S.Get("dsSave"), Style = (Style)FindResource("Btn"), Margin = new Thickness(0, 0, 4, 0) };
            save.Click += (s, e) =>
            {
                var n = InputBox.Ask(Owner, S.Get("digitSet"), S.Get("dsName"), S.Get("dsMine") + " " + (DigitSets.User().Count + 1));
                if (n != null) { DigitSets.Add(n, gen); BuildInspector(); }
            };
            var all = new Button { Content = S.Get("dsApplyAll"), Style = (Style)FindResource("Btn"), Margin = new Thickness(4, 0, 0, 0) };
            all.Click += (s, e) => project.Edit(p =>
            {
                // інші числа отримують той самий вигляд, розмір кожного лишається своїм
                foreach (var kv in p.Meta.Generators.Where(x => x.Value.Kind == GenKind.Digits && x.Key != name).ToList())
                {
                    var g = kv.Value.Copy();
                    g.ApplyStyle(gen);
                    ElementFactory.Regenerate(p, kv.Key, g);
                }
            });
            acts.Children.Add(save); acts.Children.Add(all);
            Add(acts);
            var mine = DigitSets.User();
            if (mine.Count > 0)
            {
                var del = new TextBlock { Text = S.Get("dsManage"), FontSize = 12, Foreground = (Brush)FindResource("Accent"), Cursor = Cursors.Hand, Margin = new Thickness(0, -4, 0, 10) };
                del.MouseLeftButtonUp += (s, e) =>
                {
                    var m = new ContextMenu { PlacementTarget = del };
                    foreach (var st in mine)
                    {
                        var it = new MenuItem { Header = S.Get("dsDelete", st.Name) };
                        var nm = st.Name;
                        it.Click += (s2, e2) => { DigitSets.Remove(nm); BuildInspector(); };
                        m.Items.Add(it);
                    }
                    m.IsOpen = true;
                };
                Add(del);
            }

            // градієнт згори донизу
            bool grad = !string.IsNullOrEmpty(gen.Color2);
            Add(Ui.Switch(S.Get("gradient"), grad, v => Regen(name, gen, g => g.Color2 = v ? (Suggested.FirstOrDefault(c => c != g.Color) ?? "#FF375F") : "")));
            if (grad) Add(Ui.ColorRow(S.Get("gradientTo"), gen.Color2, h => Regen(name, gen, g => g.Color2 = h)));
            Add(Ui.Slider(S.Get("outline"), gen.Outline, 0, 8, 0.5, v => Regen(name, gen, g => g.Outline = v)));
            if (gen.Outline > 0) Add(Ui.ColorRow(S.Get("outlineColor"), gen.OutlineColor, h => Regen(name, gen, g => g.OutlineColor = h)));
            Add(Ui.Slider(S.Get("shadowX"), gen.ShadowX, -8, 8, 1, v => Regen(name, gen, g => g.ShadowX = v)));
            Add(Ui.Slider(S.Get("shadowY"), gen.ShadowY, -8, 8, 1, v => Regen(name, gen, g => g.ShadowY = v)));
            if (gen.ShadowX != 0 || gen.ShadowY != 0) Add(Ui.ColorRow(S.Get("shadowColor"), gen.ShadowColor, h => Regen(name, gen, g => g.ShadowColor = h)));
            Add(Ui.Slider(S.Get("letterWidth"), gen.WidthPct, 50, 150, 1, v => Regen(name, gen, g => g.WidthPct = v)));
            // лише контур і фон-фігура під кожною цифрою
            Add(Ui.Switch(S.Get("hollow"), gen.Hollow, v => Regen(name, gen, g => g.Hollow = v)));
            Add(Ui.Chips(S.Get("badge"), new[] { P("", S.Get("badgeNone")), P("circle", S.Get("badgeCircle")), P("capsule", S.Get("badgeCapsule")), P("square", S.Get("badgeSquare")) },
                         gen.Badge ?? "", v => Regen(name, gen, g => g.Badge = v)));
            if (!string.IsNullOrEmpty(gen.Badge)) Add(Ui.ColorRow(S.Get("badgeColor"), gen.BadgeColor, h => Regen(name, gen, g => g.BadgeColor = h)));
        }

        static Generator Sized(Generator g, double size) { var c = g.Copy(); c.FontSize = size; c.Outline = Math.Min(c.Outline, 1.5); return c; }

        /// <summary>Шрифт: будь-який встановлений у Windows або доданий файл; без вибору — стиль</summary>
        void FontPicker(string name, Generator gen)
        {
            // шрифт: будь-який встановлений у Windows або доданий файл
            var fonts = new List<KeyValuePair<string, string>> { P("", S.Get("fontStyleDefault")) };
            fonts.AddRange(FontLibrary.AllNames().Select(f => P(f, f)));
            var combo = new ComboBox { MaxDropDownHeight = 460 };
            foreach (var kv in fonts)
            {
                var tb = new TextBlock { Text = kv.Value, FontSize = 13 };
                if (kv.Key.Length > 0) { tb.FontFamily = FontLibrary.Family(kv.Key); tb.Text = kv.Value + "   0123456789"; }
                var it = new ComboBoxItem { Content = tb, Tag = kv.Key };
                combo.Items.Add(it);
                if (kv.Key == gen.Font) combo.SelectedItem = it;
            }
            combo.SelectionChanged += (s, e) =>
            {
                var f = (combo.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
                if (f != gen.Font) Regen(name, gen, g => g.Font = f);
            };
            Add(new TextBlock { Text = S.Get("font"), FontSize = 13, Margin = new Thickness(0, 0, 0, 6) });
            Add(combo);
            var cov = gen.Font.Length > 0 ? FontLibrary.Coverage(gen.Font) : "";
            Add(Ui.Note(cov.Length > 0 ? S.Get("fontHas", cov) : S.Get("fontHint")));
            var addFont = new TextBlock { Text = S.Get("addFontFile"), FontSize = 12, Foreground = (Brush)FindResource("Accent"), Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 0, 10) };
            addFont.MouseLeftButtonUp += (s, e) =>
            {
                var added = Actions.AddFonts(Owner);
                if (added.Count > 0) Regen(name, gen, g => g.Font = added[0]); else BuildInspector();
            };
            Add(addFont);
            if (gen.Font.Length == 0)
                Add(Ui.Chips(S.Get("fontStyle"), new[] { P("rounded", S.Get("stRounded")), P("default", S.Get("stDefault")), P("condensed", S.Get("stCondensed")), P("mono", S.Get("stMono")) },
                             gen.Style, v => Regen(name, gen, g => g.Style = v)));
        }

        /// <summary>x числа — точка прив'язки (лівий край / середина / правий край): при зміні вирівнювання число лишається на місці</summary>
        void SetNumberAlign(XNode layout, XNode res, string v)
        {
            var b = new FaceRenderer(project).Boxes(theme).FirstOrDefault(x => x.Layout == layout)?.Rect;
            project.Edit(p =>
            {
                res.Set("align", v);
                if (b == null) return;
                double x = v == "center" ? b.Value.X + b.Value.Width / 2 : v == "right" ? b.Value.Right : b.Value.X;
                layout.Set("x", (int)Math.Round(x));
            });
        }

        // MARK: Напис

        /// <summary>Напис: рядок, шрифт (будь-який Windows або доданий), розмір, товщина, колір</summary>
        void LabelLook(XNode res, Generator gen)
        {
            if (gen == null) return;
            var name = res.Str("name") ?? "";
            var text = new TextBox { Text = gen.Text };
            void Commit()
            {
                var t = text.Text.Trim();
                if (t.Length == 0) { text.Text = gen.Text; return; }
                if (t != gen.Text) Regen(name, gen, g => g.Text = t);
            }
            text.KeyDown += (s, e) => { if (e.Key == Key.Enter) { Commit(); e.Handled = true; } };
            text.LostKeyboardFocus += (s, e) => Commit();
            Add(new TextBlock { Text = S.Get("labelText"), FontSize = 13, Margin = new Thickness(0, 0, 0, 6) });
            Add(text);
            Add(Ui.Note(S.Get("labelHint")));
            Add(Ui.ColorRow(S.Get("color"), gen.Color, h => Regen(name, gen, g => g.Color = h)));
        }

        // MARK: Стрілка, дуга, лінія

        void GaugeLook(XNode res, ElementKind kind, Generator gen)
        {
            var name = res.Str("name") ?? "";
            bool drawn = gen != null && gen.Drawn;
            if (kind == ElementKind.Arc && drawn) { ArcLook(res, ElementFactory.Synced(res, gen)); return; }
            if (kind == ElementKind.Line && drawn) { LineLook(res, ElementFactory.Synced(res, gen)); return; }
            if (kind == ElementKind.Arc || kind == ElementKind.Pointer)
                Add(Ui.Slider(S.Get("startAngle"), res.Int("angleStart"), -360, 360, 1, v => EditRes(() => res.Set("angleStart", (int)v))));
            if (kind == ElementKind.Arc)
                Add(Ui.Slider(S.Get("arcLength"), res.Int("angleRange"), -360, 360, 1, v => EditRes(() => res.Set("angleRange", (int)v))));
            if (kind == ElementKind.Pointer)
            {
                Add(Ui.Slider(S.Get("turnRange"), res.Int("angleRange"), -1440, 1440, 5, v => EditRes(() => res.Set("angleRange", (int)v))));
                Add(Ui.NumberRow(S.Get("pivotX"), res.Int("pivotX"), v => EditRes(() => res.Set("pivotX", v))));
                Add(Ui.NumberRow(S.Get("pivotY"), res.Int("pivotY"), v => EditRes(() => res.Set("pivotY", v))));
                Add(Ui.Note(S.Get("pivotHint")));
                Add(Ui.Button(S.Get("handImage") + "…", () =>
                {
                    var imgs = PickImages(false, 260);
                    if (imgs.Count == 0) return;
                    var img = imgs[0];
                    project.Edit(p =>
                    {
                        var target = p.ResourceRef(res.Str("ref"));
                        if (target == null) return;
                        ElementFactory.ReplaceImage(p, target, img);
                        res.Set("pivotX", img.W / 2).Set("pivotY", img.H - img.W / 2);
                        // своя картинка — параметри малювання стрілки більше не діють
                        p.Meta.Generators.Remove(name);
                    });
                }));
            }
            if (kind == ElementKind.Arc || kind == ElementKind.Line)
                Add(Ui.Chips(S.Get("ends"), new[] { P("round", S.Get("endsRound")), P("normal", S.Get("endsFlat")) },
                             res.Str("endingStyle") == "normal" ? "normal" : "round", v => EditRes(() => res.Set("endingStyle", v))));
            if (!res.Has("valueRangeSource"))
                Add(Ui.NumberRow(S.Get("maxValue"), res.Int("valueRange"), v => EditRes(() => res.Set("valueRange", v)), 1, 1000000));
            if (drawn)
            {
                Add(Ui.Slider(S.Get("length"), gen.Length, 10, 400, 1, v => Regen(name, gen, g => g.Length = v)));
                Add(Ui.Slider(S.Get("thickness"), gen.Width, 2, 60, 1, v => Regen(name, gen, g => g.Width = v)));
                Add(Ui.ColorRow(S.Get("color"), gen.Color, h => Regen(name, gen, g => g.Color = h)));
            }
            else Add(Ui.Note(S.Get("colorByImages")));
        }

        /// <summary>Швидкі форми дуги: (початок, довжина)</summary>
        static readonly Tuple<string, double, double>[] ArcShapes =
        {
            Tuple.Create("shapeCircle", 0.0, 360.0), Tuple.Create("shapeHorseshoe", 220.0, 280.0),
            Tuple.Create("shapeHalf", 270.0, 180.0), Tuple.Create("shapeQuarter", 315.0, 90.0),
        };

        void ArcLook(XNode res, Generator gen)
        {
            var name = res.Str("name") ?? "";
            // Довжина — повзунком; розріз дуги лишається на місці (дуга розтягується симетрично).
            // Середина дуги = Start + Range/2, розріз — навпроти неї.
            double sign = gen.Range < 0 ? -1 : 1;
            double mid = Norm(gen.Start + gen.Range / 2);
            Add(Ui.Slider(S.Get("arcLength"), Math.Abs(gen.Range), 10, 360, 1, v =>
            {
                foreach (var snapTo in new[] { 90.0, 180, 270, 360 }) if (Math.Abs(v - snapTo) <= 6) { v = snapTo; break; }
                Regen(name, gen, g => { g.Range = sign * v; g.Start = Norm(mid - sign * v / 2); });
            }));
            Add(Ui.Note(S.Get("arcLengthHint")));
            // Розріз: 8 напрямків — дуга стає симетрично, розрізом у вибраний бік (для 360° — звідки починається заповнення)
            double gap = Math.Abs(Math.Abs(gen.Range) - 360) < 0.5 ? Norm(gen.Start) : Norm(mid + 180);
            Add(Ui.DirectionPad(S.Get("arcGap"), gap, d =>
                Regen(name, gen, g =>
                {
                    double len = Math.Abs(g.Range);
                    g.Start = len >= 359.5 ? d : Norm(d + 180 - sign * len / 2);
                })));
            Add(Ui.NumberRow(S.Get("arcStart"), (int)Math.Round(Norm(gen.Start)), v => Regen(name, gen, g => g.Start = Norm(v)), 0, 359));
            Add(Ui.ButtonsRow(new[] { "−15°", "+15°" }, k => Regen(name, gen, g => g.Start = Norm(g.Start + (k == 0 ? -15 : 15)))));
            Add(Ui.Chips(S.Get("fillDirection"), new[] { P("cw", S.Get("dirCw")), P("ccw", S.Get("dirCcw")) }, gen.Range < 0 ? "ccw" : "cw",
                         v => Regen(name, gen, g =>
                         {
                             // зміна напрямку не зсуває дугу: та сама середина, інший бік заповнення
                             double len = Math.Abs(g.Range), s2 = v == "ccw" ? -1 : 1;
                             g.Range = s2 * len; g.Start = Norm(mid - s2 * len / 2);
                         })));
            Add(Ui.Note(S.Get("arcHandlesHint")));
            Add(Ui.Slider(S.Get("radius"), gen.Radius, 10, 300, 1, v => Regen(name, gen, g => g.Radius = v)));
            Add(Ui.Slider(S.Get("thickness"), gen.Width, 2, 60, 1, v => Regen(name, gen, g => g.Width = v)));
            Add(Ui.Chips(S.Get("ends"), new[] { P("round", S.Get("endsRound")), P("normal", S.Get("endsFlat")) }, gen.Round ? "round" : "normal",
                         v => Regen(name, gen, g => g.Round = v == "round")));
            Add(Ui.Switch(S.Get("endDot"), res.Has("indicatorImage"), v => project.Edit(p => ElementFactory.SetIndicator(p, res, v, gen.Width))));
            if (!res.Has("valueRangeSource"))
                Add(Ui.NumberRow(S.Get("maxValue"), res.Int("valueRange"), v => EditRes(() => res.Set("valueRange", v)), 1, 1000000));
            Add(Ui.ColorRow(S.Get("color"), gen.Color, h => Regen(name, gen, g => g.Color = h)));
            Add(Ui.ColorRow(S.Get("trackColor"), gen.BgColor, h => Regen(name, gen, g => g.BgColor = h)));
        }

        static double Norm(double a) { a %= 360; return a < 0 ? a + 360 : a; }

        static readonly Tuple<string, double>[] LineDirs =
            { Tuple.Create("→", 0.0), Tuple.Create("←", 180.0), Tuple.Create("↑", -90.0), Tuple.Create("↓", 90.0) };

        void LineLook(XNode res, Generator gen)
        {
            var name = res.Str("name") ?? "";
            var layout = selected;
            double ang = Math.Round(gen.Angle, 1);
            var dir = LineDirs.FirstOrDefault(d => Math.Abs(Norm(d.Item2) - Norm(ang)) < 0.05)?.Item1 ?? "custom";
            var items = LineDirs.Select(d => P(d.Item1, d.Item1)).ToList();
            items.Add(P("custom", S.Get("customAngle")));
            Add(Ui.Chips(S.Get("direction"), items, dir, v =>
            {
                if (v == "custom") { Regen(name, gen, g => g.Angle = Math.Abs(Norm(ang) % 90) < 0.05 ? 45 : ang); return; }
                Regen(name, gen, g => g.Angle = LineDirs.First(d => d.Item1 == v).Item2);
            }));
            if (dir == "custom")
                Add(Ui.Slider(S.Get("angle"), ang > 180 ? ang - 360 : ang, -180, 180, 1, v => Regen(name, gen, g => g.Angle = v)));
            Add(Ui.Slider(S.Get("length"), gen.Length, 4, 600, 1, v => Regen(name, gen, g => g.Length = v)));
            Add(Ui.Slider(S.Get("thickness"), gen.Width, 2, 60, 1, v => Regen(name, gen, g => g.Width = v)));
            Add(Ui.Chips(S.Get("ends"), new[] { P("round", S.Get("endsRound")), P("normal", S.Get("endsFlat")) }, gen.Round ? "round" : "normal",
                         v => Regen(name, gen, g => g.Round = v == "round")));
            if (Math.Abs(Norm(ang) % 180) > 0.05)
            {
                var warn = Ui.Note(S.Get("lineUntested"));
                warn.Foreground = (Brush)FindResource("Err");
                Add(warn);
            }
            // кінці лінії в координатах циферблата
            if (layout != null)
            {
                double x1 = layout.Int("x") + res.Int("startX"), y1 = layout.Int("y") + res.Int("startY");
                double x2 = layout.Int("x") + res.Int("endX"), y2 = layout.Int("y") + res.Int("endY");
                var g4 = new UniformGrid { Columns = 4, Margin = new Thickness(0, 0, 0, 6) };
                FrameworkElement Cell(string label, double v, Action<int> set)
                {
                    var sp = new StackPanel { Margin = new Thickness(0, 0, 6, 0) };
                    sp.Children.Add(new TextBlock { Text = label, FontSize = 11, Foreground = (Brush)FindResource("Sub"), Margin = new Thickness(0, 0, 0, 3) });
                    sp.Children.Add(Ui.Number((int)Math.Round(v), set));
                    return sp;
                }
                void Place(double a, double b, double c, double d) => project.Edit(p => ElementFactory.PlaceLine(p, res, layout, gen, a, b, c, d));
                g4.Children.Add(Cell("X1", x1, v => Place(v, y1, x2, y2)));
                g4.Children.Add(Cell("Y1", y1, v => Place(x1, v, x2, y2)));
                g4.Children.Add(Cell("X2", x2, v => Place(x1, y1, v, y2)));
                g4.Children.Add(Cell("Y2", y2, v => Place(x1, y1, x2, v)));
                Add(new TextBlock { Text = S.Get("lineEnds"), FontSize = 13, Margin = new Thickness(0, 0, 0, 6) });
                Add(g4);
                Add(Ui.Note(S.Get("lineHandlesHint")));
            }
            if (!res.Has("valueRangeSource"))
                Add(Ui.NumberRow(S.Get("maxValue"), res.Int("valueRange"), v => EditRes(() => res.Set("valueRange", v)), 1, 1000000));
            Add(Ui.ColorRow(S.Get("color"), gen.Color, h => Regen(name, gen, g => g.Color = h)));
            Add(Ui.ColorRow(S.Get("trackColor"), gen.BgColor, h => Regen(name, gen, g => g.BgColor = h)));
        }

        // MARK: Кольорові варіанти елемента

        void BuildVariantRow(XNode res)
        {
            // галочка «кольорові варіанти» — у кожного елемента; де неможливо, видно чому
            var avail = ColorVariants.Check(project, res, out var why);
            bool on = ColorVariants.IsOn(project, res) || ColorVariants.Wanted(project, res);
            Add(Ui.Header(S.Get("faceColors")));
            Add(Ui.Switch(S.Get("cvFollows"), on, v => project.Edit(p => ColorVariants.Set(p, res, v)),
                          avail != ColorVariants.Availability.Unavailable || on));
            if (why != null) Add(Ui.Note(why));
            else if (!ColorVariants.IsEnabled(project)) Add(Ui.Note(S.Get("cvOffHint")));
            else if (on) Add(Ui.Note(S.Get("cvOnHint")));
        }

        // MARK: Позиція

        void BuildPosition(XNode layout)
        {
            Add(Ui.Header(S.Get("position")));
            var box = new FaceRenderer(project).Boxes(theme).FirstOrDefault(b => b.Layout == layout)?.Rect ?? new Rect();
            var g = new UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 4) };
            FrameworkElement Cell(string label, FrameworkElement c)
            {
                var sp = new StackPanel { Margin = new Thickness(0, 0, 8, 8) };
                sp.Children.Add(new TextBlock { Text = label, FontSize = 11, Foreground = (Brush)FindResource("Sub"), Margin = new Thickness(0, 0, 0, 3) });
                sp.Children.Add(c);
                return sp;
            }
            g.Children.Add(Cell("X", Ui.Number(layout.Int("x"), v => EditRes(() => layout.Set("x", v)))));
            g.Children.Add(Cell("Y", Ui.Number(layout.Int("y"), v => EditRes(() => layout.Set("y", v)))));
            g.Children.Add(Cell(S.Get("width"), new TextBox { Text = ((int)Math.Round(box.Width)).ToString(), IsReadOnly = true, Opacity = 0.7 }));
            g.Children.Add(Cell(S.Get("height"), new TextBox { Text = ((int)Math.Round(box.Height)).ToString(), IsReadOnly = true, Opacity = 0.7 }));
            Add(g);
            var dev = project.Meta.Device;
            var al = new UniformGrid { Columns = 3 };
            void A(string title, Func<int?> tx, Func<int?> ty)
            {
                var b = new Button { Content = title, Style = (Style)FindResource("Btn"), Margin = new Thickness(0, 0, 4, 4), Padding = new Thickness(4, 0, 4, 0), FontSize = 12 };
                b.Click += (s, e) =>
                {
                    var bx = new FaceRenderer(project).Boxes(theme).FirstOrDefault(q => q.Layout == layout)?.Rect;
                    if (bx == null) return;
                    int dx = tx() is int x ? x - (int)Math.Round(bx.Value.X) : 0;
                    int dy = ty() is int y ? y - (int)Math.Round(bx.Value.Y) : 0;
                    if (dx != 0 || dy != 0) EditRes(() => layout.Set("x", layout.Int("x") + dx).Set("y", layout.Int("y") + dy));
                };
                al.Children.Add(b);
            }
            A(S.Get("alLeft"), () => 0, () => null);
            A(S.Get("alHCenter"), () => (int)Math.Round((dev.Width - box.Width) / 2), () => null);
            A(S.Get("alRight"), () => dev.Width - (int)Math.Round(box.Width), () => null);
            A(S.Get("alTop"), () => null, () => 0);
            A(S.Get("alVCenter"), () => null, () => (int)Math.Round((dev.Height - box.Height) / 2));
            A(S.Get("alBottom"), () => null, () => dev.Height - (int)Math.Round(box.Height));
            Add(al);
            Add(Ui.Note(S.Get("nudgeHint")));
        }
    }
}
