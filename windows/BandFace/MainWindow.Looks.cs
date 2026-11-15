using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using BandFace.Creator;

namespace BandFace
{
    /// <summary>
    /// Картка встановлення: стилі й кольори вибраного файла — колонка праворуч від поля перетягування
    /// (зʼявляється лише коли у файлі кілька стилів або кольорів). Капсула показує вибраний стиль і колір.
    /// </summary>
    public partial class MainWindow
    {
        const double LooksWidth = 200, LooksGap = 16;

        Border LooksPanel;
        List<Tuple<string, int>> _lookStyles;   // назва стилю й номер його теми у файлі
        List<string> _lookColors;
        int _lookStyle, _lookColor;
        FaceRenderer _lookRenderer;
        FaceProject _lookProject;

        void InitLooks()
        {
            LooksPanel = new Border { Width = LooksWidth, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0), Visibility = Visibility.Collapsed };
            Grid.SetRow(LooksPanel, 4);
            InfoColumn.Children.Add(LooksPanel);
            ButtonsRow.SizeChanged += (s, e) => UpdatePickLabel();
            Loaded += (s, e) => { EqualLabelSpacing(BandLabel); EqualLabelSpacing(InstallLabel); };
        }

        /// <summary>Напис над карткою («Пристрій», «Встановлення циферблата»): під літерами стільки ж місця, скільки над ними
        /// від краю картки (за розмірами самого шрифту, а не рамки рядка)</summary>
        void EqualLabelSpacing(TextBlock label)
        {
            var tf = new Typeface(label.FontFamily, label.FontStyle, label.FontWeight, label.FontStretch);
            double size = label.FontSize;
            double lineHeight = label.FontFamily.LineSpacing * size;
            double baseline = label.FontFamily.Baseline * size;
            double caps = tf.CapsHeight * size;
            double above = 16 + (baseline - caps);           // відступ картки (CardBox, 16) + порожнє місце над великими літерами
            double below = lineHeight - baseline;             // порожнє місце під базовою лінією в рамці рядка
            label.Margin = new Thickness(0, 0, 0, Math.Max(8, Math.Round(above - below, 1)));
        }

        /// <summary>Стилі й кольори щойно вибраного файла; немає — колонку сховано, поле й кнопки на всю ширину</summary>
        void UpdateLooks()
        {
            _lookStyles = null; _lookColors = null; _lookStyle = 0; _lookColor = 0;
            _lookRenderer = null; _lookProject = null;
            if (_faceData != null)
            {
                try
                {
                    var u = FaceProject.Unpack(_faceData);
                    var p = new FaceProject("looks", System.IO.Path.GetTempPath(), u.Item1, u.Item2, new ProjectMeta());
                    var themes = p.Themes;
                    var styles = new List<Tuple<string, int>>();
                    // старі файли без типів тем: друга тема — AOD
                    if (themes.Count == 2 && themes.All(t => !t.Has("type"))) styles.Add(Tuple.Create(themes[0].Str("name") ?? "", 0));
                    else for (int i = 0; i < themes.Count; i++)
                            if (themes[i].Str("type") != "AOD" && p.Layouts(i).Count > 0) styles.Add(Tuple.Create(themes[i].Str("name") ?? "", i));
                    var colors = ColorVariants.Colors(p);
                    if (styles.Count > 1 || colors.Count > 1)
                    {
                        _lookStyles = styles; _lookColors = colors;
                        _lookProject = p; _lookRenderer = new FaceRenderer(p);
                    }
                }
                catch (Exception ex) { AddLog("looks: " + ex.Message); }
            }
            bool show = _lookStyles != null;
            LooksPanel.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
            // кнопки й поле — однакової ширини; колонка починається на рівні поля
            double right = show ? LooksWidth + LooksGap : 0;
            ButtonsRow.Margin = new Thickness(0, 16, right, 0);
            Zone.Margin = new Thickness(0, 16, right, 0);
            if (show) BuildLooks();
            UpdatePickLabel();
        }

