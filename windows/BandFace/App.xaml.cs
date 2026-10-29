using System;
using System.IO;
using System.Windows;

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
            DispatcherUnhandledException += (s, a) => { Crash(a.Exception); a.Handled = true; Shutdown(1); };
            AppDomain.CurrentDomain.UnhandledException += (s, a) => Crash(a.ExceptionObject as Exception);
            Theme.Apply(null); // ресурси кольорів мають існувати до створення вікна
            base.OnStartup(e);
        }
    }
}
