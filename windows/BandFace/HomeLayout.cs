// SPDX-License-Identifier: MIT
// Тестові варіанти головного екрана (вмикаються в Налаштуваннях):
//   A — «велика сцена»: браслет у справжньому розмірі, пристрій — плашка біля заголовка, місце для перетягування файла;
//   B — «сцена й полиці»: менша сцена, нижче — циферблати на браслеті й нещодавні файли.
// Обидва — без підкладки навколо браслета. Ті самі елементи вікна переставляються, логіка встановлення не змінюється.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BandFace.Protocol;

namespace BandFace
{
    public partial class MainWindow
    {
        static readonly string[] HomeKeys = { "", "a", "b" };
        string _home = Storage.LoadText("homeLayout");
        List<WatchfaceEntry> _bandFaces;

        // MARK: Налаштування

        void FillHomeSetting()
        {
            RowHomeText.Text = S.Get("homeLayout");
            RowHomeDesc.Text = S.Get("homeLayoutDesc");
            HomeTestChip.Text = S.Get("testChip");
            HomeBox.Items.Clear();
            foreach (var k in new[] { "homeClassic", "homeA", "homeB" }) HomeBox.Items.Add(S.Get(k));
            HomeBox.SelectedIndex = Math.Max(0, Array.IndexOf(HomeKeys, _home));
        }

        void Home_Changed(object sender, SelectionChangedEventArgs e)
        {
            if (_loadingSettings || HomeBox.SelectedIndex < 0) return;
            _home = HomeKeys[HomeBox.SelectedIndex];
            Storage.SaveText("homeLayout", _home);
            ApplyHomeLayout();
        }

        // MARK: Розкладка

        /// <summary>Розмір капсули: зовнішній (з сірим обведенням 3 px) і внутрішній екран</summary>
        void SetCapsule(double innerW, double innerH)
        {
            Capsule.Width = innerW + 6; Capsule.Height = innerH + 6;
            Capsule.CornerRadius = new CornerRadius((innerW + 6) / 2);
            CapsuleInner.Width = innerW; CapsuleInner.Height = innerH;
            CapsuleInner.Clip = new RectangleGeometry(new Rect(0, 0, innerW, innerH), innerW / 2, innerW / 2);
        }

        void ApplyHomeLayout()
        {
            bool a = _home == "a", b = _home == "b";
            if (a) SetCapsule(212, 520);            // 1 піксель браслета = 1 точка Windows
            else if (b) SetCapsule(110, 270);
            else SetCapsule(96, 236);

            InstallInfo.Margin = new Thickness(a ? 36 : b ? 26 : 18, 0, 0, 0);
            InstallInfo.MaxWidth = a || b ? 440 : double.PositiveInfinity;
            InstallInfo.HorizontalAlignment = a || b ? HorizontalAlignment.Left : HorizontalAlignment.Stretch;
            FaceName.FontSize = a ? 26 : b ? 20 : 18;

            // A: головна кнопка на всю ширину, «Вибрати файл» під нею; інакше — поруч
            ButtonsGrid.ColumnDefinitions.Clear(); ButtonsGrid.RowDefinitions.Clear();
            if (a)
            {
                ButtonsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                ButtonsGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(10) });
                ButtonsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                Grid.SetColumn(InstallBtn, 0); Grid.SetRow(InstallBtn, 0);
                Grid.SetColumn(PickBtn, 0); Grid.SetRow(PickBtn, 2);
                InstallBtn.Height = 44; PickBtn.Height = 36;
            }
            else
            {
                ButtonsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                ButtonsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
                ButtonsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                // B, як на макеті: спершу «Встановити», потім «Вибрати файл»
                Grid.SetRow(InstallBtn, 0); Grid.SetRow(PickBtn, 0);
                Grid.SetColumn(PickBtn, b ? 2 : 0); Grid.SetColumn(InstallBtn, b ? 0 : 2);
                InstallBtn.Height = PickBtn.Height = 40;
            }

            DropZone.Visibility = a ? Visibility.Visible : Visibility.Collapsed;
            DropZoneText.Text = S.Get("dropZone");
            DropZoneSub.Text = S.Get("dropZoneSub");
            Shelves.Visibility = b ? Visibility.Visible : Visibility.Collapsed;
            BandShelfLabel.Text = S.Get("shelfBand").ToUpperInvariant();
            RecentShelfLabel.Text = S.Get("shelfRecent").ToUpperInvariant();
            PillDisconnectBtn.ToolTip = S.Get("disconnect");

