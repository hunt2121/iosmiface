using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace BandFace.Store
{
    /// <summary>
    /// «👁 4.8k   ↓ 1.1k» (спершу перегляди, потім завантаження) — значки й числа малюються як контури й ставляться за чорнилом (межами самих штрихів),
    /// а не за рамками тексту, у яких різні порожні поля:
    /// від значка до числа рівно 3 px, стрілка заввишки з цифри, око — 80% (значки — як в iOS), по вертикалі центр чорнила значків — на центрі цифр, а та — по центру елемента.
    /// Пари разом, уся група по центру; між парами MinGap (14 px).
    /// Spread = true: малі числа трохи розсунуті — проміжок від MinGap + 10 до MinGap зі зростанням чисел (у масштабі шрифту).
    /// </summary>
    sealed class StatsRow : FrameworkElement
    {
        public static readonly DependencyProperty ForegroundProperty = DependencyProperty.Register(
            nameof(Foreground), typeof(Brush), typeof(StatsRow), new FrameworkPropertyMetadata(Brushes.Gray, FrameworkPropertyMetadataOptions.AffectsRender));

        public Brush Foreground { get => (Brush)GetValue(ForegroundProperty); set => SetValue(ForegroundProperty, value); }

        public string Downloads = "0";
        public string Views = "0";
        /// <summary>Числа без слів — проміжок між парами (Spread) рахуємо за ними, щоб слова його не змінювали</summary>
        public string GapDownloads, GapViews;
        public double TextSize = 12;
        public bool Spread;
        /// <summary>Найменший проміжок між парами: 14 — сторінка запису, 18 — картка</summary>
        public double MinGap = 14;

        const double IconGap = 3;
        static readonly Typeface Text = new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);   // як підписи поруч

        // Значки як в iOS (SF Symbols arrow.down.to.line і eye), у полі 24×24: лінії, що потім «товщають» пером
        static readonly Geometry ArrowLines = Geometry.Parse("M12,3 L12,15.5 M6.5,10 L12,15.5 L17.5,10 M5,20.5 L19,20.5");
        static readonly Geometry EyeLine = Geometry.Parse("M1.8,12 C4,7.7 7.7,5.2 12,5.2 C16.3,5.2 20,7.7 22.2,12 C20,16.3 16.3,18.8 12,18.8 C7.7,18.8 4,16.3 1.8,12 Z");

        /// <summary>Стрілка до риски: штрих 2.1, круглі кінці</summary>
        static Geometry ArrowShape() =>
            ArrowLines.GetWidenedPathGeometry(new Pen(Brushes.Black, 2.1) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round });

        /// <summary>Око: контур і суцільна зіниця</summary>
        static Geometry EyeShape()
        {
            var g = new GeometryGroup { FillRule = FillRule.Nonzero };
            g.Children.Add(EyeLine.GetWidenedPathGeometry(new Pen(Brushes.Black, 1.9) { LineJoin = PenLineJoin.Round }));
            g.Children.Add(new EllipseGeometry(new Point(12, 12), 3.5, 3.5));
            return g;
        }

        /// <summary>Значок у масштабі: чорнило заввишки height</summary>
        static Geometry Scaled(Geometry g, double height)
        {
            var b = g.Bounds;
            double k = b.Height > 0 ? height / b.Height : 1;
            var c = g.Clone();
            c.Transform = new ScaleTransform(k, k);
            return c.GetFlattenedPathGeometry();
        }

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
            // вертикаль і розмір — за плоскою цифрою «1» (від базової лінії до висоти великих літер);
            // кругла «0» виступає вгору й униз, і стрілка за нею виходила більшою й нижчою
            var digits = Outline("1", Text, TextSize).Bounds;
            // стрілка — рівно заввишки з цифри, око — 80% (як в iOS)
            var arrow = Scaled(ArrowShape(), digits.Height);
            var eye = Scaled(EyeShape(), digits.Height * 0.8);
            double textDy = cy - (digits.Top + digits.Bottom) / 2;

            Rect ra = Ink(arrow), re = Ink(eye), rd = Ink(d), rv = Ink(v);
            double w1 = ra.Width + IconGap + rd.Width, w2 = re.Width + IconGap + rv.Width;
            // між парами 14; з Spread (картка магазину) малі числа трохи розсунуті — як на iPhone:
            // ширина чорнила обох пар ≤ 36 (×масштаб) — 24, ≥ 64 — 14, між ними плавно
            double k = TextSize / 10.5, gap = MinGap;
            if (Spread)
            {
                double b1 = w1, b2 = w2;
                if (GapDownloads != null && GapViews != null)
                {
                    b1 = ra.Width + IconGap + Ink(Outline(GapDownloads, Text, TextSize)).Width;
                    b2 = re.Width + IconGap + Ink(Outline(GapViews, Text, TextSize)).Width;
                }
                double t = Math.Min(1, Math.Max(0, (64 * k - (b1 + b2)) / (28 * k)));
                gap = (MinGap + 10 * t) * k;
            }
            // спершу перегляди (око), потім завантаження (стрілка)
            double x1 = (w - (w2 + gap + w1)) / 2, x2 = x1 + w2 + gap;

            Draw(dc, eye, x1 - re.Left, cy - (re.Top + re.Bottom) / 2);
            Draw(dc, v, x1 + re.Width + IconGap - rv.Left, textDy);
            Draw(dc, arrow, x2 - ra.Left, cy - (ra.Top + ra.Bottom) / 2);
            Draw(dc, d, x2 + ra.Width + IconGap - rd.Left, textDy);
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
