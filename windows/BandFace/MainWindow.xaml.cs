using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using BandFace.Protocol;
using Microsoft.Win32;

namespace BandFace
{
    /// <summary>
    /// Головне вікно: вкладки як в iOS-версії — Циферблати, Магазин (поки неактивний), Редактор, Налаштування.
    /// У редакторі бічне меню згортається до смуги іконок.
    /// </summary>
    public partial class MainWindow : Window
    {
        const double SideWide = 228, SideNarrow = 56;

        readonly BleTransport _ble = new BleTransport();
        readonly StringBuilder _log = new StringBuilder();
        readonly HashSet<ulong> _seen = new HashSet<ulong>();
        BandSession _session;
        FaceFile _face;
        string _faceFile = "";
        bool _busy, _dev, _connecting, _compact, _flyout, _loadingSettings;
        string _version = "";

        public MainWindow()
        {
            InitializeComponent();
            _dev = Storage.LoadDev();
            DevSwitch.IsChecked = _dev;
            KeyBox.Text = Storage.LoadKey();
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            _version = v.Major + "." + v.Minor + "." + v.Build;
            VersionText.Text = "v" + _version;
            VersionValue.Text = _version;
            ApplyTexts();
            UpdateSidebar();
            FillSettings();
            RefreshBand();
            RefreshFace();
            RefreshKeyState();
            _ble.Info += m => Dispatcher.BeginInvoke(new Action(() => AddLog(m)));
            _ble.Data += b => _session?.Receive(b);
            _ble.Disconnected += () => Dispatcher.BeginInvoke(new Action(() => { _session?.ConnectionLost(); AddLog("disconnected"); RefreshBand(); }));
            _ble.Restored += () => Dispatcher.BeginInvoke(new Action(() => { AddLog("connected again"); RefreshBand(); }));
            AddLog("BandFace " + _version + " started");

            EditorTab.EditorShownChanged += shown => UpdateSidebar();
            EditorTab.InstallRequested += (bin, name) => InstallFromEditor(bin, name);
            PreviewKeyDown += (s, e) => { if (NavEditor.IsChecked == true && EditorTab.HandleKey(e)) e.Handled = true; };
            DragEnter += Window_DragEnter; DragOver += Window_DragEnter; DragLeave += (s, e) => DropHint.Visibility = Visibility.Collapsed;
            Drop += Window_Drop;

            string shot = null, openFile = null;
            foreach (var a in Environment.GetCommandLineArgs().Skip(1))
            {
                if (a == "--page=settings") NavSettings.IsChecked = true;
                else if (a == "--page=key") { NavSettings.IsChecked = true; ShowSettingsPage(PageKey); }
                else if (a == "--page=log") { NavSettings.IsChecked = true; ShowSettingsPage(PageLog); }
                else if (a == "--page=editor") NavEditor.IsChecked = true;
                else if (a == "--page=fonts") { NavEditor.IsChecked = true; EditorTab.ShowFonts(); }
                else if (a == "--demo") { NavEditor.IsChecked = true; EditorTab.Demo(); }
                else if (a.StartsWith("--shot=")) shot = a.Substring(7);
                else if (!a.StartsWith("--") && File.Exists(a)) openFile = a;
            }
            if (shot != null)
                ContentRendered += async (s, e) =>
                {
                    await Task.Delay(1500);
                    try { SaveShot(shot); } catch (Exception ex) { File.WriteAllText(shot + ".txt", ex.ToString()); }
                    Application.Current.Shutdown();
                };
            else
                ContentRendered += async (s, e) =>
                {
                    // .bin, відкритий подвійним кліком: спитати, що з ним робити (як в iOS)
                    if (openFile != null) AskAboutFile(openFile);
                    await AutoConnectAsync();
                };
            SourceInitialized += (s, e) => Theme.Apply(this);
            SystemEvents.UserPreferenceChanged += (s, e) => Dispatcher.BeginInvoke(new Action(() => Theme.Apply(this)));
            Closed += (s, e) => { _ble.StopScan(); _ble.Disconnect(); };
        }

