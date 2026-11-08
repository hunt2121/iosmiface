// SPDX-License-Identifier: MIT
// Значки застосунків для сповіщень на пристрої.
// Значок береться з самого сповіщення Windows (логотип програми) і зберігається в %LocalAppData%\BandFace\icons.
// Обмін з пристроєм: він питає «є значок для пакета?» (7/16) → відповідаємо 7/15 з назвою пакета →
// він просить розмір і формат пікселів (7/15) → завантажуємо картинку як файл типу 50.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BandFace.Protocol;

namespace BandFace
{
    static class NotifyIcons
    {
        public const string OwnPackage = "com.bandface.windows";
        static readonly Dictionary<string, BitmapSource> cache = new Dictionary<string, BitmapSource>();
        static readonly object gate = new object();

        static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BandFace", "icons");
        /// <summary>Створити теку значків і покласти туди значок BandFace, щоб було видно всі файли</summary>
        public static string EnsureFolder()
        {
            Directory.CreateDirectory(Folder);
            var own = FileFor(OwnPackage);
            if (!File.Exists(own))
                try
                {
                    var b = Get(OwnPackage);
                    if (b != null)
                    {
                        var enc = new PngBitmapEncoder();
                        enc.Frames.Add(BitmapFrame.Create(b));
                        using (var f = File.Create(own)) enc.Save(f);
                    }
                }
                catch (Exception) { }
            return Folder;
        }

        static string FileFor(string package) => Path.Combine(Folder, package + ".png");

        /// <summary>Запам'ятати значок пакета (PNG-байти логотипа з Windows)</summary>
        public static void Remember(string package, byte[] png)
        {
            if (string.IsNullOrEmpty(package) || png == null || png.Length == 0) return;
            try
            {
                var bmp = Decode(png);
                if (bmp == null) return;
                lock (gate) cache[package] = bmp;
                Directory.CreateDirectory(Folder);
                File.WriteAllBytes(FileFor(package), png);
            }
            catch (Exception) { }
        }

