// SPDX-License-Identifier: MIT
// Картка встановлення на головній: превʼю 144×354, під кнопками — поле перетягування файла (у ньому ж прогрес і повідомлення).
// Мінівіконце встановлення, коли встановлюють з головної, а відкрита інша вкладка.

using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace BandFace
{
    public partial class MainWindow
    {
        // MARK: Мінівіконце встановлення поза вкладкою «Циферблати»

        Creator.InstallPopup _navPopup;
        Creator.InstallUpdate _homeInstall;

        /// <summary>u — новий стан встановлення з головної (null — перейшли на іншу вкладку)</summary>
        void NavInstall(Creator.InstallUpdate u)
        {
            bool fresh = u != null;
            if (fresh) _homeInstall = u;
            var cur = _homeInstall;
            if (cur == null) return;
            bool onFaces = NavFaces.IsChecked == true && PageFaces.Visibility == Visibility.Visible;
            bool running = cur.State == Creator.InstallUpdate.Kind.Connecting || cur.State == Creator.InstallUpdate.Kind.Uploading;
            if (onFaces || (!fresh && !running))
            {
                _navPopup?.Close();
                if (!running) _homeInstall = null;
                return;
            }
            if (_navPopup == null)
                _navPopup = new Creator.InstallPopup(NavFaces, alignLeft: true)
                {
                    Cancel = CancelInstall,
                    Retry = async () => { NavFaces.IsChecked = true; await InstallAsync(); },
                };
            // перехід на іншу вкладку — віконце відкривається; далі проміжні оновлення не відкривають його, якщо закрили
            _navPopup.Show(cur, !fresh || _navPopup.IsOpen || cur.State == Creator.InstallUpdate.Kind.Done || cur.State == Creator.InstallUpdate.Kind.Failed);
            if (!running) _homeInstall = null;
        }

        /// <summary>Розміри картки встановлення: капсула 144×354; колонка праворуч на висоту капсули, поле внизу заповнює решту</summary>
        void ApplyLayout()
        {
            const double w = 144, h = 354;
            Capsule.Width = w + 6; Capsule.Height = h + 6;
            Capsule.CornerRadius = new CornerRadius((w + 6) / 2);
            Capsule.VerticalAlignment = VerticalAlignment.Top;
            CapsuleInner.Width = w; CapsuleInner.Height = h;
            CapsuleInner.Clip = new RectangleGeometry(new Rect(0, 0, w, h), w / 2, w / 2);
            // однакові відступи зверху й знизу — назва не впирається у верх капсули, поле — у низ
            InfoColumn.Margin = new Thickness(24, 28, 0, 28);
            InfoColumn.VerticalAlignment = VerticalAlignment.Stretch;
            ZoneRow.Height = new GridLength(1, GridUnitType.Star);
            ButtonsRow.Margin = new Thickness(0, 16, 0, 0);
            Zone.Margin = new Thickness(0, 16, 0, 0);
            Zone.MinHeight = 150;
            Zone.AllowDrop = true;
            foreach (var b in new[] { ProgressPanel, MessagePanel })
            {
                b.SetResourceReference(Border.BackgroundProperty, "Bg");
                b.BorderThickness = new Thickness(1);
                b.CornerRadius = new CornerRadius(10);
            }
            ProgressInner.Margin = new Thickness(48, 0, 48, 0);
            ProgressInner.VerticalAlignment = VerticalAlignment.Center;
            StatusText.FontSize = 14;
            StatusText.TextAlignment = TextAlignment.Center;
            StatusText.VerticalAlignment = VerticalAlignment.Center;
            StatusText.Margin = new Thickness(32, 0, 32, 0);
            MessagePanel.Cursor = Cursors.Hand;

            RefreshButtons();
            UpdateZone();
            if (_face != null) RefreshFace();   // превʼю — під новий розмір капсули
        }
    }
}
