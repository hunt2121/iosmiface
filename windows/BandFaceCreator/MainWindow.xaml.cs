// SPDX-License-Identifier: MIT
// Головне вікно BandFace Creator: список циферблатів (проєктів), редактор, бібліотека шрифтів.
// .bin / .face відкриваються з меню, з командного рядка (подвійний клік у Провіднику) і перетягуванням у вікно.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace BandFace.Creator
{
    public partial class MainWindow : Window
    {
        readonly ProjectStore store = new ProjectStore();
        /// <summary>Мініатюри карток: ключ — проєкт і його версія (перемальовуються лише після змін)</summary>
        readonly Dictionary<string, ImageSource> thumbs = new Dictionary<string, ImageSource>();

        public MainWindow(string[] args)
        {
            InitializeComponent();
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            VersionText.Text = "v" + v.Major + "." + v.Minor + "." + v.Build;
            ApplyTexts();
            Editor.BackRequested += () => NavFaces.IsChecked = true;
            RefreshProjects();
            SourceInitialized += (s, e) => Theme.Apply(this);
            SystemEvents.UserPreferenceChanged += (s, e) => Dispatcher.BeginInvoke(new Action(() => Theme.Apply(this)));
            PreviewKeyDown += Window_PreviewKeyDown;
            DragEnter += Window_DragEnter; DragOver += Window_DragEnter; DragLeave += (s, e) => DropHint.Visibility = Visibility.Collapsed;
            Drop += Window_Drop;

            string shot = null;
            foreach (var a in args)
            {
                if (a.StartsWith("--shot=")) shot = a.Substring(7);
                else if (a == "--demo") OpenProject(store.Create(S.Get("newFaceName"), DeviceProfile.Band10));
                else if (a == "--page=fonts") NavFonts.IsChecked = true;
                else if (!a.StartsWith("--") && File.Exists(a)) OpenFile(a);
            }
            if (shot != null)
                ContentRendered += async (s, e) =>
                {
                    await Task.Delay(1500);
                    try { SaveShot(shot); } catch (Exception ex) { File.WriteAllText(shot + ".txt", ex.ToString()); }
                    Application.Current.Shutdown();
                };
        }

        void ApplyTexts()
        {
            NavFacesText.Text = TitleFaces.Text = S.Get("faces");
            NavEditorText.Text = S.Get("editor");
            NavFontsText.Text = TitleFonts.Text = S.Get("fonts");
            NewBtn.Content = S.Get("newFace");
            OpenBinBtn.Content = S.Get("openBin");
            OpenFolderBtn.Content = S.Get("openFolder");
            FacesHint.Text = S.Get("facesHint");
            EmptyTitle.Text = S.Get("emptyTitle");
            EmptyText.Text = S.Get("emptyText");
            DropText.Text = S.Get("dropHint");
            AddFontBtn.Content = S.Get("addFont");
            FontsLabel.Text = S.Get("userFonts").ToUpper();
            FontsNote.Text = S.Get("userFontsNote");
            SysFontsLabel.Text = S.Get("sysFonts").ToUpper();
            FontSearch.ToolTip = S.Get("searchFonts");
        }

        void SaveShot(string path)
        {
            var root = (FrameworkElement)Content;
            int w = (int)root.ActualWidth, h = (int)root.ActualHeight;
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen())
            {
                dc.DrawRectangle((Brush)FindResource("Bg"), null, new Rect(0, 0, w, h));
                dc.DrawRectangle(new VisualBrush(root), null, new Rect(0, 0, w, h));
            }
            var bmp = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
            bmp.Render(dv);
            var enc = new PngBitmapEncoder();
            enc.Frames.Add(BitmapFrame.Create(bmp));
            using (var f = File.Create(path)) enc.Save(f);
        }

        // MARK: Навігація

        void Nav_Checked(object sender, RoutedEventArgs e)
        {
            if (PageFaces == null) return;
            PageFaces.Visibility = NavFaces.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            Editor.Visibility = NavEditor.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            PageFonts.Visibility = NavFonts.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            if (NavFaces.IsChecked == true) RefreshProjects();
            if (NavFonts.IsChecked == true) RefreshFonts();
            if (NavEditor.IsChecked == true) Editor.Focus();
        }

        void OpenProject(FaceProject p)
        {
            Editor.Open(p);
            NavEditor.IsEnabled = true;
            NavEditor.IsChecked = true;
            Title = p.DisplayName + " — BandFace Creator";
        }

        void Window_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (Editor.Visibility != Visibility.Visible) return;
            // у полях введення клавіші належать полю
            if (Keyboard.FocusedElement is TextBox || Keyboard.FocusedElement is ComboBox || Keyboard.FocusedElement is ComboBoxItem) return;
            if (Editor.HandleKey(e)) e.Handled = true;
        }

        // MARK: Проєкти

        void RefreshProjects()
        {
            ProjectsPanel.Children.Clear();
            foreach (var p in store.Projects) ProjectsPanel.Children.Add(Card(p));
            EmptyCard.Visibility = store.Projects.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        FrameworkElement Card(FaceProject p)
        {
            var img = new Image { Stretch = Stretch.UniformToFill };
            var capsule = new Border
            {
                Width = 96, Height = 236, CornerRadius = new CornerRadius(48), Background = new SolidColorBrush(Color.FromRgb(0x22, 0x22, 0x22)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(0x8A, 0x8A, 0x8A)), BorderThickness = new Thickness(3), Child = img,
            };
            img.Clip = new RectangleGeometry(new Rect(0, 0, 90, 230), 45, 45);
            var sp = new StackPanel { Width = 150 };
            sp.Children.Add(capsule);
            sp.Children.Add(new TextBlock { Text = p.DisplayName, FontSize = 13, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 10, 0, 0) });
            sp.Children.Add(new TextBlock { Text = p.Meta.Modified.ToLocalTime().ToString("g"), FontSize = 11, Foreground = (Brush)FindResource("Sub"), TextAlignment = TextAlignment.Center });
            var card = new Border { Style = (Style)FindResource("CardBox"), Margin = new Thickness(0, 0, 14, 14), Padding = new Thickness(14), Child = sp, Cursor = Cursors.Hand, ToolTip = p.DisplayName };
            card.MouseLeftButtonUp += (s, e) => OpenProject(p);
            var menu = new ContextMenu();
            void Item(string t, Action a) { var m = new MenuItem { Header = t }; m.Click += (s, e) => a(); menu.Items.Add(m); }
            Item(S.Get("open"), () => OpenProject(p));
            Item(S.Get("duplicate"), () => { store.Duplicate(p); RefreshProjects(); });
            Item(S.Get("saveBin"), () => Actions.ExportBin(this, p));
            Item(S.Get("showInFolder"), () => { try { Process.Start("explorer.exe", "\"" + p.Folder + "\""); } catch (Exception) { } });
            menu.Items.Add(new Separator());
            Item(S.Get("deleteFace"), () =>
            {
                if (MessageBox.Show(this, S.Get("deleteFaceAsk", p.DisplayName), "BandFace Creator", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
                if (Editor.Project == p) { NavEditor.IsEnabled = false; NavFaces.IsChecked = true; Title = "BandFace Creator"; }
                store.Delete(p);
                RefreshProjects();
            });
            card.ContextMenu = menu;
            // мініатюра — коли картки вже на екрані
            var key = p.Id + "#" + p.Revision + "#" + p.Meta.Modified.Ticks;
            if (thumbs.TryGetValue(key, out var t0)) img.Source = t0;
            else Dispatcher.BeginInvoke(new Action(() =>
            {
                try
                {
                    double dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
                    var src = new FaceRenderer(p).Render(0, 230.0 / p.Meta.Device.Height * dpi).Image;
                    thumbs[key] = src;
                    img.Source = src;
                }
                catch (Exception) { }
            }), DispatcherPriority.Background);
            return card;
        }

        void New_Click(object sender, RoutedEventArgs e) => OpenProject(store.Create(S.Get("newFaceName"), DeviceProfile.Band10));

        void OpenBin_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog { Multiselect = true, Filter = S.Get("faceFilter") + "|*.bin;*.face" };
            if (dlg.ShowDialog(this) != true) return;
            foreach (var f in dlg.FileNames) OpenFile(f);
            if (dlg.FileNames.Length > 1) { NavFaces.IsChecked = true; RefreshProjects(); }
        }

        void OpenFolder_Click(object sender, RoutedEventArgs e)
        {
            using (var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = S.Get("openFolderTitle"), ShowNewFolderButton = false })
            {
                if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
                OpenPath(dlg.SelectedPath);
            }
        }

        /// <summary>Файл .bin/.face або тека з manifest.xml → новий проєкт, відкритий у редакторі</summary>
        void OpenPath(string path)
        {
            if (Directory.Exists(path))
            {
                try
                {
                    if (!File.Exists(Path.Combine(path, "manifest.xml"))) throw new Exception(S.Get("notFace"));
                    OpenProject(store.ImportFolder(path));
                }
                catch (Exception ex) { MessageBox.Show(this, S.Get("openFail", Path.GetFileName(path), ex.Message), "BandFace Creator", MessageBoxButton.OK, MessageBoxImage.Error); }
                return;
            }
            OpenFile(path);
        }

        void OpenFile(string path)
        {
            try
            {
                var data = File.ReadAllBytes(path);
                if (data.Length < 0xA8 || BitConverter.ToUInt32(data, 0) != 0x1234A55A) throw new Exception(S.Get("notFace"));
                OpenProject(store.ImportBin(data, Path.GetFileNameWithoutExtension(path)));
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, S.Get("openFail", Path.GetFileName(path), ex.Message), "BandFace Creator", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        // MARK: Перетягування файлів

        static string[] Dropped(DragEventArgs e) => e.Data.GetDataPresent(DataFormats.FileDrop) ? (string[])e.Data.GetData(DataFormats.FileDrop) : new string[0];

        static bool Acceptable(string f) =>
            Directory.Exists(f) || f.EndsWith(".bin", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".face", StringComparison.OrdinalIgnoreCase);

        void Window_DragEnter(object sender, DragEventArgs e)
        {
            bool ok = Dropped(e).Any(Acceptable);
            e.Effects = ok ? DragDropEffects.Copy : DragDropEffects.None;
            DropHint.Visibility = ok ? Visibility.Visible : Visibility.Collapsed;
            e.Handled = true;
        }

        void Window_Drop(object sender, DragEventArgs e)
        {
            DropHint.Visibility = Visibility.Collapsed;
            foreach (var f in Dropped(e).Where(Acceptable)) OpenPath(f);
        }

        // MARK: Шрифти

        void AddFont_Click(object sender, RoutedEventArgs e)
        {
            Actions.AddFonts(this);
            RefreshFonts();
        }

        void FontSearch_TextChanged(object sender, TextChangedEventArgs e) => FillSystemFonts();

        FrameworkElement FontRow(string name, bool user)
        {
            var g = new Grid { Margin = new Thickness(0, 0, 0, 10) };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var sp = new StackPanel();
            sp.Children.Add(new TextBlock { Text = "12:45  0123456789", FontFamily = FontLibrary.Family(name), FontSize = 24 });
            var cov = FontLibrary.Coverage(name);
            sp.Children.Add(new TextBlock { Text = name + (cov.Length > 0 ? "  ·  " + cov : ""), FontSize = 12, Foreground = (Brush)FindResource("Sub") });
            g.Children.Add(sp);
            if (user)
            {
                var b = new Button { Content = S.Get("removeFont"), Style = (Style)FindResource("DangerBtn"), VerticalAlignment = VerticalAlignment.Center };
                b.Click += (s, e) =>
                {
                    // файл може бути відкритий Windows — тоді прибирається під час наступного запуску
                    if (!FontLibrary.Remove(name)) MessageBox.Show(this, S.Get("removeFontNote"), "BandFace Creator");
                    RefreshFonts();
                };
                Grid.SetColumn(b, 1);
                g.Children.Add(b);
            }
            return g;
        }

        void RefreshFonts()
        {
            UserFonts.Children.Clear();
            var user = FontLibrary.User.Keys.OrderBy(x => x).ToList();
            if (user.Count == 0) UserFonts.Children.Add(new TextBlock { Text = S.Get("noUserFonts"), FontSize = 13, Foreground = (Brush)FindResource("Sub") });
            foreach (var n in user) UserFonts.Children.Add(FontRow(n, true));
            FillSystemFonts();
        }

        void FillSystemFonts()
        {
            SysFonts.Children.Clear();
            var q = FontSearch.Text.Trim();
            var all = Fonts.SystemFontFamilies.Select(FontLibrary.Name).Distinct()
                .Where(n => q.Length == 0 || n.IndexOf(q, StringComparison.CurrentCultureIgnoreCase) >= 0)
                .OrderBy(n => n, StringComparer.CurrentCultureIgnoreCase).ToList();
            foreach (var n in all.Take(60)) SysFonts.Children.Add(FontRow(n, false));
            if (all.Count > 60) SysFonts.Children.Add(new TextBlock { Text = S.Get("moreFonts", all.Count - 60), FontSize = 12, Foreground = (Brush)FindResource("Sub") });
        }
    }
}
