using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BandFace.Protocol;
using Microsoft.Win32;

namespace BandFace
{
    public partial class MainWindow : Window
    {
        readonly BleTransport _ble = new BleTransport();
        readonly BridgeTransport _bridge = new BridgeTransport();
        bool _useBridge, _bridgeOpening, _bridgeConnecting;
        /// <summary>Поточний канал: Bluetooth Windows або (експериментально) ESP32-міст.</summary>
        ILink _link => _useBridge ? (ILink)_bridge : _ble;
        readonly StringBuilder _log = new StringBuilder();
        readonly HashSet<ulong> _seen = new HashSet<ulong>();
        BandSession _session;
        FaceFile _face;
        string _faceFile = "";
        bool _busy, _dev;

        public MainWindow()
        {
            InitializeComponent();
            _dev = Storage.LoadDev();
            DevSwitch.IsChecked = _dev;
            _useBridge = Storage.LoadFlag("bridge.flag");
            BridgeSwitch.IsChecked = _useBridge;
            KeyBox.Text = Storage.LoadKey();
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            string ver = v.Major + "." + v.Minor + "." + v.Build;
            VersionText.Text = "v" + ver;
            VersionCard.Text = "BandFace " + ver;
            ApplyTexts();
            RefreshBand();
            RefreshFace();
            _bridge.StateChanged += () => Dispatcher.BeginInvoke(new Action(RefreshBridge));
            AddLog("BandFace " + ver + " started" + (_useBridge ? " (ESP32 bridge mode)" : ""));
            if (_useBridge) ContentRendered += async (s, e) => await OpenBridgeAsync();
            foreach (var link in new ILink[] { _ble, _bridge })
            {
                link.Info += m => Dispatcher.BeginInvoke(new Action(() => AddLog(m)));
                link.Data += b => _session?.Receive(b);
                link.Disconnected += () => Dispatcher.BeginInvoke(new Action(() => { _session?.ConnectionLost(); AddLog("disconnected"); RefreshBand(); }));
            }
            foreach (var a in Environment.GetCommandLineArgs())
            {
                if (a == "--page=key") NavKey.IsChecked = true;
                else if (a == "--page=log") NavLog.IsChecked = true;
            }
            string shot = null;
            foreach (var a in Environment.GetCommandLineArgs()) if (a.StartsWith("--shot=")) shot = a.Substring(7);
            if (shot != null)
                ContentRendered += async (s, e) =>
                {
                    await Task.Delay(1500);
                    try { SaveShot(shot); } catch (Exception ex) { File.WriteAllText(shot + ".txt", ex.ToString()); }
                    Application.Current.Shutdown();
                };
            SourceInitialized += (s, e) => Theme.Apply(this);
            Microsoft.Win32.SystemEvents.UserPreferenceChanged += (s, e) => Dispatcher.BeginInvoke(new Action(() => Theme.Apply(this)));
            Closed += (s, e) => { _ble.StopScan(); _ble.Disconnect(); _bridge.Close(); };
        }

        /// <summary>Параметри відкриття сесії, як у Mi Fitness (з назвою телефона).</summary>
        SessionConfig NewConfig()
        {
            Func<int, byte[], KeyValuePair<int, byte[]>> kv = (k, v) => new KeyValuePair<int, byte[]>(k, v);
            return new SessionConfig
            {
                Log = m => Dispatcher.BeginInvoke(new Action(() => AddLog(m))),
                OpenParameters = new List<KeyValuePair<int, byte[]>>
                {
                    kv(1, new byte[] { 0x01, 0x00, 0x00 }), kv(7, new byte[] { 0x1b, 0x02, 0x00 }), kv(2, new byte[] { 0xff, 0xff }),
                    kv(5, new byte[] { 0x01 }), kv(6, Encoding.ASCII.GetBytes("iPhone")), kv(3, new byte[] { 0x10, 0x00 }), kv(4, new byte[] { 0x98, 0x3a }),
                },
            };
        }

