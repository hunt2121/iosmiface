// SPDX-License-Identifier: MIT
// Вибір джерела даних (пошук + групи), живий перегляд циферблата, спільні дії (експорт .bin, додавання шрифтів).

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using BandFace.Faces;
using Microsoft.Win32;

namespace BandFace.Creator
{
    /// <summary>Що показує елемент: усі джерела компілятора, згруповані, з пошуком</summary>
    sealed class SourcePicker : Window
    {
        readonly TextBox search = new TextBox();
        readonly ListBox list = new ListBox { BorderThickness = new Thickness(0), Background = Brushes.Transparent };
        readonly string current;
        string result;
        /// <summary>Вибрана група ("" — усі)</summary>
        string group = "";

        SourcePicker(string current)
        {
            this.current = current;
            Title = S.Get("pickSource");
            Width = 480; Height = 660; MinWidth = 380; MinHeight = 400;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Segoe UI");
            SetResourceReference(BackgroundProperty, "Bg");
            var root = new DockPanel { Margin = new Thickness(16) };
            var top = new StackPanel();
            DockPanel.SetDock(top, Dock.Top);
            top.Children.Add(new TextBlock { Text = S.Get("pickSource"), FontSize = 20, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) });
            top.Children.Add(search);
            // перемикачі груп: «Усе» і групи за префіксом
            var chips = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
            void Chip(string id, string title)
            {
                var c = new System.Windows.Controls.Primitives.ToggleButton { Content = title, Style = (Style)FindResource("Chip"), Padding = new Thickness(12, 0, 12, 0), Margin = new Thickness(0, 0, 6, 6), IsChecked = id == group };
                c.Click += (s, e) => { group = id; foreach (var o in chips.Children.OfType<System.Windows.Controls.Primitives.ToggleButton>()) o.IsChecked = o == c; Fill(); };
                chips.Children.Add(c);
            }
            Chip("", S.Get("grpAll"));
            foreach (var g in SampleData.Groups()) Chip(g.Id, g.Title);
            top.Children.Add(chips);
            top.Children.Add(new TextBlock { Text = S.Get("sourcesCount", FaceCatalog.Sources.Select(x => x.Item1).Distinct().Count()), FontSize = 12, Margin = new Thickness(0, 6, 0, 8) });
            root.Children.Add(top);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
            DockPanel.SetDock(buttons, Dock.Bottom);
            var cancel = new Button { Content = S.Get("cancel"), Style = (Style)FindResource("Btn"), IsCancel = true };
            var ok = new Button { Content = S.Get("choose"), Style = (Style)FindResource("PrimaryBtn"), Margin = new Thickness(10, 0, 0, 0), IsDefault = true };
            ok.Click += (s, e) => Accept();
            buttons.Children.Add(cancel);
            buttons.Children.Add(ok);
            root.Children.Add(buttons);
            list.ItemContainerStyle = (Style)FindResource("LayerItem");
            ScrollViewer.SetHorizontalScrollBarVisibility(list, ScrollBarVisibility.Disabled);
            list.MouseDoubleClick += (s, e) => Accept();
            root.Children.Add(new Border { Style = (Style)FindResource("CardBox"), Padding = new Thickness(6), Margin = new Thickness(0), Child = list });
            Content = root;
            search.TextChanged += (s, e) => Fill();
            Fill();
            Loaded += (s, e) => { search.Focus(); Theme.Apply(this); };
        }

