// SPDX-License-Identifier: MIT
// Вкладка «Редактор» BandFace: список циферблатів (проєктів), редактор, бібліотека шрифтів.
// Колишнє головне вікно BandFace Creator; відкриття файлів і перетягування обробляє головне вікно BandFace.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;

namespace BandFace.Creator
{
    public partial class CreatorView : UserControl
    {
        readonly ProjectStore store = new ProjectStore();
        /// <summary>Мініатюри карток: ключ — проєкт і його версія (перемальовуються лише після змін)</summary>
        readonly Dictionary<string, ImageSource> thumbs = new Dictionary<string, ImageSource>();

        /// <summary>Редактор відкрито (true) чи закрито (false) — головне вікно згортає бічне меню.</summary>
        public event Action<bool> EditorShownChanged;
        /// <summary>«Встановити на браслет» у редакторі: .bin і назва.</summary>
        public event Action<byte[], string> InstallRequested;
        public event Action CancelInstallRequested;
        /// <summary>Id циферблата, який зараз на екрані браслета (null — невідомо)</summary>
        string activeFaceId;
        public void SetActiveFace(string id)
        {
            if (activeFaceId == id) return;
            activeFaceId = id;
            RefreshProjects();
        }

        /// <summary>Id усіх циферблатів на браслеті: для них кнопка під превʼю — «Перевстановити»</summary>
        HashSet<string> installedIds = new HashSet<string>();
        public void SetInstalledFaces(IEnumerable<string> ids)
        {
            var n = new HashSet<string>(ids ?? Enumerable.Empty<string>());
            if (n.SetEquals(installedIds)) return;
            installedIds = n;
            RefreshProjects();
        }

        /// <summary>Прогрес встановлення з редактора — у віконце під кнопкою</summary>
        /// <summary>Прогрес встановлення: у редакторі — під його кнопкою «Встановити»; у списку циферблатів — так само
        /// у верхньому правому куті, під кнопкою «Новий циферблат» (кнопка редактора тоді прихована, і віконце без місця «гуляло»)</summary>
        public void ShowInstall(InstallUpdate u)
        {
            if (Editor.Visibility == Visibility.Visible) { listPopup?.Close(); Editor.ShowInstall(u); return; }
            if (listPopup == null)
                listPopup = new InstallPopup(NewBtn) { Cancel = () => CancelInstallRequested?.Invoke(), Retry = null };
            listPopup.Show(u, listPopup.IsOpen || u.State == InstallUpdate.Kind.Connecting || u.State == InstallUpdate.Kind.Done || u.State == InstallUpdate.Kind.Failed);
        }

        InstallPopup listPopup;

        public bool EditorShown => Editor.Visibility == Visibility.Visible;
        Window Owner => Window.GetWindow(this);

        public CreatorView()
        {
            InitializeComponent();
            ApplyTexts();
            Editor.BackRequested += ShowList;
            Editor.InstallRequested += (bin, name) => InstallRequested?.Invoke(bin, name);
            Editor.CancelInstallRequested += () => CancelInstallRequested?.Invoke();
            RefreshProjects();
            // ширина вікна змінилась — лише кількість колонок (картки не перебудовуємо)
            PageFaces.SizeChanged += (s, e) => { if (e.WidthChanged) ProjectsPanel.Columns = GridColumns(); };
        }

        void ApplyTexts()
        {
            TitleFaces.Text = S.Get("editor");
            FontsBtn.Content = S.Get("fonts");
            TitleFonts.Text = S.Get("fonts");
            NewBtn.Content = S.Get("newFace");
            OpenBinBtn.Content = S.Get("openBin");
            OpenFolderBtn.Content = S.Get("openFolder");
            FacesHint.Text = S.Get("facesHint");
            EmptyTitle.Text = S.Get("emptyTitle");
            EmptyText.Text = S.Get("emptyText");
            AddFontBtn.Content = S.Get("addFont");
            FontsBackBtn.ToolTip = S.Get("back");
            FontsLabel.Text = S.Get("userFonts").ToUpper();
            FontsNote.Text = S.Get("userFontsNote");
            SysFontsLabel.Text = S.Get("sysFonts").ToUpper();
            FontSearch.ToolTip = S.Get("searchFonts");
        }

