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
            idRow.Children.Add(new TextBlock { Text = project.Root.Str("id") ?? "—", FontFamily = new FontFamily("Consolas"), FontSize = 15, VerticalAlignment = VerticalAlignment.Center });
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

            if (res.Has("source"))
            {
                Add(Ui.Header(S.Get("data")));
                var src = res.Str("source");
                var btn = new Button { Style = (Style)FindResource("Btn"), HorizontalContentAlignment = HorizontalAlignment.Stretch, Height = 44, Margin = new Thickness(0, 0, 0, 8) };
                var sp = new StackPanel();
                sp.Children.Add(new TextBlock { Text = S.Get("shows"), FontSize = 11, Foreground = (Brush)FindResource("Sub") });
                sp.Children.Add(new TextBlock { Text = SampleData.Title(src), FontSize = 13, FontWeight = FontWeights.SemiBold });
                btn.Content = sp;
                btn.HorizontalAlignment = HorizontalAlignment.Stretch;
                btn.Click += (s, e) =>
                {
                    var n = SourcePicker.Pick(Owner, src);
                    if (n != null && n != src) EditRes(() => res.Set("source", n));
                };
                Add(btn);
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
                    Add(Ui.Button(S.Get("replaceImages") + "…", () =>
                    {
                        var imgs = PickImages(true, 200);
                        if (imgs.Count > 0) project.Edit(p => ElementFactory.ReplaceValueImages(p, res, imgs));
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

        static readonly int[] WeightValues = { 100, 200, 300, 400, 500, 600, 700, 800, 900 };

        void DigitsLook(XNode layout, XNode res, Generator gen)
        {
            var name = res.Str("name") ?? "";
            if (gen != null)
            {
                FontPicker(name, gen);
                Add(Ui.Slider(S.Get("fontSize"), gen.FontSize, 8, 200, 1, v => Regen(name, gen, g => g.FontSize = v)));
                Add(Ui.Row(S.Get("weight"), Ui.Combo(WeightValues.Select(w => P(w.ToString(), w + " · " + S.Get("w" + w))), gen.Weight.ToString(),
                                                     v => Regen(name, gen, g => g.Weight = int.Parse(v))), 190));
                Add(Ui.ColorRow(S.Get("color"), gen.Color, h => Regen(name, gen, g => g.Color = h)));
                // одиниця біля числа — тим самим шрифтом
                var unit = new TextBox { Text = gen.Unit, Width = 70 };
                void CommitUnit(string u) { if (u != gen.Unit) Regen(name, gen, g => g.Unit = u); }
                unit.KeyDown += (s, e) => { if (e.Key == Key.Enter) { CommitUnit(unit.Text.Trim()); e.Handled = true; } };
                unit.LostKeyboardFocus += (s, e) => CommitUnit(unit.Text.Trim());
                var up = new StackPanel { Orientation = Orientation.Horizontal };
                up.Children.Add(unit);
                foreach (var u in new[] { "%", "°", "км" })
                {
                    var b = new Button { Content = u, Style = (Style)FindResource("Btn"), Width = 36, Padding = new Thickness(0), Margin = new Thickness(6, 0, 0, 0) };
                    var uu = u;
                    b.Click += (s, e) => CommitUnit(uu);
                    up.Children.Add(b);
                }
                Add(Ui.Row(S.Get("unit"), up, 0));
            }
            else
            {
                Add(Ui.Note(S.Get("digitsNoGen")));
                Add(Ui.Button(S.Get("drawDigits"), () =>
                    project.Edit(p => ElementFactory.Regenerate(p, name, new Generator(GenKind.Digits) { Color = "#FFFFFF", FontSize = 48, Weight = 700, Style = "rounded" }))));
            }
            Add(Ui.Chips(S.Get("align"), new[] { P("left", S.Get("left")), P("center", S.Get("center")), P("right", S.Get("right")) },
                         res.Str("align") ?? "left", v => SetNumberAlign(layout, res, v)));
            Add(Ui.Note(S.Get("alignHint")));
            Add(Ui.NumberRow(S.Get("totalDigits"), res.Int("totalDigits"), v => EditRes(() => res.Set("totalDigits", v)), 0, 9));
            Add(Ui.NumberRow(S.Get("digitSpace"), res.Int("space"), v => EditRes(() => res.Set("space", v)), -20, 60));
            Add(Ui.Switch(S.Get("leadingZero"), res.Bool("leadingZero"), v => EditRes(() => res.Set("leadingZero", v))));
        }

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
            FontPicker(name, gen);
            Add(Ui.Slider(S.Get("fontSize"), gen.FontSize, 8, 200, 1, v => Regen(name, gen, g => g.FontSize = v)));
            Add(Ui.Row(S.Get("weight"), Ui.Combo(WeightValues.Select(w => P(w.ToString(), w + " · " + S.Get("w" + w))), gen.Weight.ToString(),
                                                 v => Regen(name, gen, g => g.Weight = int.Parse(v))), 190));
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
            var cur = ArcShapes.FirstOrDefault(t => Math.Abs(Norm(gen.Start) - t.Item2) < 0.5 && Math.Abs(Math.Abs(gen.Range) - t.Item3) < 0.5)?.Item1 ?? "";
            Add(Ui.Chips(S.Get("shape"), ArcShapes.Select(t => P(t.Item1, S.Get(t.Item1) + " " + t.Item3 + "°")), cur, v =>
            {
                var t = ArcShapes.First(x => x.Item1 == v);
                Regen(name, gen, g => { g.Start = t.Item2; g.Range = Math.Sign(gen.Range == 0 ? 1 : gen.Range) * t.Item3; });
            }));
            Add(Ui.Slider(S.Get("arcStart"), Norm(gen.Start), 0, 359, 1, v => Regen(name, gen, g => g.Start = v)));
            Add(Ui.Slider(S.Get("arcLength"), Math.Abs(gen.Range), 1, 360, 1, v => Regen(name, gen, g => g.Range = (gen.Range < 0 ? -1 : 1) * v)));
            Add(Ui.Chips(S.Get("direction"), new[] { P("cw", S.Get("dirCw")), P("ccw", S.Get("dirCcw")) }, gen.Range < 0 ? "ccw" : "cw",
                         v => Regen(name, gen, g => g.Range = (v == "ccw" ? -1 : 1) * Math.Abs(gen.Range))));
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
            var avail = ColorVariants.Check(project, res, out var why);
            bool on = ColorVariants.IsOn(project, res);
            if (ColorVariants.IsEnabled(project))
            {
                Add(Ui.Header(S.Get("faceColors")));
                Add(Ui.Switch(S.Get("cvFollows"), on, v => project.Edit(p => ColorVariants.Set(p, res, v)),
                              avail != ColorVariants.Availability.Unavailable || on));
                if (why != null) Add(Ui.Note(why));
                else if (on) Add(Ui.Note(S.Get("cvOnHint")));
            }
            else if (avail != ColorVariants.Availability.Unavailable)
            {
                Add(Ui.Header(S.Get("faceColors")));
                Add(Ui.Note(S.Get("cvOffHint")));
            }
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
