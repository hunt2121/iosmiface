using System;
using System.Globalization;
using System.IO;
using System.Threading;
using System.Windows;
using BandFace.Faces;

namespace BandFace
{
    public partial class App : Application
    {
        static void Crash(Exception e)
        {
            try { File.WriteAllText(Path.Combine(Path.GetTempPath(), "bandface-crash.txt"), e?.ToString() ?? "?"); } catch (Exception) { }
        }

        protected override void OnStartup(StartupEventArgs e)
        {
            DispatcherUnhandledException += (s, a) =>
            {
                Crash(a.Exception);
                a.Handled = true;
                // помилка в редакторі не має закривати весь застосунок
                MessageBox.Show(a.Exception.Message, "BandFace", MessageBoxButton.OK, MessageBoxImage.Error);
            };
            AppDomain.CurrentDomain.UnhandledException += (s, a) => Crash(a.ExceptionObject as Exception);
            // мова, вибрана в Налаштуваннях (порожньо — мова Windows); до першого звернення до текстів
            var lang = Storage.LoadText("lang");
            if (lang == "uk" || lang == "en" || lang == "ru")
            {
                var c = new CultureInfo(lang);
                CultureInfo.DefaultThreadCurrentUICulture = c;
                Thread.CurrentThread.CurrentUICulture = c;
            }
            Theme.Mode = Storage.LoadText("theme", "system");
            Theme.Apply(null); // ресурси кольорів мають існувати до створення вікна
            // JPEG, BMP, GIF тощо в проєктах редактора — засобами Windows
            ImageDecoder.Fallback = BandFace.Creator.Imaging.Decode;
            base.OnStartup(e);
        }
    }
}
