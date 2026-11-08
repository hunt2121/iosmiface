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
            Item(S.Get("installBand"), () => { var bin = Actions.Build(Owner, p); if (bin != null) InstallRequested?.Invoke(bin, p.DisplayName); });
            Item(S.Get("duplicate"), () => { store.Duplicate(p); RefreshProjects(); });
            Item(S.Get("saveBin"), () => Actions.ExportBin(Owner, p));
            Item(S.Get("showInFolder"), () => { try { Process.Start("explorer.exe", "\"" + p.Folder + "\""); } catch (Exception) { } });
            menu.Items.Add(new Separator());
            Item(S.Get("deleteFace"), () =>
            {
                var ask = ProjectStore.IsExternal(p) ? S.Get("removeFaceAsk", p.DisplayName, p.Folder) : S.Get("deleteFaceAsk", p.DisplayName);
                if (MessageBox.Show(Owner, ask, "BandFace", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
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
