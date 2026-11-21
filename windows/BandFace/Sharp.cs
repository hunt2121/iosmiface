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
    /// рівно під пікселі екрана — з урахуванням масштабу Windows (125 %, 150 %…). Тоді WPF малює її 1:1, без власного
    /// розтягування й без зсуву на пів пікселя, від яких картинка «пливе».
    /// </summary>
    static class Sharp
    {
        static readonly DependencyProperty OriginalProperty =
            DependencyProperty.RegisterAttached("Original", typeof(BitmapSource), typeof(Sharp));
        static readonly DependencyProperty HookedProperty =
            DependencyProperty.RegisterAttached("Hooked", typeof(bool), typeof(Sharp));

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
            var dpi = VisualTreeHelper.GetDpi(img);
            int pw = Math.Max(1, (int)Math.Round(size.Width * dpi.DpiScaleX)), ph = Math.Max(1, (int)Math.Round(size.Height * dpi.DpiScaleY));
            var sizes = Cache.GetOrCreateValue(b);
            long key = ((long)pw << 32) | (uint)ph;
            if (!sizes.TryGetValue(key, out var ready))
            {
                ready = Render(b, pw, ph, dpi);
                sizes[key] = ready;
            }
            img.Stretch = Stretch.Fill;
            img.Source = ready;
        }

        /// <summary>Розмір місця під картинку: заданий розмір рамки (капсули мають сталий), інакше фактичний</summary>
        static Size Box(Image img)
        {
            if (img.Parent is FrameworkElement p && !double.IsNaN(p.Width) && !double.IsNaN(p.Height)) return new Size(p.Width, p.Height);
            return new Size(img.ActualWidth, img.ActualHeight);
        }

        static BitmapSource Render(BitmapSource b, int pw, int ph, DpiScale dpi)
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
            var result = BitmapSource.Create(pw, ph, 96 * dpi.DpiScaleX, 96 * dpi.DpiScaleY, PixelFormats.Pbgra32, null, pixels, pw * 4);
            result.Freeze();
            return result;
        }
    }
}