        /// <summary>Параметри відкриття сесії, як у Mi Fitness.</summary>
        SessionConfig NewConfig()
        {
            Func<int, byte[], KeyValuePair<int, byte[]>> kv = (k, v) => new KeyValuePair<int, byte[]>(k, v);
            return new SessionConfig
            {
                Log = m => Dispatcher.BeginInvoke(new Action(() => AddLog(m))),
                // Band 10 підтверджує 6 частин раз на ~3–4 с незалежно від адаптера (журнал: пакет 514 байтів, ~8 КБ/с) —
                // з тайм-аутом 3 с ми надсилали частини повторно й лише гальмували передачу. 10 с — лише затримка
                // відновлення, якщо частина справді загубилася.
                FileAckTimeoutMs = 10000,
                OpenParameters = new List<KeyValuePair<int, byte[]>>
                {
                    kv(1, new byte[] { 0x01, 0x00, 0x00 }), kv(7, new byte[] { 0x1b, 0x02, 0x00 }), kv(2, new byte[] { 0xff, 0xff }),
                    kv(5, new byte[] { 0x01 }), kv(6, Encoding.ASCII.GetBytes("iPhone")), kv(3, new byte[] { 0x10, 0x00 }), kv(4, new byte[] { 0x98, 0x3a }),
                },
            };
        }

        static string Region()
        {
            try { var r = System.Globalization.RegionInfo.CurrentRegion.TwoLetterISORegionName; return r.Length == 2 ? r : "UA"; }
            catch (Exception) { return "UA"; }
        }

        bool KeyValid { get { var k = Bytes.ParseHex(KeyBox.Text); return k != null && k.Length == 16; } }