        static BitmapSource Decode(byte[] png)
        {
            using (var ms = new MemoryStream(png))
            {
                var d = BitmapDecoder.Create(ms, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
                var f = d.Frames[0];
                f.Freeze();
                return f;
            }
        }

        public static BitmapSource Get(string package)
        {
            if (string.IsNullOrEmpty(package)) return null;
            lock (gate) if (cache.TryGetValue(package, out var c)) return c;
            BitmapSource b = null;
            try
            {
                if (File.Exists(FileFor(package))) b = Decode(File.ReadAllBytes(FileFor(package)));
                else if (package == OwnPackage) b = OwnIcon();
            }
            catch (Exception) { }
            if (b != null) lock (gate) cache[package] = b;
            return b;
        }

        public static bool Has(string package) => Get(package) != null;

        /// <summary>Значок самого BandFace (з exe) — для вітання й тестового сповіщення</summary>
        static BitmapSource OwnIcon()
        {
            BitmapSource r = null;
            Application.Current.Dispatcher.Invoke(() =>
            {
                // найбільший кадр з app.ico
                var d = BitmapDecoder.Create(new Uri("pack://application:,,,/Assets/app.ico"), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                var f = d.Frames.OrderByDescending(x => x.PixelWidth).First();
                f.Freeze();
                r = f;
            });
            return r;
        }

        /// <summary>Картинка size×size у форматі, який попросив пристрій; null — формат невідомий</summary>
        public static byte[] Encode(string package, int pixelFormat, int size)
        {
            var src = Get(package);
            if (src == null || size <= 0 || size > 512) return null;
            byte[] bgra = null;
            Application.Current.Dispatcher.Invoke(() => bgra = Bgra(src, size));
            if (bgra == null) return null;
            int n = size * size;
            switch (pixelFormat)
            {
                case 0: // RGB565, молодший байт першим (прозоре — на чорному)
                case 1: // RGB565, старший байт першим
                {
                    var o = new byte[n * 2];
                    for (int i = 0; i < n; i++)
                    {
                        int a = bgra[i * 4 + 3];
                        int b = bgra[i * 4] * a / 255, g = bgra[i * 4 + 1] * a / 255, r = bgra[i * 4 + 2] * a / 255;
                        int v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
                        if (pixelFormat == 0) { o[i * 2] = (byte)v; o[i * 2 + 1] = (byte)(v >> 8); }
                        else { o[i * 2] = (byte)(v >> 8); o[i * 2 + 1] = (byte)v; }
                    }
                    return o;
                }
                case 2: // XRGB8888 / ARGB8888, молодший байт першим = B G R A
                case 3:
                    return bgra;
                case 7: // ARGB8565: RGB565 (молодший байт першим) + байт прозорості
                case 8: // ABGR8565: те саме, червоний і синій поміняні
                {
                    var o = new byte[n * 3];
                    for (int i = 0; i < n; i++)
                    {
                        int b = bgra[i * 4], g = bgra[i * 4 + 1], r = bgra[i * 4 + 2], a = bgra[i * 4 + 3];
                        int hi = pixelFormat == 7 ? r : b, lo = pixelFormat == 7 ? b : r;
                        int v = ((hi >> 3) << 11) | ((g >> 2) << 5) | (lo >> 3);
                        o[i * 3] = (byte)v; o[i * 3 + 1] = (byte)(v >> 8); o[i * 3 + 2] = (byte)a;
                    }
                    return o;
                }
            }
            return null;
        }

        /// <summary>Вписати значок у квадрат size×size; пікселі B G R A без попереднього множення на прозорість</summary>
        static byte[] Bgra(BitmapSource src, int size)
        {
            var dv = new DrawingVisual();
            RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
            using (var dc = dv.RenderOpen())
            {
                double k = Math.Min(size / (double)src.PixelWidth, size / (double)src.PixelHeight);
                double w = src.PixelWidth * k, h = src.PixelHeight * k;
                dc.DrawImage(src, new Rect((size - w) / 2, (size - h) / 2, w, h));
            }
            var rt = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
            rt.Render(dv);
            var conv = new FormatConvertedBitmap(rt, PixelFormats.Bgra32, null, 0);
            var px = new byte[size * size * 4];
            conv.CopyPixels(px, size * 4, 0);
            return px;
        }
    }

    /// <summary>Відповідає на запити значків протягом одного сеансу зв'язку</summary>
    sealed class IconResponder
    {
        readonly BandSession session;
        readonly Action<string> log;
        string package;
        int busy;
        DateTime lastActivity = DateTime.MinValue;

        public IconResponder(BandSession s, Action<string> log)
        {
            session = s; this.log = log;
            s.Incoming += OnCommand;
        }

        void OnCommand(Command c)
        {
            if (c.Type != Command.Notify) return;
            if (c.Subtype == 16)
            {
                var pkg = c.Root.MessageAt(9, 16)?.String(1);
                lastActivity = DateTime.UtcNow;
                _ = Task.Run(async () =>
                {
                    if (string.IsNullOrEmpty(pkg)) return;
                    if (!NotifyIcons.Has(pkg)) { log("icon: none for " + pkg); return; }
                    package = pkg;
                    System.Threading.Interlocked.Increment(ref busy);
                    try { await session.SendAsync(Command.NotificationIconReply(pkg)); log("icon: offered " + pkg); }
                    catch (Exception ex) { log("icon: " + ex.Message); }
                    finally { System.Threading.Interlocked.Decrement(ref busy); lastActivity = DateTime.UtcNow; }
                });
            }
            else if (c.Subtype == 15)
            {
                var req = c.Root.MessageAt(9, 15);
                if (req == null) return;
                int format = (int)(req.Varint(2) ?? -1), size = (int)(req.Varint(3) ?? 0);
                long status = req.Varint(1) ?? 0;
                var pkg = package;
                lastActivity = DateTime.UtcNow;
                System.Threading.Interlocked.Increment(ref busy);
                _ = Task.Run(async () =>
                {
                    try
                    {
                        log("icon: request " + pkg + " format " + format + " size " + size + " status " + status);
                        var data = NotifyIcons.Encode(pkg, format, size);
                        if (data == null) { log("icon: can't make format " + format); return; }
                        var md5 = BandCrypto.Md5(data);
                        var resp = new UploadResponse(await session.CommandAsync(Command.UploadRequest(md5, data.Length, Command.UploadTypeNotificationIcon)));
                        if (resp.Status != 0 || resp.ChunkSize <= 4) { log("icon: upload refused " + resp.Status); return; }
                        var parts = FileTransfer.Parts(data, md5, resp.ResumePosition, resp.ChunkSize, (byte)Command.UploadTypeNotificationIcon);
                        // у заголовку потоку той самий тип 50: з типом циферблата (16) пристрій рвав зв'язок посеред передачі
                        await session.SendFilePartsAsync(parts, null);
                        log("icon: sent " + pkg + " (" + data.Length + " bytes)");
                    }
                    catch (Exception ex) { log("icon: " + ex.Message); }
                    finally { System.Threading.Interlocked.Decrement(ref busy); lastActivity = DateTime.UtcNow; }
                });
            }
        }

        /// <summary>Почекати, поки обмін значками затихне: мінімум minMs, максимум maxMs</summary>
        public async Task SettleAsync(int minMs, int maxMs)
        {
            var start = DateTime.UtcNow;
            await Task.Delay(minMs);
            while ((DateTime.UtcNow - start).TotalMilliseconds < maxMs)
            {
                bool quiet = System.Threading.Volatile.Read(ref busy) == 0 && (DateTime.UtcNow - lastActivity).TotalMilliseconds > 1500;
                if (quiet) break;
                await Task.Delay(200);
            }
        }

        public void Detach() => session.Incoming -= OnCommand;
    }
}
