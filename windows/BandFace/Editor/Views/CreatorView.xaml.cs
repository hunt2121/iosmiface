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

        public bool EditorShown => Editor.Visibility == Visibility.Visible;
        Window Owner => Window.GetWindow(this);

        public CreatorView()
        {
            InitializeComponent();
            ApplyTexts();
            Editor.BackRequested += ShowList;
            Editor.InstallRequested += (bin, name) => InstallRequested?.Invoke(bin, name);
            RefreshProjects();
        }

        void ApplyTexts()
        {
            TitleFaces.Text = S.Get("editor");
            NewBtn.Content = S.Get("newFace");
            OpenBinBtn.Content = S.Get("openBin");
            OpenFolderBtn.Content = S.Get("openFolder");
            FacesHint.Text = S.Get("facesHint");
            EmptyTitle.Text = S.Get("emptyTitle");
            EmptyText.Text = S.Get("emptyText");
        }

        // MARK: Сторінки

        void Show(FrameworkElement page)
        {
            bool wasEditor = EditorShown;
            PageFaces.Visibility = page == PageFaces ? Visibility.Visible : Visibility.Collapsed;
            Editor.Visibility = page == Editor ? Visibility.Visible : Visibility.Collapsed;
            if (page != Editor) Editor.StopWatching();
            // теки проєктів могли змінити ззовні — список читається заново
            if (page == PageFaces) { if (wasEditor) store.Reload(); RefreshProjects(); }
            if (page == Editor) Editor.Focus();
            if (wasEditor != EditorShown) EditorShownChanged?.Invoke(EditorShown);
        }

        public void ShowList() => Show(PageFaces);

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


        // MARK: Проєкти

        void RefreshProjects()
        {
            ProjectsPanel.Children.Clear();
            foreach (var p in store.Projects) ProjectsPanel.Children.Add(Card(p));
            EmptyCard.Visibility = store.Projects.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        FrameworkElement Card(FaceProject p)
        {
            // капсула така сама, як на вкладці «Циферблати»: 140×334, сіре обведення 3 px, вміст 134×328 (розмір офіційного превʼю) обрізано по капсулі,
            // картинка масштабується якісно (без змазування)
            var img = new Image { Stretch = Stretch.UniformToFill };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            var inner = new Grid { Width = 134, Height = 328, Background = Brushes.Black, Clip = new RectangleGeometry(new Rect(0, 0, 134, 328), 67, 67) };
            inner.Children.Add(img);
            var capsule = new Border
            {
                Width = 140, Height = 334, CornerRadius = new CornerRadius(70), Background = new SolidColorBrush(Color.FromRgb(0x7A, 0x7A, 0x7A)),
                Padding = new Thickness(3), Child = inner,
            };
            var sp = new StackPanel { Width = 170 };
            sp.Children.Add(capsule);
            sp.Children.Add(new TextBlock { Text = p.DisplayName, FontSize = 13, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 10, 0, 0) });
            sp.Children.Add(new TextBlock { Text = p.Meta.Modified.ToLocalTime().ToString("g"), FontSize = 11, Foreground = (Brush)FindResource("Sub"), TextAlignment = TextAlignment.Center });
            var card = new Border { Style = (Style)FindResource("CardBox"), Margin = new Thickness(0, 0, 14, 14), Padding = new Thickness(14), Child = sp, Cursor = Cursors.Hand, ToolTip = p.DisplayName };
            card.MouseLeftButtonUp += (s, e) => OpenProject(p);
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
            card.ContextMenu = menu;
            // мініатюра — коли картки вже на екрані
            var key = p.Id + "#" + p.Revision + "#" + p.Meta.Modified.Ticks;
            if (thumbs.TryGetValue(key, out var t0)) img.Source = t0;
            else Dispatcher.BeginInvoke(new Action(() =>
            {
                try
                {
                    double dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
                    var src = new FaceRenderer(p).Render(0, 328.0 / p.Meta.Device.Height * dpi).Image;
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
    }
}
