// SPDX-License-Identifier: MIT
// Рамка розміру віджета й слота на полотні: 8 ручок, прилипання до країв екрана й інших елементів (Alt вимикає),
// Shift на куті — зберігає пропорції. Розмір записується одним кроком історії.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using BandFace.Faces;

namespace BandFace.Creator
{
    public partial class EditorView
    {
        /// <summary>«tl» «t» «tr» «r» «br» «b» «bl» «l»; null — ручку не тягнуть</summary>
        string sizeHandle;
        Rect sizeStart, sizeRect;
        List<double> sizeGuideX = new List<double>(), sizeGuideY = new List<double>();
        /// <summary>Кут зберігає пропорції (перемикач у налаштуваннях)</summary>
        internal bool SizeRatioLock;

        /// <summary>Віджети вибраного шару (віджет — один, слот — усі його) й сам шар</summary>
        bool SizeTarget(out List<XNode> ws, out XNode layout)
        {
            ws = null; layout = selected;
            if (selected == null || project == null) return false;
            var res = project.ElementOf(selected);
            if (res == null) return false;
            if (res.Tag == "Widget") { ws = new List<XNode> { res }; return true; }
            if (res.Tag == "Slot") { ws = WidgetSlots.Widgets(project, res); return ws.Count > 0; }
            return false;
        }

        Rect? CurrentSizeRect()
        {
            if (!SizeTarget(out var ws, out var l)) return null;
            return new Rect(l.Int("x"), l.Int("y"), Math.Max(8, ws.Max(x => x.Int("w"))), Math.Max(8, ws.Max(x => x.Int("h"))));
        }

        static IEnumerable<KeyValuePair<string, Point>> SizePoints(Rect r)
        {
            double mx = r.X + r.Width / 2, my = r.Y + r.Height / 2;
            yield return new KeyValuePair<string, Point>("tl", new Point(r.Left, r.Top));
            yield return new KeyValuePair<string, Point>("t", new Point(mx, r.Top));
            yield return new KeyValuePair<string, Point>("tr", new Point(r.Right, r.Top));
            yield return new KeyValuePair<string, Point>("r", new Point(r.Right, my));
            yield return new KeyValuePair<string, Point>("br", new Point(r.Right, r.Bottom));
            yield return new KeyValuePair<string, Point>("b", new Point(mx, r.Bottom));
            yield return new KeyValuePair<string, Point>("bl", new Point(r.Left, r.Bottom));
            yield return new KeyValuePair<string, Point>("l", new Point(r.Left, my));
        }

        bool StartSizeDrag(Point pt)
        {
            var r = CurrentSizeRect();
            if (!r.HasValue) return false;
            double tol = 11 / zoom;
            var best = SizePoints(r.Value).Select(kv => new { kv.Key, D = (kv.Value - pt).Length }).Where(x => x.D <= tol).OrderBy(x => x.D).FirstOrDefault();
            if (best == null) return false;
            sizeHandle = best.Key; sizeStart = r.Value; sizeRect = r.Value;
            return true;
        }

        void MoveSize(Point pt)
        {
            if (sizeHandle == null) return;
            var dev = project.Meta.Device;
            bool snapOn = snap && !Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);
            var others = boxes.Where(b => b.Layout != selected && !AodDim.Is(project, b.Layout, theme)).Select(b => b.Rect).ToList();
            var xs = new List<double> { 0, dev.Width / 2.0, dev.Width }; var ys = new List<double> { 0, dev.Height / 2.0, dev.Height };
            foreach (var o in others) { xs.Add(o.Left); xs.Add(o.Left + o.Width / 2); xs.Add(o.Right); ys.Add(o.Top); ys.Add(o.Top + o.Height / 2); ys.Add(o.Bottom); }
            var gx = new List<double>(); var gy = new List<double>();
            Func<double, List<double>, List<double>, double> sn = (v, c, g) =>
            {
                if (snapOn) { var m = c.OrderBy(x => Math.Abs(x - v)).First(); if (Math.Abs(m - v) <= 4) { g.Add(m); return m; } }
                return Math.Round(v);
            };
            bool L = sizeHandle.Contains("l"), R = sizeHandle.Contains("r"), T = sizeHandle.StartsWith("t"), B = sizeHandle.StartsWith("b");
            double minX = sizeStart.Left, maxX = sizeStart.Right, minY = sizeStart.Top, maxY = sizeStart.Bottom;
            if (L) minX = Math.Min(sn(pt.X, xs, gx), maxX - 8);
            if (R) maxX = Math.Max(sn(pt.X, xs, gx), minX + 8);
            if (T) minY = Math.Min(sn(pt.Y, ys, gy), maxY - 8);
            if (B) maxY = Math.Max(sn(pt.Y, ys, gy), minY + 8);
            if ((SizeRatioLock || Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) && (L || R) && (T || B) && sizeStart.Height > 0)
            {
                double ratio = sizeStart.Width / sizeStart.Height;
                double nh = Math.Max(8, Math.Round((maxX - minX) / ratio));
                if (T) minY = maxY - nh; else maxY = minY + nh;
                gy.Clear();
            }
            sizeGuideX = gx; sizeGuideY = gy;
            sizeRect = new Rect(minX, minY, maxX - minX, maxY - minY);
            DrawOverlay();
        }

