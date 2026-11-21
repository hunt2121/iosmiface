using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace BandFace.Store
{
    /// <summary>
    /// «↓ 1.1k   👁 4.8k» — значки й числа малюються як контури й ставляться за чорнилом (межами самих штрихів),
    /// а не за рамками тексту, у яких різні порожні поля:
    /// від значка до числа рівно 3 px, стрілка заввишки з цифри, по вертикалі всі по центру висоти цифр, а та — по центру елемента.
    /// Разом (Spread = false): між парами 14 px, уся група по центру.
    /// Розведено (Spread = true, картка магазину): центри пар на 18% ширини від середини, але між парами не менше 16 px —
    /// малі числа не злипаються посередині, великі не налазять на краї.
    /// </summary>
    sealed class StatsRow : FrameworkElement
    {
        public static readonly DependencyProperty ForegroundProperty = DependencyProperty.Register(
            nameof(Foreground), typeof(Brush), typeof(StatsRow), new FrameworkPropertyMetadata(Brushes.Gray, FrameworkPropertyMetadataOptions.AffectsRender));

        public Brush Foreground { get => (Brush)GetValue(ForegroundProperty); set => SetValue(ForegroundProperty, value); }

        public string Downloads = "0";
        public string Views = "0";
        public double TextSize = 12;
        public bool Spread;

        /// <summary>Segoe MDL2 Assets: «Завантажити» і «Переглянути»</summary>
        const string ArrowGlyph = "\uE896", EyeGlyph = "\uE890";
        const double IconGap = 3, PairGap = 14, MinPairGap = 16, SpreadShare = 0.18;
        static readonly Typeface Text = new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
        static readonly Typeface Icons = new Typeface(new FontFamily("Segoe MDL2 Assets"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);

        public StatsRow()
        {
            SetResourceReference(ForegroundProperty, "Sub");
            SnapsToDevicePixels = true;
        }

        Geometry Outline(string s, Typeface tf, double size) =>
            new FormattedText(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, tf, size, Brushes.Black,
                VisualTreeHelper.GetDpi(this).PixelsPerDip).BuildGeometry(new Point(0, 0));

        protected override Size MeasureOverride(Size available) => new Size(0, Math.Ceiling(TextSize * 1.6));

        protected override void OnRender(DrawingContext dc)
        {
            double w = ActualWidth, cy = ActualHeight / 2;
            if (w <= 0) return;
            var d = Outline(Downloads, Text, TextSize);
            var v = Outline(Views, Text, TextSize);
            // вертикаль: центр висоти цифр (у слів можуть бути виносні елементи — по них не центруємо)
            var digits = Outline("0", Text, TextSize).Bounds;
            // значки такого розміру, щоб стрілка була рівно заввишки з цифри; око — у тому ж масштабі
            double probe = Outline(ArrowGlyph, Icons, TextSize).Bounds.Height;
            double iconSize = probe > 0 ? TextSize * digits.Height / probe : TextSize;
            var arrow = Outline(ArrowGlyph, Icons, iconSize);
            var eye = Outline(EyeGlyph, Icons, iconSize);
            double textDy = cy - (digits.Top + digits.Bottom) / 2;

            Rect ra = Ink(arrow), re = Ink(eye), rd = Ink(d), rv = Ink(v);
            double w1 = ra.Width + IconGap + rd.Width, w2 = re.Width + IconGap + rv.Width;
            double x1, x2;
            if (Spread)
            {
                double c = w / 2, off = w * SpreadShare;
                x1 = c - off - w1 / 2;
                x2 = c + off - w2 / 2;
                double gap = x2 - (x1 + w1);
                if (gap < MinPairGap) { x1 -= (MinPairGap - gap) / 2; x2 += (MinPairGap - gap) / 2; }
            }
            else
            {
                x1 = (w - (w1 + PairGap + w2)) / 2;
                x2 = x1 + w1 + PairGap;
            }

            Draw(dc, arrow, x1 - ra.Left, cy - (ra.Top + ra.Bottom) / 2);
            Draw(dc, d, x1 + ra.Width + IconGap - rd.Left, textDy);
            Draw(dc, eye, x2 - re.Left, cy - (re.Top + re.Bottom) / 2);
            Draw(dc, v, x2 + re.Width + IconGap - rv.Left, textDy);
        }

        static Rect Ink(Geometry g) => g.Bounds.IsEmpty ? new Rect(0, 0, 0, 0) : g.Bounds;

        void Draw(DrawingContext dc, Geometry g, double dx, double dy)
        {
            if (g.Bounds.IsEmpty) return;
            dc.PushTransform(new TranslateTransform(dx, dy));
            dc.DrawGeometry(Foreground, null, g);
            dc.Pop();
        }
    }
}
