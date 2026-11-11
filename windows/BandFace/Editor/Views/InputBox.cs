// SPDX-License-Identifier: MIT
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BandFace.Creator
{
    /// <summary>Маленьке вікно з одним полем (назва набору цифр тощо)</summary>
    sealed class InputBox : Window
    {
        readonly TextBox box = new TextBox();

        InputBox(string title, string label, string value)
        {
            Title = title;
            Width = 420; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Segoe UI");
            SetResourceReference(BackgroundProperty, "Bg");
            SetResourceReference(ForegroundProperty, "Text");
            var sp = new StackPanel { Margin = new Thickness(20) };
            sp.Children.Add(new TextBlock { Text = label, FontSize = 13, Margin = new Thickness(0, 0, 0, 8), TextWrapping = TextWrapping.Wrap });
            box.Text = value ?? "";
            sp.Children.Add(box);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
            var cancel = new Button { Content = S.Get("cancel"), Style = (Style)FindResource("Btn"), IsCancel = true };
            var ok = new Button { Content = "OK", Style = (Style)FindResource("PrimaryBtn"), IsDefault = true, Margin = new Thickness(10, 0, 0, 0) };
            ok.Click += (s, e) => { if (box.Text.Trim().Length > 0) DialogResult = true; };
            buttons.Children.Add(cancel);
            buttons.Children.Add(ok);
            sp.Children.Add(buttons);
            Content = sp;
            // темний заголовок вікна ставиться до показу — інакше Windows лишає його білим до перемикання вікон
            SourceInitialized += (s, e) => Theme.Apply(this);
            Loaded += (s, e) => { Theme.Apply(this); box.Focus(); box.SelectAll(); };
        }

        public static string Ask(Window owner, string title, string label, string value = "")
        {
            var w = new InputBox(title, label, value) { Owner = owner };
            return w.ShowDialog() == true ? w.box.Text.Trim() : null;
        }
    }
}
