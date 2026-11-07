// SPDX-License-Identifier: MIT
// Ручки на полотні: кінці дуги (початок і довжина) та кінці лінії (будь-який кут).
// Прив'язка: кути кратні 45° (у межах 4°), довжина дуги — 90/180/270/360°; Alt вимикає прив'язку.

using System;
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
        const double SnapDeg = 4;

        /// <summary>«a0»/«a1» — початок/кінець дуги, «l0»/«l1» — кінці лінії; null — ручку не тягнуть</summary>
        string handle;
        XNode handleRes;
        Generator handleGen;
        // поточний стан під час перетягування
        double hStart, hRange;
        Point hA, hB;
        bool hSnapped;

        /// <summary>Дуга чи лінія вибраного шару (null — інший елемент)</summary>
        XNode GaugeRes(out ElementKind kind)
        {
            kind = ElementKind.Other;
            if (selected == null || project == null) return null;
            var res = project.ElementOf(selected);
            kind = Elements.Of(res, project);
            return kind == ElementKind.Arc || kind == ElementKind.Line ? res : null;
        }

        Point ArcCenter(XNode res) => new Point(selected.Int("x") + res.Int("pivotX"), selected.Int("y") + res.Int("pivotY"));

        static Point OnArc(Point c, double r, double deg)
        {
            double t = deg * Math.PI / 180;
            return new Point(c.X + r * Math.Sin(t), c.Y - r * Math.Cos(t));
        }

        static double AngleOf(Point c, Point p) { var a = Math.Atan2(p.X - c.X, -(p.Y - c.Y)) * 180 / Math.PI; return a < 0 ? a + 360 : a; }
        static double Norm360(double a) { a %= 360; return a < 0 ? a + 360 : a; }

        /// <summary>До найближчого кратного step, якщо ближче за SnapDeg</summary>
        static double SnapTo(double a, double step, out bool snapped)
        {
            double n = Math.Round(a / step) * step;
            snapped = Math.Abs(n - a) <= SnapDeg;
            return snapped ? n : Math.Round(a);
        }

        /// <summary>Поточні кінці: для дуги — точки на радіусі, для лінії — кінці в координатах циферблата</summary>
        bool Ends(XNode res, ElementKind kind, out Point a, out Point b)
        {
            if (kind == ElementKind.Arc)
            {
                var c = ArcCenter(res);
                double r = res.Int("barRadius");
                a = OnArc(c, r, res.Int("angleStart"));
                b = OnArc(c, r, res.Int("angleStart") + res.Int("angleRange"));
                return r > 0;
            }
            a = new Point(selected.Int("x") + res.Int("startX"), selected.Int("y") + res.Int("startY"));
            b = new Point(selected.Int("x") + res.Int("endX"), selected.Int("y") + res.Int("endY"));
            return true;
        }

        bool StartHandleDrag(Point pt)
        {
            var res = GaugeRes(out var kind);
            if (res == null || !Ends(res, kind, out var a, out var b)) return false;
            var gen = project.Meta.Gen(res.Str("name"));
            // лінію без параметрів малювання (своя картинка) не перемальовуємо
            if (kind == ElementKind.Line && (gen == null || !gen.Drawn)) return false;
            double tol = 9 / zoom;
            string h = null;
            if ((pt - b).Length <= tol) h = kind == ElementKind.Arc ? "a1" : "l1";
            else if ((pt - a).Length <= tol) h = kind == ElementKind.Arc ? "a0" : "l0";
            if (h == null) return false;
            handle = h; handleRes = res; handleGen = gen != null ? ElementFactory.Synced(res, gen) : null;
            hStart = res.Int("angleStart"); hRange = res.Int("angleRange"); hA = a; hB = b; hSnapped = false;
            return true;
        }

        void MoveHandle(Point pt)
        {
            var res = handleRes;
            bool snapOn = snap && !Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);
            hSnapped = false;
            if (handle[0] == 'a')
            {
                var c = ArcCenter(res);
                double th = AngleOf(c, pt);
                bool s1 = false;
                if (snapOn) th = Norm360(SnapTo(th, 45, out s1)); else th = Math.Round(th);
                double s0 = res.Int("angleStart"), r0 = res.Int("angleRange");
                bool ccw = r0 < 0;
                if (handle == "a1")
                {
                    double r = ccw ? -Norm360(s0 - th) : Norm360(th - s0);
                    if (Math.Abs(r) < 1) r = (ccw ? -1 : 1) * (Math.Abs(hRange) > 180 ? 360 : 1);
                    if (snapOn)
                    {
                        // довжина — до 90/180/270/360
                        double m = Math.Round(Math.Abs(r) / 90) * 90;
                        if (m > 0 && Math.Abs(m - Math.Abs(r)) <= SnapDeg) { r = Math.Sign(r) * m; s1 = true; }
                    }
                    hStart = s0; hRange = r;
                }
                else
                {
                    double end = s0 + r0;
                    double r = ccw ? -Norm360(th - end) : Norm360(end - th);
                    if (Math.Abs(r) < 1) r = (ccw ? -1 : 1) * 360;
                    hStart = th; hRange = r;
                }
                hSnapped = s1;
            }
            else
            {
                var fixedPt = handle == "l1" ? hA : hB;
                var orig = handle == "l1" ? hB : hA;
                double dx = pt.X - fixedPt.X, dy = pt.Y - fixedPt.Y;
                double len = Math.Max(4, Math.Sqrt(dx * dx + dy * dy));
                double ang = Math.Atan2(dy, dx) * 180 / Math.PI;
                if (snapOn) ang = SnapTo(ang, 45, out hSnapped);
                double t = ang * Math.PI / 180;
                var moved = new Point(Math.Round(fixedPt.X + Math.Cos(t) * len), Math.Round(fixedPt.Y + Math.Sin(t) * len));
                if (handle == "l1") hB = moved; else hA = moved;
            }
            DrawOverlay();
        }

        void EndHandleDrag()
        {
            var h = handle; var res = handleRes; var gen = handleGen; var layout = selected;
            handle = null; handleRes = null; handleGen = null;
            if (res == null || layout == null) { DrawOverlay(); return; }
            if (h[0] == 'a')
            {
                if ((int)hStart == res.Int("angleStart") && (int)hRange == res.Int("angleRange")) { DrawOverlay(); return; }
                if (gen != null && gen.Drawn)
                {
                    var g = gen.Copy(); g.Start = hStart; g.Range = hRange;
                    project.Edit(p => ElementFactory.Regenerate(p, res.Str("name"), g));
                }
                else project.Edit(p => res.Set("angleStart", (int)hStart).Set("angleRange", (int)hRange));
            }
            else
            {
                Ends(res, ElementKind.Line, out var a, out var b);
                if (a == hA && b == hB) { DrawOverlay(); return; }
                var A = hA; var B = hB;
                project.Edit(p => ElementFactory.PlaceLine(p, res, layout, gen, A.X, A.Y, B.X, B.Y));
            }
        }

        // MARK: Малювання ручок

        Point Scr(Point p) => new Point(p.X * zoom, p.Y * zoom);

        void Dot(Point facePt, Brush stroke, double size = 12)
        {
            var s = Scr(facePt);
            var e = new Ellipse { Width = size, Height = size, Fill = Brushes.White, Stroke = stroke, StrokeThickness = 2 };
            Canvas.SetLeft(e, s.X - size / 2); Canvas.SetTop(e, s.Y - size / 2);
            Overlay.Children.Add(e);
        }

        void HandleTag(Point facePt, string text, Brush bg)
        {
            var s = Scr(facePt);
            var t = new Border
            {
                Background = bg, CornerRadius = new CornerRadius(3), Padding = new Thickness(5, 1, 5, 1),
                Child = new TextBlock { Text = text, Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.SemiBold },
            };
            Canvas.SetLeft(t, s.X + 10); Canvas.SetTop(t, s.Y - 24);
            Overlay.Children.Add(t);
        }

        void DashedLine(Point a, Point b, Brush br)
        {
            var sa = Scr(a); var sb = Scr(b);
            Overlay.Children.Add(new Line { X1 = sa.X, Y1 = sa.Y, X2 = sb.X, Y2 = sb.Y, Stroke = br, StrokeThickness = 1.2, StrokeDashArray = new DoubleCollection { 5, 3 } });
        }

        void DrawHandles(Brush sel)
        {
            if (dragPos.HasValue && moved) return;
            var res = handle != null ? handleRes : GaugeRes(out _);
            if (res == null) return;
            var kind = Elements.Of(res, project);
            var guide = (Brush)FindResource("Guide");
            if (!Ends(res, kind, out var a, out var b)) return;
            if (kind == ElementKind.Arc)
            {
                var c = ArcCenter(res);
                double r = res.Int("barRadius"), w = Math.Max(2, res.Int("barWidth"));
                if (handle != null)
                {
                    a = OnArc(c, r, hStart); b = OnArc(c, r, hStart + hRange);
                    // напівпрозорий слід нової дуги
                    var sc = Scr(c);
                    Geometry g;
                    if (Math.Abs(hRange) >= 359.5) g = new EllipseGeometry(sc, r * zoom, r * zoom);
                    else
                    {
                        var fig = new PathFigure { StartPoint = Scr(a) };
                        fig.Segments.Add(new ArcSegment(Scr(b), new Size(r * zoom, r * zoom), 0, Math.Abs(hRange) > 180,
                            hRange >= 0 ? SweepDirection.Clockwise : SweepDirection.Counterclockwise, true));
                        var pg = new PathGeometry(); pg.Figures.Add(fig); g = pg;
                    }
                    Overlay.Children.Add(new Path { Data = g, Stroke = sel, StrokeThickness = w * zoom, Opacity = 0.45,
                        StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round });
                    var moving = handle == "a1" ? b : a;
                    DashedLine(c, moving, hSnapped ? guide : sel);
                    HandleTag(moving, handle == "a1" ? S.Get("lenShort", (int)Math.Abs(hRange)) : S.Get("startShort", (int)Norm360(hStart)), hSnapped ? guide : sel);
                }
                Dot(a, sel); Dot(b, sel, 14);
            }
            else
            {
                if (handle != null)
                {
                    a = hA; b = hB;
                    var sa = Scr(a); var sb = Scr(b);
                    Overlay.Children.Add(new Line { X1 = sa.X, Y1 = sa.Y, X2 = sb.X, Y2 = sb.Y, Stroke = sel, StrokeThickness = Math.Max(2, res.Int("barWidth")) * zoom,
                        Opacity = 0.45, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round });
                    double ang = Math.Atan2(b.Y - a.Y, b.X - a.X) * 180 / Math.PI;
                    if (hSnapped)
                    {
                        // напрямна через усю лінію
                        var d = b - a; d.Normalize();
                        DashedLine(a - d * 40, b + d * 40, guide);
                    }
                    var moving = handle == "l1" ? b : a;
                    HandleTag(moving, S.Get("angleLen", (int)Math.Round(Norm360(-ang)), (int)Math.Round((b - a).Length)), hSnapped ? guide : sel);
                }
                Dot(a, sel); Dot(b, sel);
            }
        }
    }
}