            RefreshBand();
            if (_face != null) RefreshFace();   // превʼю — під новий розмір капсули
            if (b) { RefreshShelves(); _ = RefreshActiveFaceAsync(true); }
        }

        /// <summary>У тестових варіантах підключений пристрій — плашка біля заголовка замість картки</summary>
        void RefreshHomeBand(bool connected)
        {
            bool pill = _home.Length > 0 && connected;
            BandPill.Visibility = pill ? Visibility.Visible : Visibility.Collapsed;
            DeviceCard.Visibility = pill ? Visibility.Collapsed : Visibility.Visible;
            BandPillName.Text = BandName.Text;
            if (!connected) _bandFaces = null;
            if (_home == "b") RefreshShelves();
        }

        void DropZone_Click(object sender, MouseButtonEventArgs e) => Pick_Click(sender, e);

        // MARK: Превʼю циферблатів, які вже були у BandFace (браслет картинок не віддає)

        static string PreviewDir
        {
            get
            {
                var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BandFace", "previews");
                Directory.CreateDirectory(d);
                return d;
            }
        }

        static string PreviewPath(string id) => Path.Combine(PreviewDir, string.Concat((id ?? "").Where(char.IsLetterOrDigit)) + ".png");

        /// <summary>Запам'ятати превʼю циферблата за його ID: щоб показати його на полиці «На браслеті»</summary>
        static void RememberPreview(string id, BitmapSource img)
        {
            if (string.IsNullOrEmpty(id) || img == null) return;
            try
            {
                var enc = new PngBitmapEncoder();
                enc.Frames.Add(BitmapFrame.Create(img));
                using (var f = File.Create(PreviewPath(id))) enc.Save(f);
            }
            catch (Exception) { }
        }

        static BitmapSource CachedPreview(string id)
        {
            try
            {
                var p = PreviewPath(id);
                if (!File.Exists(p)) return null;
                var bmp = new BitmapImage();
                bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.UriSource = new Uri(p); bmp.EndInit(); bmp.Freeze();
                return bmp;
            }
            catch (Exception) { return null; }
        }

        // MARK: Нещодавні файли

        static List<string> RecentFiles() =>
            Storage.LoadText("recentFaces").Split('\n').Select(x => x.Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

        static void AddRecent(string path)
        {
            var l = RecentFiles();
            l.RemoveAll(x => string.Equals(x, path, StringComparison.OrdinalIgnoreCase));
            l.Insert(0, path);
            Storage.SaveText("recentFaces", string.Join("\n", l.Take(8)));
        }

        static void RemoveRecent(string path)
        {
            var l = RecentFiles();
            l.RemoveAll(x => string.Equals(x, path, StringComparison.OrdinalIgnoreCase));
            Storage.SaveText("recentFaces", string.Join("\n", l));
        }

        readonly Dictionary<string, Tuple<BitmapSource, string>> _thumbs = new Dictionary<string, Tuple<BitmapSource, string>>(StringComparer.OrdinalIgnoreCase);

        /// <summary>Мініатюра й назва файла циферблата (запам'ятовуються, доки файл не зміниться)</summary>
        BitmapSource FileThumb(string path, out string name)
        {
            name = Path.GetFileNameWithoutExtension(path);
            try
            {
                var key = path + "#" + File.GetLastWriteTimeUtc(path).Ticks;
                if (_thumbs.TryGetValue(key, out var t)) { name = t.Item2; return t.Item1; }
                var data = File.ReadAllBytes(path);
                try { name = new FaceFile(data).Name; } catch (Exception) { }
                double dpi = VisualTreeHelper.GetDpi(this).DpiScaleY;
                var shots = FacePreview.Render(data, 132 * dpi);
                var img = shots != null && shots.Frames.Count > 0 ? shots.Frames[0] : null;
                _thumbs[key] = Tuple.Create(img, name);
                return img;
            }
            catch (Exception) { return null; }
        }

        // MARK: Полиці

        const double ShelfW = 56, ShelfH = 132;

        /// <summary>Мала капсула з підписом; active — зелене обведення (увімкнений на браслеті)</summary>
        FrameworkElement ShelfTile(ImageSource img, string title, string sub, bool active, bool dashed)
        {
            var inner = new Grid { Width = ShelfW - 4, Height = ShelfH - 4, Background = Brushes.Black, Clip = new RectangleGeometry(new Rect(0, 0, ShelfW - 4, ShelfH - 4), (ShelfW - 4) / 2, (ShelfW - 4) / 2) };
            if (img != null)
            {
                var im = new Image { Source = img, Stretch = Stretch.UniformToFill };
                RenderOptions.SetBitmapScalingMode(im, BitmapScalingMode.HighQuality);
                inner.Children.Add(im);
            }
            FrameworkElement capsule;
            if (dashed)
            {
                // невідомий циферблат: порожня пунктирна капсула
                var g = new Grid { Width = ShelfW, Height = ShelfH };
                g.Children.Add(new System.Windows.Shapes.Rectangle { RadiusX = ShelfW / 2, RadiusY = ShelfW / 2, Stroke = (Brush)FindResource("Sub"), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 4, 3 }, Opacity = 0.6 });
                g.Children.Add(new TextBlock { Text = "", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 18, Foreground = (Brush)FindResource("Sub"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Opacity = 0.7 });
                capsule = g;
            }
            else
                capsule = new Border
                {
                    Width = ShelfW, Height = ShelfH, CornerRadius = new CornerRadius(ShelfW / 2), Padding = new Thickness(2), Child = inner,
                    Background = active ? (Brush)FindResource("Ok") : new SolidColorBrush(Color.FromRgb(0x7A, 0x7A, 0x7A)),
                };
            var sp = new StackPanel { Width = 84, Margin = new Thickness(0, 0, 8, 10), Cursor = Cursors.Hand, Background = Brushes.Transparent };
            sp.Children.Add(capsule);
            sp.Children.Add(new TextBlock { Text = title, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 6, 0, 0) });
            if (!string.IsNullOrEmpty(sub))
                sp.Children.Add(new TextBlock { Text = sub, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis, TextAlignment = TextAlignment.Center, Foreground = (Brush)FindResource(active ? "Ok" : "Sub") });
            sp.ToolTip = title;
            return sp;
        }

        void RefreshShelves()
        {
            if (_home != "b") return;
            // На браслеті
            BandShelf.Children.Clear();
            bool connected = _ble.IsConnected && !_connecting;
            if (!connected) BandShelfHint.Text = S.Get("shelfBandOff");
            else if (_bandFaces == null) BandShelfHint.Text = S.Get("shelfBandLoading");
            else
            {
                BandShelfHint.Text = S.Get("shelfBandHint");
                foreach (var f in _bandFaces)
                {
                    // превʼю: збережене під час встановлення чи відкриття файла, інакше — з проєкту редактора з тим самим ID
                    string pname = null;
                    ImageSource fromProject = EditorTab?.PreviewFor(f.Id, out pname);
                    ImageSource img = (ImageSource)CachedPreview(f.Id) ?? fromProject;
                    var title = f.Name ?? pname ?? ("ID " + f.Id);
                    var tile = ShelfTile(img, title, f.IsActive ? S.Get("shelfActive") : null, f.IsActive, img == null);
                    var entry = f;
                    tile.MouseLeftButtonUp += async (s, e) => { if (!entry.IsActive) await BandFaceCommandAsync(Command.ActivateWatchface(entry.Id), "activate"); };
                    if (entry.CanDelete)
                    {
                        var cm = new ContextMenu();
                        Creator.Ui.MenuAdd(cm, S.Get("shelfDelete"), "", async () =>
                        {
                            if (MessageBox.Show(this, S.Get("shelfDeleteAsk", title), "BandFace", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
                            await BandFaceCommandAsync(Command.DeleteWatchface(entry.Id), "delete");
                        }, danger: true);
                        tile.ContextMenu = cm;
                    }
                    BandShelf.Children.Add(tile);
                }
            }

            // Нещодавні
            RecentShelf.Children.Clear();
            var files = RecentFiles().Where(File.Exists).ToList();
            foreach (var path in files)
            {
                var img = FileThumb(path, out var name);
                var tile = ShelfTile(img, name, null, false, img == null);
                var p = path;
                tile.MouseLeftButtonUp += (s, e) => { if (!_busy) LoadFaceFile(p); };
                var cm = new ContextMenu();
                Creator.Ui.MenuAdd(cm, S.Get("shelfForget"), "", () => { RemoveRecent(p); RefreshShelves(); });
                tile.ContextMenu = cm;
                tile.ToolTip = p;
                RecentShelf.Children.Add(tile);
            }
            RecentShelfHint.Text = files.Count == 0 ? S.Get("shelfRecentEmpty") : S.Get("shelfRecentHint");
        }

        /// <summary>Увімкнути або видалити циферблат на браслеті, потім оновити список</summary>
        async Task BandFaceCommandAsync(byte[] cmd, string what)
        {
            var key = Bytes.ParseHex(KeyBox.Text);
            if (key == null || key.Length != 16 || !_ble.IsConnected || _connecting || _busy) return;
            await _bandGate.WaitAsync();
            var session = new BandSession(_ble, NewConfig());
            _session = session;
            try
            {
                await session.OpenAsync();
                await session.AuthenticateAsync(key, "Windows PC", "UK", Command.PhoneInfoMiFitness(Region()));
                try { await session.CommandAsync(Command.AfterAuthMiFitness, 3000); } catch (BandException) { }
                await session.CommandAsync(cmd);
                try { await session.CloseAsync(); } catch (Exception) { }
                AddLog("faces " + what + ": ok");
            }
            catch (Exception ex) { AddLog("faces " + what + ": " + ex.Message); SetStatus(Describe(ex), true); }
            finally { try { session.Dispose(); } catch (Exception) { } _session = null; _bandGate.Release(); }
            await RefreshActiveFaceAsync(true);
        }
    }
}
