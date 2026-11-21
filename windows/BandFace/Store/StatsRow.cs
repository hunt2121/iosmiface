using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace BandFace.Store
{
    /// <summary>
    /// «👁 4.8k   ↓ 1.1k» (спершу перегляди, потім завантаження) — значки й числа малюються як контури й ставляться за чорнилом (межами самих штрихів),
    /// а не за рамками тексту, у яких різні порожні поля:
    /// від значка до числа рівно 3 px, стрілка на піксель вища й нижча за цифри, око заввишки з цифри (значки — як в iOS), по вертикалі центр чорнила значків — на центрі цифр, а та — по центру елемента.
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

        // Око як в iOS (SF Symbols eye), у полі 24×24: лінія, що потім «товщає» пером
        static readonly Geometry EyeLine = Geometry.Parse("M1.8,12 C4,7.7 7.7,5.2 12,5.2 C16.3,5.2 20,7.7 22.2,12 C20,16.3 16.3,18.8 12,18.8 C7.7,18.8 4,16.3 1.8,12 Z");

        const double EyeStroke = 2.3;

        /// <summary>Лоток зі стрілкою вниз рівно по чорнилу width × height; лінії line (як в ока), круглі кінці — як в iOS</summary>
        static Geometry ArrowShape(double width, double height, double line)
        {
            double W = width, H = height, r = line / 2;
            var g = new PathGeometry();
            PathFigure Fig(Point start) { var f = new PathFigure { StartPoint = start, IsClosed = false }; g.Figures.Add(f); return f; }
            void To(PathFigure f, double x, double y) => f.Segments.Add(new LineSegment(new Point(x, y), true));
            void Quad(PathFigure f, double cx, double cy, double x, double y) => f.Segments.Add(new QuadraticBezierSegment(new Point(cx, cy), new Point(x, y), true));
            // стрілка
            double cxm = W / 2, tip = H * 0.50, arm = H * 0.24;
            To(Fig(new Point(cxm, r)), cxm, tip);
            var head = Fig(new Point(cxm - arm, tip - arm)); To(head, cxm, tip); To(head, cxm + arm, tip - arm);
            // лоток: боки й дно з заокругленими кутами
            double l = r, rr = W - r, b = H - r, rim = H * 0.58, rad = H * 0.12;
            var tray = Fig(new Point(l, rim));
            To(tray, l, b - rad); Quad(tray, l, b, l + rad, b); To(tray, rr - rad, b); Quad(tray, rr, b, rr, b - rad); To(tray, rr, rim);
            // обідок з виїмкою посередині
            var lip = Fig(new Point(l, rim));
            To(lip, W * 0.30, rim); To(lip, W * 0.36, H * 0.74); To(lip, W * 0.64, H * 0.74); To(lip, W * 0.70, rim); To(lip, rr, rim);
            return g.GetWidenedPathGeometry(new Pen(Brushes.Black, line) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round }).GetFlattenedPathGeometry();
        }

        /// <summary>Око: контур і суцільна зіниця</summary>
        static Geometry EyeShape()
        {
            var g = new GeometryGroup { FillRule = FillRule.Nonzero };
            g.Children.Add(EyeLine.GetWidenedPathGeometry(new Pen(Brushes.Black, EyeStroke) { LineJoin = PenLineJoin.Round }));
            g.Children.Add(new EllipseGeometry(new Point(12, 12), 3.6, 3.6));
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
            // як в iOS: око заввишки з цифри; лоток зі стрілкою на 3 пікселі вужчий за око, на піксель вища й нижча за цифри, лінії як в ока
            double px = 1 / VisualTreeHelper.GetDpi(this).DpiScaleY;
            var eyeRaw = EyeShape();
            var eye = Scaled(eyeRaw, digits.Height);
            double eyeLine = EyeStroke * digits.Height / eyeRaw.Bounds.Height;
            var arrow = ArrowShape(Ink(eye).Width - 3 * px, digits.Height + 2 * px, eyeLine);
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

        /// <summary>Висота плоскої цифри «1» (від базової лінії до верху) у Segoe UI розміру size</summary>
        public static double DigitHeight(double size) =>
            new FormattedText("1", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, Text, size, Brushes.Black, 1).BuildGeometry(new Point(0, 0)).Bounds.Height;

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
