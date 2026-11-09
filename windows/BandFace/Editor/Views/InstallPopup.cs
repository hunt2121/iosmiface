// SPDX-License-Identifier: MIT
// Маленьке віконце під «Встановити на пристрій» у редакторі: прогрес встановлення.
// Однаковий розмір у всіх станах: назва (+ відсоток), смужка, нижній рядок з дією.

using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace BandFace.Creator
{
    /// <summary>Стан встановлення з редактора</summary>
    public sealed class InstallUpdate
    {
        public enum Kind { Connecting, Uploading, Done, Failed, Cancelled }
        public Kind State;
        /// <summary>Частка передачі 0…1</summary>
        public double Fraction;
        /// <summary>Розмір файла, байти</summary>
        public long Bytes;
        /// <summary>Скільки секунд минуло від початку</summary>
        public double Seconds;
        /// <summary>Текст помилки (для Failed)</summary>
        public string Error;
        public string Name;
        /// <summary>Етап — той самий текст, що й на вкладці «Циферблати» та в iOS</summary>
        public string Text;
    }

    sealed class InstallPopup
    {
        const double W = 292, H = 84;
        readonly Popup popup;
        readonly FrameworkElement target;
        readonly TextBlock title, percent, info;
        readonly Border bar, fill, icon;
        readonly TextBlock iconText;
        readonly TextBlock action;
        readonly DispatcherTimer hide = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        readonly DispatcherTimer spin = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(30) };
        double spinPos;
        public Action Cancel, Retry;
        public InstallUpdate.Kind? Current;

        public InstallPopup(FrameworkElement target)
        {
            this.target = target;
            title = new TextBlock { FontSize = 14, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
            percent = new TextBlock { FontSize = 14, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
            iconText = new TextBlock { FontSize = 11, FontWeight = FontWeights.Bold, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            icon = new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(9), Margin = new Thickness(0, 0, 8, 0), Child = iconText, Visibility = Visibility.Collapsed };
            var head = new DockPanel { LastChildFill = true };
            DockPanel.SetDock(percent, Dock.Right);
            head.Children.Add(percent);
            head.Children.Add(icon);
            head.Children.Add(title);

            fill = new Border { CornerRadius = new CornerRadius(3), HorizontalAlignment = HorizontalAlignment.Left };
            bar = new Border { Height = 6, CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 10, 0, 8), Child = fill, ClipToBounds = true };
            bar.SetResourceReference(Border.BackgroundProperty, "Track");

            info = new TextBlock { FontSize = 12.5, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
            info.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            action = new TextBlock { FontSize = 13, FontWeight = FontWeights.SemiBold, Cursor = System.Windows.Input.Cursors.Hand, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) };
            action.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
            action.MouseLeftButtonUp += (s, e) =>
            {
                if (Current == InstallUpdate.Kind.Failed) Retry?.Invoke();
                else Cancel?.Invoke();
            };
            var row = new DockPanel { Height = 18 };
            DockPanel.SetDock(action, Dock.Right);
            row.Children.Add(action);
            row.Children.Add(info);

            var stack = new StackPanel();
            stack.Children.Add(head);
            stack.Children.Add(bar);
            stack.Children.Add(row);

            var card = new Border
            {
                Width = W, Height = H, CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1),
                Padding = new Thickness(16, 14, 16, 14), Child = stack,
                Effect = new DropShadowEffect { BlurRadius = 22, ShadowDepth = 6, Direction = 270, Opacity = 0.18 },
            };
            card.SetResourceReference(Border.BackgroundProperty, "Card");
            card.SetResourceReference(Border.BorderBrushProperty, "CardBorder");
            card.SetResourceReference(TextElement.ForegroundProperty, "Text");

            // стрілка до кнопки
            var arrow = new Path { Data = Geometry.Parse("M0,8 L8,0 L16,8"), StrokeThickness = 1, Margin = new Thickness(0, 0, 0, -1) };
            arrow.SetResourceReference(Shape.FillProperty, "Card");
            arrow.SetResourceReference(Shape.StrokeProperty, "CardBorder");
            var arrowHost = new Canvas { Height = 8 };
            arrowHost.Children.Add(arrow);
            var outer = new StackPanel { Margin = new Thickness(14, 0, 14, 18) };
            outer.Children.Add(arrowHost);
            outer.Children.Add(card);
            Panel.SetZIndex(arrowHost, 1);

            popup = new Popup
            {
                PlacementTarget = target, Placement = PlacementMode.Bottom, AllowsTransparency = true, StaysOpen = false,
                PopupAnimation = PopupAnimation.Fade, Child = outer,
            };
            popup.Opened += (s, e) =>
            {
                // правий край віконця — під правим краєм кнопки, стрілка — під серединою кнопки
                popup.HorizontalOffset = target.ActualWidth - W - 14;
                Canvas.SetLeft(arrow, W - target.ActualWidth / 2 - 8);
                popup.VerticalOffset = 2;
            };
            hide.Tick += (s, e) => { hide.Stop(); popup.IsOpen = false; };
            spin.Tick += (s, e) =>
            {
                // смужка «невідомої тривалості»: шматок, що біжить зліва направо
                spinPos = (spinPos + 0.012) % 1.3;
                double w = bar.ActualWidth > 0 ? bar.ActualWidth : W - 32;
                fill.Width = w * 0.3;
                fill.Margin = new Thickness(w * (spinPos - 0.3), 0, 0, 0);
            };
        }

        public bool IsOpen => popup.IsOpen;
        public void Open() { popup.IsOpen = true; }

        /// <summary>Показ стану; віконце відкривається, якщо закрите (крім проміжних оновлень, коли користувач його закрив)</summary>
        public void Show(InstallUpdate u, bool open)
        {
            bool first = Current != u.State;
            Current = u.State;
            hide.Stop();
            icon.Visibility = Visibility.Collapsed;
            percent.Text = "";
            fill.Margin = new Thickness(0);
            spin.Stop();
            double w = bar.ActualWidth > 0 ? bar.ActualWidth : W - 32;
            switch (u.State)
            {
                case InstallUpdate.Kind.Connecting:
                    title.Text = u.Text ?? "";
                    fill.SetResourceReference(Border.BackgroundProperty, "Accent");
                    info.Text = "";
                    action.Text = S.Get("instCancel");
                    spin.Start();
                    break;
                case InstallUpdate.Kind.Uploading:
                    title.Text = u.Text ?? "";
                    int pc = (int)Math.Floor(u.Fraction * 100);
                    percent.Text = pc + " %";
                    fill.SetResourceReference(Border.BackgroundProperty, "Accent");
                    fill.Width = Math.Max(6, w * u.Fraction);
                    long kb = Math.Max(1, (u.Bytes + 512) / 1024);
                    long sentKb = (long)Math.Round(kb * u.Fraction);
                    string left = "";
                    if (u.Fraction > 0.03 && u.Seconds > 1)
                    {
                        int rest = (int)Math.Ceiling(u.Seconds / u.Fraction * (1 - u.Fraction));
                        left = " · ~" + rest + " " + S.Get("instSec");
                    }
                    info.Text = S.Get("instKb", sentKb, kb) + left;
                    action.Text = S.Get("instCancel");
                    break;
                case InstallUpdate.Kind.Done:
                    title.Text = u.Text ?? "";
                    icon.Visibility = Visibility.Visible; iconText.Text = "✓";
                    icon.SetResourceReference(Border.BackgroundProperty, "Ok");
                    fill.SetResourceReference(Border.BackgroundProperty, "Ok");
                    fill.Width = w;
                    info.Text = S.Get("instDoneInfo", u.Name, (int)Math.Round(u.Seconds));
                    action.Text = "";
                    hide.Start();
                    break;
                case InstallUpdate.Kind.Failed:
                    title.Text = u.Fraction > 0 && u.Fraction < 1 ? S.Get("instFailAt", (int)Math.Floor(u.Fraction * 100)) : (u.Error ?? S.Get("instFail"));
                    title.ToolTip = u.Error;
                    icon.Visibility = Visibility.Visible; iconText.Text = "!";
                    icon.SetResourceReference(Border.BackgroundProperty, "Err");
                    fill.SetResourceReference(Border.BackgroundProperty, "Err");
                    fill.Width = Math.Max(6, w * u.Fraction);
                    info.Text = S.Get("instUnchanged");
                    action.Text = S.Get("instRetry");
                    break;
                case InstallUpdate.Kind.Cancelled:
                    popup.IsOpen = false;
                    return;
            }
            if (open || first && u.State != InstallUpdate.Kind.Uploading) popup.IsOpen = true;
        }
    }
}