        // MARK: Сторінки

        void Show(FrameworkElement page)
        {
            bool wasEditor = EditorShown;
            PageFaces.Visibility = page == PageFaces ? Visibility.Visible : Visibility.Collapsed;
            Editor.Visibility = page == Editor ? Visibility.Visible : Visibility.Collapsed;
            PageFonts.Visibility = page == PageFonts ? Visibility.Visible : Visibility.Collapsed;
            if (page != Editor) Editor.StopWatching();
            // теки проєктів могли змінити ззовні — список читається заново
            if (page == PageFaces) { if (wasEditor) store.Reload(); RefreshProjects(); }
            if (page == PageFonts) RefreshFonts();
            if (page == Editor) Editor.Focus();
            if (wasEditor != EditorShown) EditorShownChanged?.Invoke(EditorShown);
        }

        public void ShowList() => Show(PageFaces);
        public void ShowFonts() => Show(PageFonts);

        void OpenProject(FaceProject p)
        {
            Editor.Open(p);
            Show(Editor);
        }

        /// <summary>Новий демонстраційний проєкт (для знімків екрана).</summary>
        public void Demo() => OpenProject(store.Create(S.Get("newFaceName"), DeviceProfile.Band10));

        /// <summary>Демо для знімків: arc, line, digits, xml, images, gallery, gallery2. Повертає вікно, яке знімати (null — головне).</summary>
        public Window Demo(string mode)
        {
            Demo();
            return Editor.DemoMode(mode);
        }

        /// <summary>Клавіші редактора; true — оброблено.</summary>
        public bool HandleKey(KeyEventArgs e)
        {
            if (!EditorShown) return false;
            // у полях введення клавіші належать полю
            if (Keyboard.FocusedElement is TextBox || Keyboard.FocusedElement is ComboBox || Keyboard.FocusedElement is ComboBoxItem) return false;
            return Editor.HandleKey(e);
        }

        void Fonts_Click(object sender, RoutedEventArgs e) => ShowFonts();
        void FontsBack_Click(object sender, RoutedEventArgs e) => ShowList();

        // MARK: Проєкти

