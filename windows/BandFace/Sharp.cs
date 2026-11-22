using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace BandFace
{
    /// <summary>
    /// Чіткі превʼю: велика картинка (з сервера чи з рендера) заздалегідь зменшується якісно (Fant) і обрізається як UniformToFill
    /// рівно під пікселі екрана — з урахуванням масштабу Windows (125 %, 150 %…) і Viewbox. Тоді WPF малює її 1:1, без власного
    /// розтягування й без зсуву на пів пікселя, від яких картинка «пливе».
    /// </summary>
    static class Sharp
    {
        static readonly DependencyProperty OriginalProperty =
            DependencyProperty.RegisterAttached("Original", typeof(BitmapSource), typeof(Sharp));
        static readonly DependencyProperty HookedProperty =
            DependencyProperty.RegisterAttached("Hooked", typeof(bool), typeof(Sharp));
        static readonly DependencyProperty LastProperty =
            DependencyProperty.RegisterAttached("Last", typeof(Size?), typeof(Sharp));

        /// <summary>Готові зменшені копії для кожного розміру в пікселях (кадри анімації й повторні показу — без перерахунку)</summary>
        static readonly ConditionalWeakTable<BitmapSource, Dictionary<long, BitmapSource>> Cache =
            new ConditionalWeakTable<BitmapSource, Dictionary<long, BitmapSource>>();

        /// <summary>Показати src в img як UniformToFill, але чітко</summary>
        public static void Show(Image img, ImageSource src)
        {
            if (!(src is BitmapSource b))
            {
                img.ClearValue(OriginalProperty);
                img.Source = src;
                return;
            }
            if (!(bool)img.GetValue(HookedProperty))
            {
                img.SetValue(HookedProperty, true);
                img.SizeChanged += (s, e) => Update(img);
                img.DpiChanged += (s, e) => Update(img);
                // у Viewbox розмір на екрані змінюється без SizeChanged самої картинки — перевіряємо після кожного макета
                // (лише там: картки магазину й редактора у Viewbox не лежать, їм ця перевірка не потрібна)
                if (InViewbox(img))
                    img.LayoutUpdated += (s, e) => { if (img.GetValue(OriginalProperty) != null && Pixels(img) != (Size?)img.GetValue(LastProperty)) Update(img); };
            }
            img.SetValue(OriginalProperty, b);
            img.Stretch = Stretch.Fill;   // картинка вже рівно потрібного розміру
            Update(img);
        }

        static void Update(Image img)
        {
            if (!(img.GetValue(OriginalProperty) is BitmapSource b)) return;
            Size size = Box(img);
            if (size.Width <= 0 || size.Height <= 0 || b.PixelWidth == 0 || b.PixelHeight == 0)
            {
                img.Stretch = Stretch.UniformToFill;
                img.Source = b;
                return;
            }
            var px = Pixels(img) ?? new Size(size.Width * VisualTreeHelper.GetDpi(img).DpiScaleX, size.Height * VisualTreeHelper.GetDpi(img).DpiScaleY);
            img.SetValue(LastProperty, (Size?)px);
            int pw = Math.Max(1, (int)Math.Round(px.Width)), ph = Math.Max(1, (int)Math.Round(px.Height));
            var sizes = Cache.GetOrCreateValue(b);
            long key = ((long)pw << 32) | (uint)ph;
            if (!sizes.TryGetValue(key, out var ready))
            {
                ready = Render(b, pw, ph, 96 * pw / size.Width, 96 * ph / size.Height);
                sizes[key] = ready;
            }
            img.Stretch = Stretch.Fill;
            img.Source = ready;
        }

        /// <summary>Розмір місця під картинку: заданий розмір рамки (капсули мають сталий), інакше фактичний</summary>
        static Size Box(Image img)
        {
            if (!double.IsNaN(img.Width) && !double.IsNaN(img.Height)) return new Size(img.Width, img.Height);
            if (img.Parent is FrameworkElement p && !double.IsNaN(p.Width) && !double.IsNaN(p.Height)) return new Size(p.Width, p.Height);
            return new Size(img.ActualWidth, img.ActualHeight);
        }

        static bool InViewbox(DependencyObject d)
        {
            for (d = VisualTreeHelper.GetParent(d) ?? LogicalTreeHelper.GetParent(d); d != null; d = d is Visual ? VisualTreeHelper.GetParent(d) ?? LogicalTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d))
                if (d is Viewbox) return true;
            return false;
        }

        /// <summary>Скільки пікселів екрана займає місце під картинку — з масштабом Windows і Viewbox над нею (null — ще не на екрані)</summary>
        static Size? Pixels(Image img)
        {
            var size = Box(img);
            var src = PresentationSource.FromVisual(img);
            if (src?.RootVisual == null || src.CompositionTarget == null || size.Width <= 0 || size.Height <= 0) return null;
            try
            {
                var toRoot = img.TransformToAncestor(src.RootVisual);
                var r = toRoot.TransformBounds(new Rect(0, 0, size.Width, size.Height));
                var m = src.CompositionTarget.TransformToDevice;
                return new Size(Math.Round(r.Width * m.M11), Math.Round(r.Height * m.M22));
            }
            catch (InvalidOperationException) { return null; }
        }

        static BitmapSource Render(BitmapSource b, int pw, int ph, double dpiX, double dpiY)
        {
            var dv = new DrawingVisual();
            RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
            using (var dc = dv.RenderOpen())
            {
                double s = Math.Max((double)pw / b.PixelWidth, (double)ph / b.PixelHeight);
                double w = b.PixelWidth * s, h = b.PixelHeight * s;
                dc.DrawImage(b, new Rect((pw - w) / 2, (ph - h) / 2, w, h));
            }
            // малюємо в пікселях (96 dpi), а потім кажемо WPF справжню щільність — розмір у DIP збігається з місцем
            var rtb = new RenderTargetBitmap(pw, ph, 96, 96, PixelFormats.Pbgra32);
            rtb.Render(dv);
            var pixels = new byte[pw * ph * 4];
            rtb.CopyPixels(pixels, pw * 4, 0);
            var result = BitmapSource.Create(pw, ph, dpiX, dpiY, PixelFormats.Pbgra32, null, pixels, pw * 4);
            result.Freeze();
            return result;
        }
    }

    /// <summary>Капсула превʼю, як на вкладці «Головна»: обведення 3 px — сіре, зелене для циферблата на екрані браслета;
    /// картинка (img) обрізана по капсулі. Спільна для магазину й списку редактора</summary>
    static class PreviewCapsule
    {
        static readonly Brush Active = Frozen(Color.FromRgb(0x22, 0xA8, 0x46)), Idle = Frozen(Color.FromRgb(0x7A, 0x7A, 0x7A));
        static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

        public static Border Make(double w, double h, bool active, out Image img)
        {
            img = new Image { Stretch = Stretch.UniformToFill };
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            var inner = new Grid { Width = w, Height = h, Background = Brushes.Black, Clip = new RectangleGeometry(new Rect(0, 0, w, h), w / 2, w / 2) };
            inner.Children.Add(img);
            return new Border
            {
                Width = w + 6, Height = h + 6, CornerRadius = new CornerRadius((w + 6) / 2), Padding = new Thickness(3), Child = inner,
                HorizontalAlignment = HorizontalAlignment.Center, Background = active ? Active : Idle,
            };
        }
    }
}
