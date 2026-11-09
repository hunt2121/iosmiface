// SPDX-License-Identifier: MIT
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BandFace.Creator
{
    /// <summary>Вибір одного з варіантів великими кнопками: назва, підпис і (за бажанням) мініатюра</summary>
    sealed class ChoiceBox : Window
    {
        public sealed class Item { public string Title, Sub; public FrameworkElement Preview; public bool Enabled = true; }

        int picked = -1;

        ChoiceBox(string title, IList<Item> items)
        {
            Title = title;
            Width = 440; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Segoe UI");
            SetResourceReference(BackgroundProperty, "Bg");
            SetResourceReference(ForegroundProperty, "Text");
            var sp = new StackPanel { Margin = new Thickness(20) };
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                int idx = i;
                var grid = new Grid();
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                text.Children.Add(new TextBlock { Text = it.Title, FontSize = 14, FontWeight = FontWeights.SemiBold });
                if (!string.IsNullOrEmpty(it.Sub))
                {
                    var sub = new TextBlock { Text = it.Sub, FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) };
                    sub.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
                    text.Children.Add(sub);
                }
                grid.Children.Add(text);
                if (it.Preview != null) { it.Preview.Margin = new Thickness(10, 0, 0, 0); it.Preview.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(it.Preview, 1); grid.Children.Add(it.Preview); }
                var b = new Button
                {
                    Content = grid, Style = (Style)FindResource("Btn"), Height = double.NaN, Padding = new Thickness(14, 10, 14, 10),
                    HorizontalContentAlignment = HorizontalAlignment.Stretch, Margin = new Thickness(0, 0, 0, 8), IsEnabled = it.Enabled,
                };
                b.Click += (s, e) => { picked = idx; DialogResult = true; };
                sp.Children.Add(b);
            }
            var cancel = new Button { Content = S.Get("cancel"), Style = (Style)FindResource("Btn"), IsCancel = true, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 0) };
            sp.Children.Add(cancel);
            Content = sp;
            Loaded += (s, e) => Theme.Apply(this);
        }

        /// <summary>Номер вибраного варіанта або -1</summary>
        public static int Ask(Window owner, string title, IList<Item> items)
        {
            var w = new ChoiceBox(title, items) { Owner = owner };
            return w.ShowDialog() == true ? w.picked : -1;
        }
    }
}