        /// <summary>Одразу після підключення проходимо автентифікацію: браслет виходить з екрана налаштувань.</summary>
        async Task ActivateAsync()
        {
            var key = Bytes.ParseHex(KeyBox.Text);
            if (key == null || key.Length != 16 || !_ble.IsConnected) return;
            SetStatus(S.Get("phPair"), false);
            var session = new BandSession(_ble, NewConfig());
            _session = session;
            try
            {
                await session.OpenAsync();
                await session.AuthenticateAsync(key, "Windows PC", "UK", Command.PhoneInfoMiFitness(Region()));
                try { await session.CommandAsync(Command.AfterAuthMiFitness, 3000); } catch (BandException) { }
                await Task.Delay(300);
                await session.CloseAsync();
                AddLog("connect activate: ok");
                SetStatus("", false);
            }
            catch (Exception ex) { AddLog("connect activate: " + ex.Message); SetStatus(Describe(ex), true); }
            finally { try { session.Dispose(); } catch (Exception) { } _session = null; }
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

        void ApplyTexts()
        {
            NavFacesText.Text = TitleFaces.Text = S.Get("faces");
            NavStoreText.Text = S.Get("store");
            StoreChipText.Text = S.Get("soon");
            NavStore.ToolTip = S.Get("store") + " · " + S.Get("soon").ToLowerInvariant();
            NavEditorText.Text = S.Get("editor");
            NavSettingsText.Text = TitleSettings.Text = S.Get("settings");
            MenuBtn.ToolTip = S.Get("menu");
            KeyNoticeLabel.Text = S.Get("key").ToUpperInvariant();
            AddKeyBtn.Content = S.Get("addKey");
            KeyNoticeText.Text = S.Get("addKeyNote");
            DeviceSectionLabel.Text = S.Get("device").ToUpperInvariant();
            AppSectionLabel.Text = S.Get("appSection").ToUpperInvariant();
            RowKeyText.Text = TitleKey.Text = S.Get("key");
            RowLogText.Text = TitleLog.Text = S.Get("log");
            RowThemeText.Text = S.Get("theme");
            RowLangText.Text = S.Get("language");
            RowVersionText.Text = S.Get("version");
            KeyBackBtn.ToolTip = LogBackBtn.ToolTip = S.Get("settings");
            BandLabel.Text = S.Get("band").ToUpperInvariant();
            InstallLabel.Text = S.Get("installCard").ToUpperInvariant();
            KeyLabel.Text = S.Get("keyTitle").ToUpperInvariant();
            ActivityLabel.Text = S.Get("activity").ToUpperInvariant();
            DisconnectBtn.Content = S.Get("disconnect");
            PasteBtn.Content = S.Get("paste");
            FromFileBtn.Content = S.Get("fromFile");
            KeyNote.Text = S.Get("keyNote");
            CloudLabel.Text = S.Get("cloudTitle").ToUpperInvariant();
            CloudBtn.Content = S.Get("cloudBtn");
            CloudCancelBtn.Content = S.Get("cloudCancel");
            CloudNote.Text = S.Get("cloudNote");
            DevLabel.Text = S.Get("dev");
            CopyBtn.Content = S.Get("copy");
            ClearBtn.Content = S.Get("clear");
            LogFileBtn.Content = S.Get("logFile");
            InstallBtn.Content = S.Get("install");
            DropText.Text = S.Get("dropHint");
            Title = "BandFace";
        }

        // ---------- Вкладки й бічне меню ----------

        void Nav_Checked(object sender, RoutedEventArgs e)
        {
            // під час InitializeComponent (NavFaces IsChecked) решти елементів ще немає
            if (NavSettings == null || EditorTab == null) return;
            bool editor = NavEditor.IsChecked == true;
            PagesHost.Visibility = editor ? Visibility.Collapsed : Visibility.Visible;
            EditorTab.Visibility = editor ? Visibility.Visible : Visibility.Collapsed;
            if (NavFaces.IsChecked == true) ShowPage(PageFaces);
            if (NavSettings.IsChecked == true) ShowPage(PageSettings);
            CloseFlyout();
            UpdateSidebar();
        }

        void ShowPage(FrameworkElement page)
        {
            foreach (var p in new FrameworkElement[] { PageFaces, PageSettings, PageKey, PageLog })
                p.Visibility = p == page ? Visibility.Visible : Visibility.Collapsed;
        }

        void ShowSettingsPage(FrameworkElement page)
        {
            ShowPage(page);
            if (page == PageLog) LogText.Text = _log.ToString();
        }

        void OpenKey_Click(object sender, RoutedEventArgs e) => ShowSettingsPage(PageKey);
        void OpenLog_Click(object sender, RoutedEventArgs e) => ShowSettingsPage(PageLog);
        void SettingsBack_Click(object sender, RoutedEventArgs e) => ShowPage(PageSettings);

        void AddKey_Click(object sender, RoutedEventArgs e)
        {
            NavSettings.IsChecked = true;
            ShowSettingsPage(PageKey);
        }

        /// <summary>У відкритому редакторі меню — вузька смуга іконок; на інших вкладках — повне.</summary>
        void UpdateSidebar()
        {
            _compact = NavEditor.IsChecked == true && EditorTab.EditorShown;
            if (!_compact) _flyout = false;
            bool wide = !_compact || _flyout;
            Sidebar.Width = wide ? SideWide : SideNarrow;
            ContentHost.Margin = new Thickness(_compact ? SideNarrow : SideWide, 0, 0, 0);
            var textVis = wide ? Visibility.Visible : Visibility.Collapsed;
            foreach (var t in new FrameworkElement[] { NavFacesText, NavStoreText, StoreChip, NavEditorText, NavSettingsText })
                t.Visibility = textVis;
            VersionText.Text = wide ? "v" + _version : _version;
            VersionText.Margin = new Thickness(wide ? 12 : 0, 0, 0, 6);
            VersionText.FontSize = wide ? 12 : 10;
            MenuBtn.Visibility = _compact ? Visibility.Visible : Visibility.Collapsed;
            Shade.Visibility = _flyout ? Visibility.Visible : Visibility.Collapsed;
            Sidebar.Effect = _flyout ? new DropShadowEffect { BlurRadius = 24, ShadowDepth = 4, Direction = 0, Opacity = 0.25 } : null;
            // у вузькій смузі назва вкладки — підказкою
            NavFaces.ToolTip = wide ? null : S.Get("faces");
            NavEditor.ToolTip = wide ? null : S.Get("editor");
            NavSettings.ToolTip = wide ? null : S.Get("settings");
        }

        void Menu_Click(object sender, RoutedEventArgs e) { _flyout = !_flyout; UpdateSidebar(); }
        void Shade_MouseDown(object sender, MouseButtonEventArgs e) => CloseFlyout();
        void CloseFlyout() { if (_flyout) { _flyout = false; UpdateSidebar(); } }

        // ---------- Налаштування: тема й мова ----------

        static readonly string[] ThemeKeys = { "system", "light", "dark" };
        static readonly string[] LangKeys = { "", "uk", "en", "ru" };

        void FillSettings()
        {
            _loadingSettings = true;
            ThemeBox.Items.Clear();
            foreach (var k in new[] { "themeSystem", "themeLight", "themeDark" }) ThemeBox.Items.Add(S.Get(k));
            ThemeBox.SelectedIndex = Math.Max(0, Array.IndexOf(ThemeKeys, Theme.Mode));
            LangBox.Items.Clear();
            LangBox.Items.Add(S.Get("langSystem"));
            LangBox.Items.Add("Українська");
            LangBox.Items.Add("English");
            LangBox.Items.Add("Русский");
            LangBox.SelectedIndex = Math.Max(0, Array.IndexOf(LangKeys, Storage.LoadText("lang")));
            _loadingSettings = false;
        }

        void Theme_Changed(object sender, SelectionChangedEventArgs e)
        {
            if (_loadingSettings || ThemeBox.SelectedIndex < 0) return;
            Theme.Mode = ThemeKeys[ThemeBox.SelectedIndex];
            Storage.SaveText("theme", Theme.Mode == "system" ? "" : Theme.Mode);
            Theme.Apply(this);
        }

        void Lang_Changed(object sender, SelectionChangedEventArgs e)
        {
            if (_loadingSettings || LangBox.SelectedIndex < 0) return;
            Storage.SaveText("lang", LangKeys[LangBox.SelectedIndex]);
            // тексти беруться під час запуску — пропонуємо перезапуститися
            if (_busy || MessageBox.Show(this, S.Get("restartAsk"), "BandFace", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            try { Process.Start(Assembly.GetExecutingAssembly().Location); Application.Current.Shutdown(); } catch (Exception) { }
        }

        // ---------- Браслет ----------
        void RefreshBand()
        {
            bool c = _ble.IsConnected;
            BandConnected.Visibility = c ? Visibility.Visible : Visibility.Collapsed;
            BandIdle.Visibility = c ? Visibility.Collapsed : Visibility.Visible;
            BandName.Text = _ble.ConnectedName ?? "";
            BandStatus.Text = S.Get("connected");
            BandNone.Text = S.Get("notConnected");
            ScanBtn.Content = S.Get(_connecting ? "phConnect" : "scan");
            ScanBtn.IsEnabled = !_connecting;
            InstallBtn.IsEnabled = !_busy && _face != null;
        }

        void Scan_Click(object sender, RoutedEventArgs e)
        {
            DeviceList.Children.Clear();
            _seen.Clear();
            ScanBtn.Content = S.Get("scanning");
            try
            {
                _ble.StartScan(f => Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (!_seen.Add(f.Address)) return;
                    var b = new Button { Content = f.Name, Style = (Style)FindResource("Btn"), Height = 34, HorizontalContentAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 6), Padding = new Thickness(14, 0, 14, 0) };
                    b.Click += async (s, a) => await ConnectTo(f.Address, f.Name, false);
                    DeviceList.Children.Add(b);
                })));
            }
            catch (Exception) { SetStatus(S.Get("noBle"), true); ScanBtn.Content = S.Get("scan"); }
        }