        void EndSizeDrag()
        {
            var r = sizeRect; var start = sizeStart;
            sizeHandle = null; sizeGuideX.Clear(); sizeGuideY.Clear();
            if (r == start || !SizeTarget(out var ws, out var l)) { DrawOverlay(); return; }
            int dx = (int)(r.Left - start.Left), dy = (int)(r.Top - start.Top);
            project.Edit(p =>
            {
                foreach (var w in ws)
                {
                    WidgetSlots.SetSize(p, w, (int)r.Width, (int)r.Height);
                    // зсув лівого чи верхнього краю не має зрушувати вміст з місця (вільне розташування)
                    if ((dx != 0 || dy != 0) && WidgetSlots.Arrange(w) == "free")
                        foreach (var it in w.All("Item")) it.Set("x", it.Int("x") - dx).Set("y", it.Int("y") - dy);
                }
                l.Set("x", (int)r.Left).Set("y", (int)r.Top);
            });
        }

        void DrawSizeHandles(Brush sel)
        {
            if (dragPos.HasValue && moved) return;
            var r0 = sizeHandle != null ? sizeRect : CurrentSizeRect();
            if (!r0.HasValue) return;
            var guide = (Brush)FindResource("Guide");
            var r = r0.Value;
            if (sizeHandle != null)
            {
                var fill = new Rectangle { Width = r.Width * zoom, Height = r.Height * zoom, Fill = sel, Opacity = 0.08 };
                Canvas.SetLeft(fill, r.X * zoom); Canvas.SetTop(fill, r.Y * zoom);
                Overlay.Children.Add(fill);
                var dev = project.Meta.Device;
                foreach (var x in sizeGuideX) Ui.GuideLine(Overlay, true, x * zoom, dev.Height * zoom, guide);
                foreach (var y in sizeGuideY) Ui.GuideLine(Overlay, false, y * zoom, dev.Width * zoom, guide);
                var tagBg = (sizeGuideX.Count > 0 || sizeGuideY.Count > 0) ? guide : sel;
                var tag = new Border
                {
                    Background = tagBg, CornerRadius = new CornerRadius(3), Padding = new Thickness(5, 1, 5, 1),
                    Child = new TextBlock { Text = (int)r.Width + " × " + (int)r.Height, Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.SemiBold },
                };
                Canvas.SetLeft(tag, (r.X + r.Width / 2) * zoom - 30); Canvas.SetTop(tag, Math.Max(0, r.Y * zoom - 24));
                Overlay.Children.Add(tag);
            }
            foreach (var kv in SizePoints(r))
            {
                bool edge = kv.Key.Length == 1, horizontal = kv.Key == "t" || kv.Key == "b";
                double w = edge ? (horizontal ? 22 : 11) : 12, h = edge ? (horizontal ? 11 : 22) : 12;
                var hnd = new Rectangle { Width = w, Height = h, RadiusX = 5, RadiusY = 5, Fill = Brushes.White, Stroke = sel, StrokeThickness = 2 };
                Canvas.SetLeft(hnd, kv.Value.X * zoom - w / 2); Canvas.SetTop(hnd, kv.Value.Y * zoom - h / 2);
                Overlay.Children.Add(hnd);
            }
        }
    }
}