        /// <summary>Одразу після зв'язування проходимо автентифікацію (на новому браслеті це дає запит підтвердження).</summary>
        async Task ActivateAsync()
        {
            var key = Bytes.ParseHex(KeyBox.Text);
            if (key == null || key.Length != 16 || !_link.IsConnected) return;
            // Через ESP32 — як в iOS-версії: без окремого входу одразу після підключення;
            // вхід відбувається вже під час встановлення, в одній сесії з передачею циферблата
            if (_useBridge) { AddLog("connect: activation skipped (iOS-style, auth at install)"); return; }
            SetStatus(S.Get("phPair"), false);
            var session = new BandSession(_link, NewConfig());
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

        static string Region()
        {
            try { var r = System.Globalization.RegionInfo.CurrentRegion.TwoLetterISORegionName; return r.Length == 2 ? r : "UA"; }
            catch (Exception) { return "UA"; }
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
            NavKeyText.Text = S.Get("key"); TitleKey.Text = S.Get("key");
            NavLogText.Text = S.Get("log"); TitleLog.Text = S.Get("log");
            BandLabel.Text = S.Get("band").ToUpperInvariant();
            InstallLabel.Text = S.Get("installCard").ToUpperInvariant();
            KeyLabel.Text = S.Get("keyTitle").ToUpperInvariant();
            ActivityLabel.Text = S.Get("activity").ToUpperInvariant();
            VersionLabel.Text = S.Get("version").ToUpperInvariant();
            DisconnectBtn.Content = S.Get("disconnect");
            BandNone.Text = S.Get("notConnected");
            PasteBtn.Content = S.Get("paste");
            FromFileBtn.Content = S.Get("fromFile");
            KeyNote.Text = S.Get("keyNote");
            CloudLabel.Text = S.Get("cloudTitle").ToUpperInvariant();
            CloudBtn.Content = S.Get("cloudBtn");
            CloudCancelBtn.Content = S.Get("cloudCancel");
            CloudNote.Text = S.Get("cloudNote");
            DevLabel.Text = S.Get("dev");
            ExpLabel.Text = S.Get("experimental").ToUpperInvariant();
            BridgeCardLabel.Text = S.Get("bridgeCard").ToUpperInvariant() + " · " + S.Get("experimental").ToUpperInvariant();
            BridgeFindBtn.Content = S.Get("bridgeFind");
            PairConnectBtn.Content = S.Get("pairConnect");
            UnpairBtn.Content = S.Get("unpair");
            LogFileBtn.Content = S.Get("logFile");
            BridgeLabel.Text = S.Get("bridge");
            BridgeNote.Text = S.Get("bridgeNote");
            CopyBtn.Content = S.Get("copy");
            ClearBtn.Content = S.Get("clear");
            InstallBtn.Content = S.Get("install");
            Title = "BandFace";
        }

        void Nav_Checked(object sender, RoutedEventArgs e)
        {
            if (PageFaces == null) return;
            PageFaces.Visibility = NavFaces.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            PageKey.Visibility = NavKey.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            PageLog.Visibility = NavLog.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        }

        // ---------- Браслет ----------
        void RefreshBand()
        {
            bool c = _link.IsConnected;
            BandConnected.Visibility = c ? Visibility.Visible : Visibility.Collapsed;
            BandIdle.Visibility = c ? Visibility.Collapsed : Visibility.Visible;
            BandName.Text = _link.ConnectedName ?? "";
            BandStatus.Text = S.Get(_useBridge ? "connectedBridge" : "connected");
            ScanBtn.Content = S.Get(_useBridge ? "scanBridge" : "scan");
            InstallBtn.IsEnabled = !_busy && _face != null;
            RefreshBridge();
        }

        // ---------- ESP32-міст (експериментально) ----------
        void RefreshBridge()
        {
            BridgeCard.Visibility = _useBridge ? Visibility.Visible : Visibility.Collapsed;
            if (!_useBridge) return;
            bool open = _bridge.IsOpen, paired = open && _bridge.PairedAddr != null, conn = _bridge.IsConnected;
            BridgePort.Text = _bridgeOpening ? S.Get("bridgeLooking") : open ? S.Get("bridgeOn", _bridge.PortName) : S.Get("bridgeNoBoard");
            BridgeDot.Fill = (Brush)FindResource(open ? "Ok" : "Sub");
            if (!open) { PairText.Text = S.Get("pairUnknown"); PairAddr.Text = ""; }
            else if (paired)
            {
                PairText.Text = S.Get(conn ? "pairedConnected" : "pairedWith", _bridge.PairedName);
                PairAddr.Text = _bridge.PairedAddr.ToUpperInvariant();
            }
            else { PairText.Text = S.Get("notPaired"); PairAddr.Text = ""; }
            PairDot.Fill = (Brush)FindResource(paired ? "Ok" : "Sub");
            PairText.Foreground = (Brush)FindResource(paired ? "Ok" : "Text");
            BridgeFindBtn.Visibility = open ? Visibility.Collapsed : Visibility.Visible;
            BridgeFindBtn.IsEnabled = !_bridgeOpening;
            PairConnectBtn.Visibility = paired && !conn ? Visibility.Visible : Visibility.Collapsed;
            PairConnectBtn.IsEnabled = !_busy && !_bridgeConnecting;
            UnpairBtn.Visibility = paired ? Visibility.Visible : Visibility.Collapsed;
            UnpairBtn.IsEnabled = !_busy && !_bridgeConnecting;
        }

        async Task<bool> OpenBridgeAsync()
        {
            if (_bridge.IsOpen) return true;
            if (_bridgeOpening) return false;
            _bridgeOpening = true;
            RefreshBridge();
            try
            {
                await _bridge.OpenAsync();
                AddLog("connect: ESP32 bridge on " + _bridge.PortName);
                return true;
            }
            catch (Exception) { AddLog("connect: ESP32 bridge not found"); return false; }
            finally { _bridgeOpening = false; RefreshBridge(); }
        }

        async void BridgeFind_Click(object sender, RoutedEventArgs e)
        {
            if (!await OpenBridgeAsync()) SetStatus(S.Get("noBridge"), true);
        }

        async void PairConnect_Click(object sender, RoutedEventArgs e)
        {
            if (_bridgeConnecting || _bridge.PairedAddr == null) return;
            _bridgeConnecting = true;
            _bridge.StopScan();
            DeviceList.Children.Clear();
            SetStatus(S.Get("phConnect"), false);
            RefreshBridge();
            try
            {
                await _bridge.ConnectPairedAsync();
                AddLog("connected " + _bridge.PairedName + " (paired)");
                SetStatus("", false);
                RefreshBand();
                await ActivateAsync();
            }
            catch (Exception ex)
            {
                AddLog("connect: " + ex.Message);
                SetStatus(ex.Message.Contains("connect") ? S.Get("pairHint") : Describe(ex), true);
            }
            finally { _bridgeConnecting = false; RefreshBand(); }
        }

        void Unpair_Click(object sender, RoutedEventArgs e)
        {
            try { _bridge.Unpair(); AddLog("connect: ESP32 pairing forgotten"); } catch (Exception ex) { AddLog("connect: unpair " + ex.Message); }
            SetStatus("", false);
            RefreshBand();
        }

        async void Scan_Click(object sender, RoutedEventArgs e)
        {
            DeviceList.Children.Clear();
            _seen.Clear();
            ScanBtn.Content = S.Get("scanning");
            var link = _link;
            try
            {
                if (link == _bridge && !_bridge.IsOpen)
                {
                    SetStatus(S.Get("bridgeLooking"), false);
                    if (!await OpenBridgeAsync()) throw new InvalidOperationException("bridge");
                    SetStatus("", false);
                }
                if (link != _link) return;   // перемикач змінили, поки шукали плату
                link.StartScan(f => Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (!_seen.Add(f.Address)) return;
                    var b = new Button { Content = f.Name, Style = (Style)FindResource("Btn"), Height = 34, HorizontalContentAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 6), Padding = new Thickness(14, 0, 14, 0) };
                    b.Click += async (s, a) => await ConnectTo(f);
                    DeviceList.Children.Add(b);
                })));
            }
            catch (Exception) { SetStatus(S.Get(link == _bridge ? "noBridge" : "noBle"), true); ScanBtn.Content = S.Get(_useBridge ? "scanBridge" : "scan"); }
        }

        async Task ConnectTo(FoundBand f)
        {
            _link.StopScan();
            DeviceList.Children.Clear();
            ScanBtn.Content = S.Get("phConnect");
            SetStatus(S.Get("phPair"), false);
            try { await _link.ConnectAsync(f); AddLog("connected " + f.Name); SetStatus("", false); RefreshBand(); await ActivateAsync(); }
            catch (Exception ex) { SetStatus(_useBridge && ex.Message == "ESP32: connect" ? S.Get("pairHint") : Describe(ex), true); AddLog("connect: " + ex.Message); }
            RefreshBand();
        }

        void Disconnect_Click(object sender, RoutedEventArgs e) { _link.Disconnect(); RefreshBand(); }

        // ---------- Циферблат ----------
        void Pick_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog { Filter = "Watch face (*.bin;*.face)|*.bin;*.face|*.*|*.*" };
            if (dlg.ShowDialog(this) != true) return;
            try
            {
                _face = new FaceFile(File.ReadAllBytes(dlg.FileName));
                _faceFile = Path.GetFileName(dlg.FileName);
                SetStatus("", false);
            }
            catch (Exception) { _face = null; SetStatus(S.Get("errFace"), true); }
            RefreshFace();
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
                FaceInfo.Text = "ID " + _face.Id + " · " + (_face.Size + 512) / 1024 + " " + (S.Get("faces") == "Циферблати" ? "КБ" : "KB");
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

        async void Install_Click(object sender, RoutedEventArgs e)
        {
            if (_busy || _face == null) return;
            var key = Bytes.ParseHex(KeyBox.Text);
            if (key == null || key.Length != 16) { SetStatus(S.Get("keyInvalid"), true); return; }
            if (!_link.IsConnected) { SetStatus(S.Get("errConnect"), true); return; }
            _busy = true; InstallBtn.IsEnabled = false; PickBtn.IsEnabled = false;
            SetStatus("", false);
            ProgressPanel.Visibility = Visibility.Visible;
            Bar.Value = 0; ProgressPercent.Text = ""; ProgressText.Text = S.Get("phConnect");
            var cfg = NewConfig();
            _session = new BandSession(_link, cfg);
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

        void KeyBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            var b = Bytes.ParseHex(KeyBox.Text);
            if (b != null && b.Length == 16) { Storage.SaveKey(Bytes.ToHexLower(b)); KeyMessage.Text = S.Get("keySaved"); KeyMessage.Foreground = (Brush)FindResource("Ok"); }
            else if (KeyBox.Text.Length > 0) { KeyMessage.Text = S.Get("keyInvalid"); KeyMessage.Foreground = (Brush)FindResource("Err"); }
            else KeyMessage.Text = "";
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
            if (!_dev && !m.StartsWith("connected") && !m.StartsWith("install") && !m.StartsWith("connect") && !m.StartsWith("disc") && !m.StartsWith("bridge") && !m.StartsWith("BandFace")) return;
            string line = DateTime.Now.ToString("HH:mm:ss") + " " + m;
            _log.AppendLine(line);
            Storage.AppendLog(DateTime.Now.ToString("yyyy-MM-dd ") + line);
            if (_log.Length > 60000) _log.Remove(0, 20000);
            LogText.Text = _log.ToString();
        }

        void Dev_Click(object sender, RoutedEventArgs e) { _dev = DevSwitch.IsChecked == true; Storage.SaveDev(_dev); }

        /// <summary>Експериментально: ESP32-міст замість Bluetooth Windows.</summary>
        void Bridge_Click(object sender, RoutedEventArgs e)
        {
            bool on = BridgeSwitch.IsChecked == true;
            if (on == _useBridge) return;
            if (_busy) { BridgeSwitch.IsChecked = _useBridge; return; }
            _link.StopScan();
            _link.Disconnect();
            if (!on) _bridge.Close();
            _useBridge = on;
            Storage.SaveFlag("bridge.flag", on);
            DeviceList.Children.Clear();
            SetStatus("", false);
            RefreshBand();
            AddLog("connect: ESP32 bridge mode " + (on ? "on" : "off"));
            if (on) _ = OpenBridgeAsync();
        }
        void Copy_Click(object sender, RoutedEventArgs e) { try { Clipboard.SetText(_log.Length == 0 ? S.Get("logEmpty") : _log.ToString()); } catch (Exception) { } }
        void Clear_Click(object sender, RoutedEventArgs e) { _log.Clear(); LogText.Text = ""; }

        /// <summary>Показати файл журналу в провіднику (його можна надіслати).</summary>
        void LogFile_Click(object sender, RoutedEventArgs e)
        {
            try { System.Diagnostics.Process.Start("explorer.exe", "/select,\"" + Storage.LogPath + "\""); } catch (Exception) { }
        }
    }
}