        /// <summary>auto — автопідключення під час запуску: тихо, з наявним спарюванням.</summary>
        async Task<bool> ConnectTo(ulong address, string name, bool auto)
        {
            if (_connecting) return false;
            _connecting = true;
            _ble.StopScan();
            DeviceList.Children.Clear();
            RefreshBand();
            SetStatus(auto ? S.Get("autoConnecting", name) : S.Get("phPair"), false);
            bool ok = false;
            try
            {
                await _ble.ConnectAsync(address, auto);
                AddLog("connected " + name + (auto ? " (auto)" : ""));
                Storage.SaveText("band", address.ToString("X") + "|" + name);
                Storage.SaveText("auto", "1");
                SetStatus("", false);
                ok = true;
                _connecting = false;
                RefreshBand();
                await ActivateAsync();
            }
            catch (Exception ex)
            {
                AddLog("connect: " + ex.Message);
                if (auto) SetStatus("", false);   // браслета поруч немає — просто показуємо «Не підключено»
                else SetStatus(Describe(ex), true);
            }
            finally { _connecting = false; RefreshBand(); }
            return ok;
        }

        /// <summary>Як в iOS: під час запуску підключаємося до браслета, з яким працювали минулого разу.</summary>
        async Task AutoConnectAsync()
        {
            if (Storage.LoadText("auto") != "1" || !KeyValid || _ble.IsConnected) return;
            var saved = Storage.LoadText("band").Split('|');
            ulong address;
            if (saved.Length < 2 || !ulong.TryParse(saved[0], System.Globalization.NumberStyles.HexNumber, null, out address)) return;
            await ConnectTo(address, saved[1], true);
        }