        void RefreshProjects()
        {
            ProjectsPanel.Children.Clear();
            ProjectsPanel.Columns = GridColumns();
            foreach (var p in store.Projects) ProjectsPanel.Children.Add(Card(p));
            EmptyCard.Visibility = store.Projects.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        /// <summary>Колонок карток — як у магазині (StoreView.RenderList): картка не вужча за 218 px, від 2 до 6 в ряд</summary>
        int GridColumns()
        {
            double w = Math.Max(400, PageFaces.ActualWidth - 36);
            return Math.Max(2, Math.Min(6, (int)((w + 12) / 230)));
        }

        /// <summary>Вага готового .bin за ключем мініатюри (рахується у фоні разом з нею)</summary>
        readonly Dictionary<string, int> sizes = new Dictionary<string, int>();

        /// <summary>Новий дизайн — картка як у магазині: капсула, назва й кольори праворуч, «вага · дата», стилі, кнопка всередині</summary>
        FrameworkElement StoreCard(FaceProject p)
        {
            const double iw = 144, ih = 354;   // як капсула в картці магазину
            var img = new Image { Stretch = Stretch.UniformToFill };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            var inner = new Grid { Width = iw, Height = ih, Background = Brushes.Black, Clip = new RectangleGeometry(new Rect(0, 0, iw, ih), iw / 2, iw / 2) };
            inner.Children.Add(img);
            var capsule = new Border
            {
                Width = iw + 6, Height = ih + 6, CornerRadius = new CornerRadius((iw + 6) / 2), Padding = new Thickness(3), Child = inner, HorizontalAlignment = HorizontalAlignment.Center,
                Background = new SolidColorBrush(activeFaceId != null && activeFaceId == p.Root.Str("id") ? Color.FromRgb(0x22, 0xA8, 0x46) : Color.FromRgb(0x7A, 0x7A, 0x7A)),
            };
            var sp = new StackPanel();
            sp.Children.Add(capsule);

            // назва, праворуч кружечки кольорів
            var nameRow = new DockPanel { Margin = new Thickness(0, 14, 0, 0) };
            var colors = ColorVariants.Colors(p);
            if (colors.Count > 1)
            {
                var dots = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
                for (int i = 0; i < Math.Min(4, colors.Count); i++)
                {
                    Color c;
                    try { c = (Color)ColorConverter.ConvertFromString(colors[i]); } catch (Exception) { c = Colors.Gray; }
                    var dot = new System.Windows.Shapes.Ellipse { Width = 16, Height = 16, Fill = new SolidColorBrush(c), Stroke = (Brush)FindResource("Card"), StrokeThickness = 1.5, Margin = new Thickness(i == 0 ? 0 : -5, 0, 0, 0) };
                    Panel.SetZIndex(dot, 10 - i);
                    dots.Children.Add(dot);
                }
                if (colors.Count > 4) dots.Children.Add(new TextBlock { Text = "+" + (colors.Count - 4), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = (Brush)FindResource("Sub"), Margin = new Thickness(6, 0, 0, 0) });
                DockPanel.SetDock(dots, Dock.Right);
                nameRow.Children.Add(dots);
            }
            nameRow.Children.Add(new TextBlock { Text = p.DisplayName, FontSize = 15, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
            sp.Children.Add(nameRow);

            // «вага · дата», праворуч кількість стилів
            var key = p.Id + "#" + p.Revision + "#" + p.Meta.Modified.Ticks + "#" + ih;
            var metaRow = new DockPanel { Margin = new Thickness(0, 3, 0, 0) };
            int styles = StyleCount(p);
            if (styles > 1)
            {
                var st = new TextBlock { Text = BandFace.S.Get(styles % 10 >= 2 && styles % 10 <= 4 && (styles % 100 < 12 || styles % 100 > 14) ? "storeStyle2" : styles % 10 == 1 && styles % 100 != 11 ? "storeStyle1" : "storeStyle5", styles),
                    FontSize = 12, Foreground = (Brush)FindResource("Sub") };
                DockPanel.SetDock(st, Dock.Right);
                metaRow.Children.Add(st);
            }
            var date = p.Meta.Modified.ToLocalTime().ToString("d");
            var meta = new TextBlock { FontSize = 12, Foreground = (Brush)FindResource("Sub"), TextTrimming = TextTrimming.CharacterEllipsis,
                Text = sizes.TryGetValue(key, out var n0) ? SizeText(n0) + " · " + date : date };
            metaRow.Children.Add(meta);
            sp.Children.Add(metaRow);

            // кнопка встановлення — у картці на всю ширину
            var inst = new Button { Content = S.Get(installedIds.Contains(p.Root.Str("id") ?? "") ? "reinstallShort" : "installShort"), Style = (Style)FindResource("Btn"), Height = 32, Margin = new Thickness(0, 12, 0, 0) };
            inst.Click += (s, e) => { var bin = Actions.Build(Owner, p); if (bin != null) InstallRequested?.Invoke(bin, p.DisplayName); };
            sp.Children.Add(inst);

            var card = new Border { Style = (Style)FindResource("CardBox"), Margin = new Thickness(0, 0, 12, 12), Padding = new Thickness(14), Child = sp, Cursor = Cursors.Hand, ToolTip = p.DisplayName };
            card.MouseLeftButtonUp += (s, e) => { if (!(e.OriginalSource is DependencyObject o && InButton(o))) OpenProject(p); };
            card.ContextMenu = CardMenu(p);

            // мініатюра й вага — коли картки вже на екрані
            if (thumbs.TryGetValue(key, out var t0)) Sharp.Show(img, t0);
            Dispatcher.BeginInvoke(new Action(() =>
            {
                try
                {
                    if (img.Source == null)
                    {
                        double dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
                        var src = new FaceRenderer(p).Render(0, Math.Max(328, ih * dpi * 1.5) / p.Meta.Device.Height).Image;
                        thumbs[key] = src;
                        Sharp.Show(img, src);
                    }
                    if (!sizes.ContainsKey(key))
                    {
                        sizes[key] = p.Compile().Item1.Length;
                        meta.Text = SizeText(sizes[key]) + " · " + date;
                    }
                }
                catch (Exception) { }
            }), DispatcherPriority.Background);
            return card;
        }

        static bool InButton(DependencyObject o)
        {
            for (; o != null; o = o is Visual ? VisualTreeHelper.GetParent(o) : LogicalTreeHelper.GetParent(o))
                if (o is System.Windows.Controls.Primitives.ButtonBase) return true;
            return false;
        }

        static string SizeText(int bytes) => bytes >= 1024 * 1024 ? (bytes / 1048576.0).ToString("0.0") + " MB" : Math.Max(1, bytes / 1024) + " KB";

        /// <summary>Стилі: звичайні теми (у старих файлах без типів тем друга тема — AOD)</summary>
        static int StyleCount(FaceProject p) => Math.Max(1, p.StyleThemes().Count);

        ContextMenu CardMenu(FaceProject p)
        {
            var menu = new ContextMenu();
            Ui.MenuAdd(menu, S.Get("open"), "\uE8E5", () => OpenProject(p));
            Ui.MenuAdd(menu, S.Get("installBand"), "\uE896", () => { var bin = Actions.Build(Owner, p); if (bin != null) InstallRequested?.Invoke(bin, p.DisplayName); });
            Ui.MenuAdd(menu, S.Get("duplicate"), "\uE8C8", () => { store.Duplicate(p); RefreshProjects(); });
            Ui.MenuAdd(menu, S.Get("saveBin"), "\uE74E", () => Actions.ExportBin(Owner, p));
            Ui.MenuAdd(menu, S.Get("showInFolder"), "\uE838", () => { try { Process.Start("explorer.exe", "\"" + p.Folder + "\""); } catch (Exception) { } });
            menu.Items.Add(new Separator());
            Ui.MenuAdd(menu, S.Get("deleteFace"), "\uE74D", () =>
            {
                var ask = ProjectStore.IsExternal(p) ? S.Get("removeFaceAsk", p.DisplayName, p.Folder) : S.Get("deleteFaceAsk", p.DisplayName);
                if (MessageBox.Show(Owner, ask, "BandFace", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
                store.Delete(p);
                RefreshProjects();
            }, danger: true);
            return menu;
        }

        FrameworkElement Card(FaceProject p) => StoreCard(p);

        void New_Click(object sender, RoutedEventArgs e) => OpenProject(store.Create(S.Get("newFaceName"), DeviceProfile.Band10));

        void OpenBin_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog { Multiselect = true, Filter = S.Get("faceFilter") + "|*.bin;*.face" };
            if (dlg.ShowDialog(Owner) != true) return;
            foreach (var f in dlg.FileNames) OpenFile(f);
            if (dlg.FileNames.Length > 1) ShowList();
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
        public void OpenPath(string path)
        {
            if (Directory.Exists(path))
            {
                try
                {
                    if (!File.Exists(Path.Combine(path, "manifest.xml"))) throw new Exception(S.Get("notFace"));
                    OpenProject(store.ImportFolder(path));
                }
                catch (Exception ex) { MessageBox.Show(Owner, S.Get("openFail", Path.GetFileName(path), ex.Message), "BandFace", MessageBoxButton.OK, MessageBoxImage.Error); }
                return;
            }
            OpenFile(path);
        }

        /// <summary>Копія готового циферблата (з магазину) — новий проєкт, відкритий у редакторі; оригінал не змінюється</summary>
        public void OpenCopy(byte[] data, string name)
        {
            try { OpenProject(store.ImportBin(data, name, asCopy: true)); }
            catch (Exception ex) { MessageBox.Show(Owner, S.Get("openFail", name, ex.Message), "BandFace", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        public void OpenFile(string path)
        {
            try
            {
                var data = File.ReadAllBytes(path);
                if (data.Length < 0xA8 || BitConverter.ToUInt32(data, 0) != 0x1234A55A) throw new Exception(S.Get("notFace"));
                OpenProject(store.ImportBin(data, Path.GetFileNameWithoutExtension(path)));
            }
            catch (Exception ex)
            {
                MessageBox.Show(Owner, S.Get("openFail", Path.GetFileName(path), ex.Message), "BandFace", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        // MARK: Шрифти

        void AddFont_Click(object sender, RoutedEventArgs e)
        {
            Actions.AddFonts(Owner);
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
                    if (!FontLibrary.Remove(name)) MessageBox.Show(Owner, S.Get("removeFontNote"), "BandFace");
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
