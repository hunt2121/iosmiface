// SPDX-License-Identifier: MIT
// Перемикач «Старий / Новий дизайн» (унизу бічного меню). Новий: превʼю 144×354 на головній і в списку редактора,
// під кнопками — поле перетягування файла (у ньому ж прогрес і повідомлення). Старий — як було раніше.

using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace BandFace
{
    static class AppDesign
    {
        public static bool New { get; private set; } = Storage.LoadText("design", "new") != "old";
        public static event Action Changed;

        /// <summary>Для скріншотів: без збереження</summary>
        public static void Try(bool isNew) { New = isNew; Changed?.Invoke(); }

        public static void Set(bool isNew)
        {
            if (New == isNew) return;
            New = isNew;
            Storage.SaveText("design", isNew ? "new" : "old");
            Changed?.Invoke();
        }
    }

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

        void DesignOld_Click(object sender, RoutedEventArgs e) => AppDesign.Set(false);
        void DesignNew_Click(object sender, RoutedEventArgs e) => AppDesign.Set(true);

        void ApplyDesign()
        {
            bool n = AppDesign.New;
            DesignOld.IsChecked = !n; DesignNew.IsChecked = n;
            DesignLabel.Text = S.Get("design");
            DesignOld.Content = S.Get("designOld");
            DesignNew.Content = S.Get("designNew");
            foreach (var t in new[] { DesignOld, DesignNew }) { t.Background = Brushes.Transparent; t.BorderBrush = Brushes.Transparent; }

            // капсула: новий — 144×354, старий — 96×236 (обведення 3 px)
            double w = n ? 144 : 96, h = n ? 354 : 236;
            Capsule.Width = w + 6; Capsule.Height = h + 6;
            Capsule.CornerRadius = new CornerRadius((w + 6) / 2);
            Capsule.VerticalAlignment = n ? VerticalAlignment.Top : VerticalAlignment.Center;
            CapsuleInner.Width = w; CapsuleInner.Height = h;
            CapsuleInner.Clip = new RectangleGeometry(new Rect(0, 0, w, h), w / 2, w / 2);

            // колонка праворуч: новий — на висоту капсули, поле внизу заповнює решту; старий — по центру, рядок прогресу під кнопками
            // новий: однакові відступи зверху й знизу — назва не впирається у верх капсули, поле — у низ
            InfoColumn.Margin = n ? new Thickness(24, 28, 0, 28) : new Thickness(18, 0, 0, 0);
            InfoColumn.VerticalAlignment = n ? VerticalAlignment.Stretch : VerticalAlignment.Center;
            ZoneRow.Height = n ? new GridLength(1, GridUnitType.Star) : GridLength.Auto;
            ButtonsRow.Margin = new Thickness(0, n ? 16 : 18, 0, 0);
            Zone.Margin = new Thickness(0, n ? 16 : 20, 0, 0);
            Zone.MinHeight = n ? 150 : 34;
            Zone.AllowDrop = n;
            foreach (var b in new[] { ProgressPanel, MessagePanel })
            {
                if (n) b.SetResourceReference(Border.BackgroundProperty, "Bg"); else b.Background = Brushes.Transparent;
                b.BorderThickness = new Thickness(n ? 1 : 0);
                b.CornerRadius = new CornerRadius(n ? 10 : 0);
            }
            ProgressInner.Margin = n ? new Thickness(48, 0, 48, 0) : new Thickness(0);
            ProgressInner.VerticalAlignment = n ? VerticalAlignment.Center : VerticalAlignment.Top;
            StatusText.FontSize = n ? 14 : 12;
            StatusText.TextAlignment = n ? TextAlignment.Center : TextAlignment.Left;
            StatusText.VerticalAlignment = n ? VerticalAlignment.Center : VerticalAlignment.Top;
            StatusText.Margin = n ? new Thickness(32, 0, 32, 0) : new Thickness(0);
            MessagePanel.Cursor = n ? Cursors.Hand : null;

            RefreshButtons();
            UpdateZone();
            if (_face != null) RefreshFace();   // превʼю — під новий розмір капсули
        }
    }
}
