using System.Windows;

namespace BandFace
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            Theme.Apply(null); // ресурси кольорів мають існувати до створення вікна
            base.OnStartup(e);
        }
    }
}
