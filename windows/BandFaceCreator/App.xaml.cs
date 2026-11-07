// SPDX-License-Identifier: MIT
using System;
using System.IO;
using System.Windows;
using BandFace.Faces;

namespace BandFace.Creator
{
    public partial class App : Application
    {
        static void Crash(Exception e)
        {
            try { File.WriteAllText(Path.Combine(Path.GetTempPath(), "bandface-creator-crash.txt"), e?.ToString() ?? "?"); } catch (Exception) { }
        }

        protected override void OnStartup(StartupEventArgs e)
        {
            DispatcherUnhandledException += (s, a) =>
            {
                Crash(a.Exception);
                a.Handled = true;
                MessageBox.Show(S.Get("crash", a.Exception.Message), "BandFace Creator", MessageBoxButton.OK, MessageBoxImage.Error);
            };
            AppDomain.CurrentDomain.UnhandledException += (s, a) => Crash(a.ExceptionObject as Exception);
            Theme.Apply(null); // ресурси кольорів мають існувати до створення вікна
            // JPEG, BMP, GIF тощо в проєктах — засобами Windows
            ImageDecoder.Fallback = Imaging.Decode;
            base.OnStartup(e);
            var w = new MainWindow(e.Args);
            MainWindow = w;
            w.Show();
        }
    }
}