        void BuildLooks()
        {
            var dock = new DockPanel { LastChildFill = false };
            bool styles = _lookStyles.Count > 1, colors = _lookColors.Count > 1;
            var hint = new TextBlock
            {
                Text = S.Get(styles && colors ? "lookHintBoth" : styles ? "lookHintStyle" : "lookHintColor"),
                FontSize = 12, Foreground = (Brush)FindResource("Sub"), TextWrapping = TextWrapping.Wrap,
            };
            DockPanel.SetDock(hint, Dock.Bottom);
            dock.Children.Add(hint);
            var top = new StackPanel();
            DockPanel.SetDock(top, Dock.Top);
            if (styles)
            {
                top.Children.Add(Heading(S.Get("lookStyle")));
                // до двох — списком; більше — по два в ряд, щоб картка не росла
                Panel list = _lookStyles.Count > 2 ? (Panel)new UniformGrid { Columns = 2 } : new StackPanel();
                for (int i = 0; i < _lookStyles.Count; i++)
                {
                    int idx = i;
                    var name = _lookStyles[i].Item1.Length > 0 ? _lookStyles[i].Item1 : S.Get("storeStyleN", i + 1);
                    var t = new ToggleButton { Style = (Style)FindResource("Chip"), Content = name, IsChecked = i == _lookStyle, Height = 30, FontSize = 13, ToolTip = name,
                        Margin = new Thickness(0, 0, _lookStyles.Count > 2 && i % 2 == 0 ? 6 : 0, 6) };
                    t.Click += (s, e) => { _lookStyle = idx; BuildLooks(); ShowLook(); };
                    list.Children.Add(t);
                }
                top.Children.Add(list);
            }
            if (colors)
            {
                var h = Heading(S.Get("lookColor"));
                if (styles) h.Margin = new Thickness(0, 10, 0, 8);
                top.Children.Add(h);
                var wrap = new WrapPanel { Width = LooksWidth, HorizontalAlignment = HorizontalAlignment.Left };
                for (int i = 0; i < _lookColors.Count; i++)
                {
                    int idx = i;
                    Color c;
                    try { c = (Color)ColorConverter.ConvertFromString(_lookColors[i]); } catch (Exception) { c = Colors.Gray; }
                    var dot = new Border
                    {
                        Width = 32, Height = 32, CornerRadius = new CornerRadius(16), Padding = new Thickness(3), BorderThickness = new Thickness(2),
                        BorderBrush = i == _lookColor ? new SolidColorBrush(c) : Brushes.Transparent, Margin = new Thickness(0, 0, 8, 8),
                        Cursor = Cursors.Hand, ToolTip = _lookColors[i], Background = Brushes.Transparent,
                        Child = new Ellipse { Fill = new SolidColorBrush(c), Stroke = new SolidColorBrush(Color.FromArgb(40, 128, 128, 128)), StrokeThickness = 0.5 },
                    };
                    dot.MouseLeftButtonUp += (s, e) => { _lookColor = idx; BuildLooks(); ShowLook(); };
                    wrap.Children.Add(dot);
                }
                top.Children.Add(wrap);
            }
            dock.Children.Add(top);
            LooksPanel.Child = dock;
        }

        TextBlock Heading(string text) => new TextBlock { Text = text, FontSize = 13, Foreground = (Brush)FindResource("Sub"), Margin = new Thickness(0, 0, 0, 8) };

        /// <summary>Капсула — вибраний стиль і колір; основний (перший стиль, перший колір) — звичайне превʼю файла з анімацією</summary>
        void ShowLook()
        {
            if (_lookRenderer == null || _faceData == null) return;
            StopAnimation();
            if (_lookStyle == 0 && _lookColor == 0) { ShowPreview(_faceData); return; }
            try
            {
                double dpi = VisualTreeHelper.GetDpi(this).DpiScaleY;
                _lookRenderer.ColorVariant = _lookColor;
                var img = _lookRenderer.Render(_lookStyles[_lookStyle].Item2, Math.Max(328, CapsuleInner.Height * dpi * 1.5) / _lookProject.Meta.Device.Height).Image;
                PreviewImage.Source = img;
            }
            catch (Exception ex) { AddLog("look: " + ex.Message); }
            finally { _lookRenderer.ColorVariant = 0; }
        }

        /// <summary>Вузьке вікно: повний напис «Вибрати інший файл» не вміщається в кнопку — коротший «Інший файл»</summary>
        void UpdatePickLabel()
        {
            if (_face == null) { PickBtn.Content = S.Get("pick"); return; }
            var full = S.Get("pickOther");
            var ft = new FormattedText(full, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface(PickBtn.FontFamily, PickBtn.FontStyle, PickBtn.FontWeight, PickBtn.FontStretch), PickBtn.FontSize, Brushes.Black,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);
            double room = PickBtn.ActualWidth - PickBtn.Padding.Left - PickBtn.Padding.Right - 4;
            PickBtn.Content = PickBtn.ActualWidth > 0 && ft.Width > room ? S.Get("pickOtherShort") : full;
        }
    }
}