        void Disconnect_Click(object sender, RoutedEventArgs e)
        {
            _ble.Disconnect();
            // «Від'єднати» вимикає автопідключення до наступного ручного підключення
            Storage.SaveText("auto", "");
            AddLog("disconnected by user");
            RefreshBand();
        }

        // ---------- Циферблат ----------
        void Pick_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog { Filter = "Watch face (*.bin;*.face)|*.bin;*.face|*.*|*.*" };
            if (dlg.ShowDialog(this) != true) return;
            LoadFaceFile(dlg.FileName);
        }

        bool LoadFaceFile(string path)
        {
            try { return LoadFace(File.ReadAllBytes(path), Path.GetFileName(path)); }
            catch (Exception) { return LoadFace(null, Path.GetFileName(path)); }
        }

        bool LoadFace(byte[] data, string fileName)
        {
            try
            {
                if (data == null) throw new InvalidDataException();
                _face = new FaceFile(data);
                _faceFile = fileName;
                SetStatus("", false);
            }
            catch (Exception) { _face = null; SetStatus(S.Get("errFace"), true); }
            RefreshFace();
            return _face != null;
        }

        void RefreshFace()
        {
            if (_face == null)
            {
                FaceName.Text = S.Get("noFile");
                FaceInfo.Text = S.Get("format");
                FaceFileName.Text = S.Get("pickHint");
                PickBtn.Content = S.Get("pick");
                PreviewImage.Source = null;
            }
            else
            {
                FaceName.Text = _face.Name;
                FaceInfo.Text = "ID " + _face.Id + " · " + (_face.Size + 512) / 1024 + " " + S.Get("kb");
                FaceFileName.Text = _faceFile;
                PickBtn.Content = S.Get("pickOther");
                PreviewImage.Source = null;
                try
                {
                    var p = _face.DecodePreview();
                    if (p != null)
                    {
                        var bmp = BitmapSource.Create(p.Width, p.Height, 96, 96, PixelFormats.Bgra32, null, p.Bgra, p.Width * 4);
                        bmp.Freeze();
                        PreviewImage.Source = bmp;
                    }
                }
                catch (Exception) { }
            }
            InstallBtn.IsEnabled = !_busy && _face != null;
        }

        async void Install_Click(object sender, RoutedEventArgs e) => await InstallAsync();

        /// <summary>Циферблат з редактора — звичним шляхом вкладки «Циферблати» (як в iOS).</summary>
        async void InstallFromEditor(byte[] bin, string name)
        {
            if (_busy) return;
            NavFaces.IsChecked = true;
            if (!LoadFace(bin, name + ".bin")) return;
            await InstallAsync();
        }

        async Task InstallAsync()
        {
            if (_busy || _face == null) return;
            var key = Bytes.ParseHex(KeyBox.Text);
            if (key == null || key.Length != 16) { SetStatus(S.Get("keyInvalid"), true); return; }
            if (!_ble.IsConnected) { SetStatus(S.Get("errConnect"), true); return; }
            _busy = true; InstallBtn.IsEnabled = false; PickBtn.IsEnabled = false;
            SetStatus("", false);
            ProgressPanel.Visibility = Visibility.Visible;
            Bar.Value = 0; ProgressPercent.Text = ""; ProgressText.Text = S.Get("phConnect");
            _session = new BandSession(_ble, NewConfig());
            try
            {
                // параметри входу точно як у Mi Fitness / iOS-версії (з іншими Band 10 розриває з'єднання після входу)
                var inst = new WatchfaceInstaller { PhoneInfo = Command.PhoneInfoMiFitness(Region()) };
                inst.CommandsAfterAuth.Add(Command.AfterAuthMiFitness);
                bool already = false;
                await inst.InstallAsync(_face, key, _session, p => Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (p.AlreadyInstalled) already = true;
                    switch (p.Phase)
                    {
                        case Phase.Connecting: ProgressText.Text = S.Get("phConnect"); break;
                        case Phase.Authenticating: ProgressText.Text = S.Get("phAuth"); break;
                        case Phase.RequestingInstall: ProgressText.Text = S.Get("phInstall"); break;
                        case Phase.RemovingOldVersion: ProgressText.Text = S.Get("phRemove"); break;
                        case Phase.Activating: ProgressText.Text = S.Get("phActivate"); break;
                        case Phase.Uploading:
                            double f = p.Total > 0 ? (double)p.Sent / p.Total : 0;
                            Bar.Value = f;
                            ProgressText.Text = S.Get("progress", p.Sent, p.Total);
                            ProgressPercent.Text = (int)(f * 100) + "%";
                            break;
                    }
                })));
                SetStatus(S.Get(already ? "doneOld" : "doneNew"), false, true);
            }
            catch (Exception ex) { SetStatus(Describe(ex), true); AddLog("install: " + ex.Message); }
            finally
            {
                try { _session.Dispose(); } catch (Exception) { }
                _session = null;
                ProgressPanel.Visibility = Visibility.Collapsed;
                _busy = false; PickBtn.IsEnabled = true; RefreshBand();
            }
        }

        // ---------- Відкриття файлів: подвійний клік і перетягування ----------

        static string[] Dropped(DragEventArgs e) => e.Data.GetDataPresent(DataFormats.FileDrop) ? (string[])e.Data.GetData(DataFormats.FileDrop) : new string[0];

        static bool IsFace(string f) => f.EndsWith(".bin", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".face", StringComparison.OrdinalIgnoreCase);

        void Window_DragEnter(object sender, DragEventArgs e)
        {
            bool ok = Dropped(e).Any(f => IsFace(f) || Directory.Exists(f));
            e.Effects = ok ? DragDropEffects.Copy : DragDropEffects.None;
            DropHint.Visibility = ok ? Visibility.Visible : Visibility.Collapsed;
            e.Handled = true;
        }

        void Window_Drop(object sender, DragEventArgs e)
        {
            DropHint.Visibility = Visibility.Collapsed;
            var files = Dropped(e);
            // один .bin — спитати, що з ним робити; тека розпакованого циферблата або кілька файлів — одразу в редактор
            if (files.Length == 1 && IsFace(files[0])) { AskAboutFile(files[0]); return; }
            foreach (var f in files.Where(f => IsFace(f) || Directory.Exists(f)))
            {
                NavEditor.IsChecked = true;
                EditorTab.OpenPath(f);
            }
        }

        /// <summary>Як в iOS: «Встановити на пристрій» / «Відкрити в редакторі» / «Скасувати».</summary>
        void AskAboutFile(string path)
        {
            switch (FileActionDialog.Ask(this, Path.GetFileName(path)))
            {
                case 1:
                    NavFaces.IsChecked = true;
                    if (LoadFaceFile(path) && _ble.IsConnected && KeyValid) _ = InstallAsync();
                    else if (_face != null && !_ble.IsConnected) SetStatus(S.Get("errConnect"), true);
                    break;
                case 2:
                    NavEditor.IsChecked = true;
                    EditorTab.OpenFile(path);
                    break;
            }
        }

        string Describe(Exception ex)
        {
            var be = ex as BandException;
            if (be == null) return S.Get("errGeneric", ex.Message);
            switch (be.Kind)
            {
                case ErrorKind.InvalidAuthKey:
                case ErrorKind.AuthKeyMismatch:
                case ErrorKind.NotAuthenticated: return S.Get("errAuth");
                case ErrorKind.Timeout:
                case ErrorKind.SessionOpenFailed: return S.Get("errTimeout");
                case ErrorKind.NotConnected: return S.Get("errConnect");
                case ErrorKind.InvalidFaceFile:
                case ErrorKind.InvalidPreview: return S.Get("errFace");
                case ErrorKind.CharacteristicNotFound: return S.Get("errService");
                case ErrorKind.Disconnected: return S.Get("errLost");
                case ErrorKind.InstallRejected:
                case ErrorKind.UploadRejected:
                case ErrorKind.InstallAborted:
                case ErrorKind.ActivationFailed: return S.Get("errInstall", be.Status);
                default: return S.Get("errGeneric", be.Kind);
            }
        }

        void SetStatus(string text, bool error, bool ok = false)
        {
            StatusText.Text = text;
            StatusText.Foreground = (Brush)FindResource(error ? "Err" : ok ? "Ok" : "Sub");
        }

        // ---------- Ключ ----------
        static readonly Regex Hex32 = new Regex("(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])");

        /// <summary>Червоний «!» на вкладці Налаштування, підказка на Циферблатах, позначка в рядку «Ключ».</summary>
        void RefreshKeyState()
        {
            bool ok = KeyValid;
            KeyBadge.Visibility = ok ? Visibility.Collapsed : Visibility.Visible;
            KeyNotice.Visibility = ok ? Visibility.Collapsed : Visibility.Visible;
            KeyStateIcon.Text = ok ? "" : "";
            KeyStateIcon.Foreground = (Brush)FindResource(ok ? "Ok" : "Err");
        }

        void KeyBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            var b = Bytes.ParseHex(KeyBox.Text);
            if (b != null && b.Length == 16) { Storage.SaveKey(Bytes.ToHexLower(b)); KeyMessage.Text = S.Get("keySaved"); KeyMessage.Foreground = (Brush)FindResource("Ok"); }
            else if (KeyBox.Text.Length > 0) { KeyMessage.Text = S.Get("keyInvalid"); KeyMessage.Foreground = (Brush)FindResource("Err"); }
            else KeyMessage.Text = "";
            if (KeyBadge != null) RefreshKeyState();
        }

        void Paste_Click(object sender, RoutedEventArgs e)
        {
            try { if (Clipboard.ContainsText()) KeyBox.Text = Clipboard.GetText().Trim(); } catch (Exception) { }
        }

        void FromFile_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog();
            if (dlg.ShowDialog(this) != true) return;
            try
            {
                var bytes = File.ReadAllBytes(dlg.FileName);
                var m = Hex32.Match(Encoding.UTF8.GetString(bytes));
                if (m.Success) { KeyBox.Text = m.Value.ToLowerInvariant(); KeyMessage.Text = S.Get("keyFound"); KeyMessage.Foreground = (Brush)FindResource("Ok"); }
                else { KeyMessage.Text = S.Get("keyNone"); KeyMessage.Foreground = (Brush)FindResource("Err"); }
            }
            catch (Exception) { KeyMessage.Text = S.Get("keyNone"); KeyMessage.Foreground = (Brush)FindResource("Err"); }
        }

        // ---------- Ключ з акаунта Xiaomi ----------
        System.Threading.CancellationTokenSource _cloudCts;

        void CloudCancel_Click(object sender, RoutedEventArgs e) { _cloudCts?.Cancel(); }

        void CloudStatusSet(string t, bool err = false)
        {
            CloudStatus.Text = t;
            CloudStatus.Foreground = (Brush)FindResource(err ? "Err" : "Sub");
        }

        async void Cloud_Click(object sender, RoutedEventArgs e)
        {
            if (_cloudCts != null) return;
            _cloudCts = new System.Threading.CancellationTokenSource();
            CloudBtn.IsEnabled = false; CloudCancelBtn.Visibility = Visibility.Visible;
            CloudDevices.Children.Clear();
            try
            {
                var qr = await XiaomiCloud.StartAsync();
                var bmp = new BitmapImage();
                using (var ms = new MemoryStream(qr.Image))
                {
                    bmp.BeginInit(); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.StreamSource = ms; bmp.EndInit();
                }
                bmp.Freeze();
                QrImage.Source = bmp; QrImage.Visibility = Visibility.Visible;
                CloudStatusSet(S.Get("cloudScan"));
                var login = await XiaomiCloud.WaitAsync(qr, _cloudCts.Token);
                QrImage.Visibility = Visibility.Collapsed;
                CloudStatusSet(S.Get("cloudGet"));
                var devs = await XiaomiCloud.DevicesAsync(login, m => Dispatcher.BeginInvoke(new Action(() => AddLog("cloud " + m))));
                if (devs.Count == 0) CloudStatusSet(S.Get("cloudNone"), true);
                else if (devs.Count == 1) { KeyBox.Text = devs[0].Key; CloudStatusSet(S.Get("keyFound")); }
                else
                {
                    CloudStatusSet(S.Get("cloudPick"));
                    foreach (var d in devs)
                    {
                        var dev = d;
                        var b = new Button { Content = dev.ToString() + "  ·  " + dev.Model, Style = (Style)FindResource("Btn"), Height = 34, HorizontalContentAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 6), Padding = new Thickness(14, 0, 14, 0) };
                        b.Click += (s2, a2) => { KeyBox.Text = dev.Key; CloudStatusSet(S.Get("keyFound")); CloudDevices.Children.Clear(); };
                        CloudDevices.Children.Add(b);
                    }
                }
            }
            catch (OperationCanceledException) { CloudStatusSet(""); }
            catch (Exception ex) { CloudStatusSet(S.Get("cloudFail", ex.Message), true); AddLog("cloud: " + ex.Message); }
            finally
            {
                QrImage.Visibility = Visibility.Collapsed;
                _cloudCts = null; CloudBtn.IsEnabled = true; CloudCancelBtn.Visibility = Visibility.Collapsed;
            }
        }

        // ---------- Журнал ----------
        void AddLog(string m)
        {
            if (!_dev && !m.StartsWith("connected") && !m.StartsWith("install") && !m.StartsWith("connect") && !m.StartsWith("disc") && !m.StartsWith("BandFace")) return;
            string line = DateTime.Now.ToString("HH:mm:ss") + " " + m;
            _log.AppendLine(line);
            Storage.AppendLog(DateTime.Now.ToString("yyyy-MM-dd ") + line);
            if (_log.Length > 60000) _log.Remove(0, 20000);
            if (PageLog.Visibility == Visibility.Visible) LogText.Text = _log.ToString();
        }

        void Dev_Click(object sender, RoutedEventArgs e) { _dev = DevSwitch.IsChecked == true; Storage.SaveDev(_dev); }
        void Copy_Click(object sender, RoutedEventArgs e) { try { Clipboard.SetText(_log.Length == 0 ? S.Get("logEmpty") : _log.ToString()); } catch (Exception) { } }
        void Clear_Click(object sender, RoutedEventArgs e) { _log.Clear(); LogText.Text = ""; }

        /// <summary>Показати файл журналу в провіднику (його можна надіслати).</summary>
        void LogFile_Click(object sender, RoutedEventArgs e)
        {
            try { Process.Start("explorer.exe", "/select,\"" + Storage.LogPath + "\""); } catch (Exception) { }
        }
    }

    /// <summary>Невелике вікно вибору дії для відкритого .bin (у кольорах теми).</summary>
    static class FileActionDialog
    {
        /// <returns>1 — встановити, 2 — відкрити в редакторі, 0 — скасувати.</returns>
        public static int Ask(Window owner, string fileName)
        {
            int result = 0;
            var w = new Window
            {
                Owner = owner, Title = "BandFace", SizeToContent = SizeToContent.WidthAndHeight, ResizeMode = ResizeMode.NoResize,
                WindowStartupLocation = WindowStartupLocation.CenterOwner, ShowInTaskbar = false,
                Background = (Brush)owner.FindResource("Bg"), FontFamily = new FontFamily("Segoe UI"),
            };
            var sp = new StackPanel { Margin = new Thickness(24, 20, 24, 20), MinWidth = 380 };
            sp.Children.Add(new TextBlock { Text = fileName, FontSize = 16, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 460 });
            sp.Children.Add(new TextBlock { Text = S.Get("fileAsk"), FontSize = 13, Margin = new Thickness(0, 6, 0, 18), Foreground = (Brush)owner.FindResource("Sub") });
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            Button B(string text, string style, int r)
            {
                var b = new Button { Content = text, Style = (Style)owner.FindResource(style), Height = 34, Padding = new Thickness(16, 0, 16, 0), Margin = new Thickness(0, 0, 10, 0) };
                b.Click += (s, e) => { result = r; w.Close(); };
                row.Children.Add(b);
                return b;
            }
            B(S.Get("installOnDevice"), "PrimaryBtn", 1).IsDefault = true;
            B(S.Get("openInEditor"), "Btn", 2);
            B(S.Get("cloudCancel"), "Btn", 0).IsCancel = true;
            sp.Children.Add(row);
            w.Content = sp;
            w.SourceInitialized += (s, e) => Theme.Apply(w);
            w.ShowDialog();
            return result;
        }
    }
}