        void Fill()
        {
            list.Items.Clear();
            var q = search.Text.Trim();
            ListBoxItem sel = null;
            foreach (var g in SampleData.Groups())
            {
                if (group.Length > 0 && g.Id != group) continue;
                var items = g.Sources.Where(x => q.Length == 0 || x.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0
                                                 || SampleData.Title(x).IndexOf(q, StringComparison.CurrentCultureIgnoreCase) >= 0).ToList();
                if (items.Count == 0) continue;
                list.Items.Add(new ListBoxItem
                {
                    Content = new TextBlock { Text = g.Title.ToUpper(), FontSize = 11, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 2) },
                    IsEnabled = false, Focusable = false,
                });
                foreach (var x in items)
                {
                    var it = new ListBoxItem { Content = EditorView.SourceRow(x, false), Tag = x };
                    list.Items.Add(it);
                    if (x == current) sel = it;
                }
            }
            if (sel != null) { list.SelectedItem = sel; list.ScrollIntoView(sel); }
        }

        void Accept()
        {
            if (!((list.SelectedItem as ListBoxItem)?.Tag is string s)) return;
            result = s;
            DialogResult = true;
        }

        public static string Pick(Window owner, string current)
        {
            var w = new SourcePicker(current) { Owner = owner };
            return w.ShowDialog() == true ? w.result : null;
        }
    }

    /// <summary>Живий перегляд: поточний час, анімації, вибраний колір. Клік або Esc — закрити.</summary>
    sealed class PreviewWindow : Window
    {
        readonly FaceProject project;
        readonly FaceRenderer renderer;
        readonly int theme;
        readonly Image image = new Image { Stretch = Stretch.Fill };
        readonly DispatcherTimer timer = new DispatcherTimer();
        readonly DateTime start = DateTime.Now;

        public PreviewWindow(FaceProject p, int theme, int variant)
        {
            project = p; this.theme = theme;
            renderer = new FaceRenderer(p) { Live = true, ColorVariant = variant };
            Title = S.Get("preview") + " — " + p.DisplayName;
            Background = Brushes.Black;
            Width = 420; Height = 860;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            var dev = p.Meta.Device;
            var face = new Grid { Width = dev.Width * 1.5, Height = dev.Height * 1.5 };
            face.Children.Add(image);
            face.Clip = new RectangleGeometry(new Rect(0, 0, face.Width, face.Height), dev.Corner * 1.5, dev.Corner * 1.5);
            var ring = new Border
            {
                BorderThickness = new Thickness(3), BorderBrush = new SolidColorBrush(Color.FromRgb(0x8A, 0x8A, 0x8A)),
                CornerRadius = new CornerRadius(dev.Corner * 1.5 + 3), Child = face, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            };
            Content = new Viewbox { Child = ring, Margin = new Thickness(24), Stretch = Stretch.Uniform };
            // крок: інтервал першої анімації на екрані, інакше — раз на секунду (живий час)
            int ms = 1000;
            foreach (var l in p.Layouts(theme))
            {
                var r = p.ResourceRef(l.Str("ref"));
                if (r?.Tag == "Sprite") { ms = Math.Max(30, r.Int("interval", 100)); break; }
            }
            timer.Interval = TimeSpan.FromMilliseconds(ms);
            timer.Tick += (s, e) => Draw();
            Loaded += (s, e) => { Draw(); timer.Start(); };
            Closed += (s, e) => timer.Stop();
            MouseLeftButtonUp += (s, e) => Close();
            KeyDown += (s, e) => { if (e.Key == Key.Escape) Close(); };
        }

        void Draw()
        {
            renderer.Time = (DateTime.Now - start).TotalSeconds;
            double dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
            image.Source = renderer.Render(theme, 1.5 * dpi * 1.4).Image;
        }
    }

    static class Actions
    {
        static string SafeName(string n)
        {
            var bad = Path.GetInvalidFileNameChars();
            var s = new string((n ?? "").Select(c => bad.Contains(c) ? '_' : c).ToArray()).Trim();
            return s.Length == 0 ? "watchface" : s;
        }

        /// <summary>Збирає .bin і зберігає у вибране місце; попередження компілятора — у повідомленні</summary>
        /// <summary>Елементи, не перевірені на браслеті: попередження й підтвердження. false — користувач відмовився.</summary>
        public static bool ConfirmUntested(Window owner, FaceProject p)
        {
            var u = Band10.Untested(p.Root);
            if (u.Count == 0) return true;
            var list = string.Join(", ", u.Select(kv => S.Get(kv.Key == "DataItemText" ? "elText" : "elOther") + " × " + kv.Value));
            return MessageBox.Show(owner, S.Get("untestedAsk", list), "BandFace", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) == MessageBoxResult.Yes;
        }

        /// <summary>Збирає .bin для встановлення на браслет; null — помилка (показано) або користувач відмовився.</summary>
        public static byte[] Build(Window owner, FaceProject p)
        {
            if (!ConfirmUntested(owner, p)) return null;
            try { owner.Cursor = Cursors.Wait; WidgetSlots.RefreshPreviews(p); return p.Compile().Item1; }
            catch (Exception ex)
            {
                MessageBox.Show(owner, S.Get("buildFail", ex.Message), "BandFace", MessageBoxButton.OK, MessageBoxImage.Error);
                return null;
            }
            finally { owner.Cursor = null; }
        }

        public static void ExportBin(Window owner, FaceProject p)
        {
            if (!ConfirmUntested(owner, p)) return;
            Tuple<byte[], List<string>> r;
            try { owner.Cursor = Cursors.Wait; WidgetSlots.RefreshPreviews(p); r = p.Compile(); }
            catch (Exception ex)
            {
                MessageBox.Show(owner, S.Get("buildFail", ex.Message), "BandFace", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }
            finally { owner.Cursor = null; }
            var dlg = new SaveFileDialog { FileName = SafeName(p.DisplayName) + ".bin", Filter = S.Get("binFilter") + "|*.bin", DefaultExt = ".bin" };
            if (dlg.ShowDialog(owner) != true) return;
            try { File.WriteAllBytes(dlg.FileName, r.Item1); }
            catch (Exception ex) { MessageBox.Show(owner, ex.Message, "BandFace", MessageBoxButton.OK, MessageBoxImage.Error); return; }
            // однакові імена — це кольорові варіанти однієї картинки, так і має бути
            var shown = r.Item2.Where(w => !w.Contains("same name")).Take(5).ToList();
            var msg = S.Get("saved", Path.GetFileName(dlg.FileName), (r.Item1.Length + 1023) / 1024);
            if (shown.Count > 0) msg += "\n\n" + S.Get("warnings") + "\n" + string.Join("\n", shown);
            MessageBox.Show(owner, msg, "BandFace", MessageBoxButton.OK, shown.Count > 0 ? MessageBoxImage.Warning : MessageBoxImage.Information);
        }

        /// <summary>Додає файли шрифтів у бібліотеку; повертає назви нових сімейств</summary>
        public static List<string> AddFonts(Window owner)
        {
            var dlg = new OpenFileDialog { Multiselect = true, Filter = S.Get("fontFilter") + "|*.ttf;*.otf;*.ttc" };
            var added = new List<string>();
            if (dlg.ShowDialog(owner) != true) return added;
            foreach (var f in dlg.FileNames)
            {
                try { added.AddRange(FontLibrary.Add(f)); }
                catch (Exception ex) { MessageBox.Show(owner, S.Get("fontFail", Path.GetFileName(f), ex.Message), "BandFace"); }
            }
            if (added.Count == 0 && dlg.FileNames.Length > 0) MessageBox.Show(owner, S.Get("fontKnown"), "BandFace");
            return added;
        }
    }
}
