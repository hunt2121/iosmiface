// SPDX-License-Identifier: MIT
// Редактор циферблата: шари, полотно з вибором і перетягуванням мишею (прив'язка до центру, країв і сітки),
// масштаб, кольорові варіанти, додавання елементів, перегляд і збирання .bin. Властивості — Inspector.cs.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using BandFace.Faces;
using Microsoft.Win32;

namespace BandFace.Creator
{
    public partial class EditorView : UserControl
    {
        FaceProject project;
        FaceRenderer renderer;
        int theme, variant;
        XNode selected;
        List<LayerBox> boxes = new List<LayerBox>();
        double zoom = 1;
        bool fit = false, snap = true, syncingList;
        int grid = 1;

        // перетягування
        XNode dragLayout;
        Point dragStart, mouseStart;
        Point? dragPos;
        bool moved, guideV, guideH;

        public event Action BackRequested;
        /// <summary>«Встановити на браслет»: зібраний .bin і назва; встановлює BandFace звичним шляхом.</summary>
        public event Action<byte[], string> InstallRequested;
        public FaceProject Project => project;

        public EditorView()
        {
            InitializeComponent();
            foreach (var g in new[] { 1, 2, 4, 8 }) GridBox.Items.Add(new ComboBoxItem { Content = g.ToString(), Tag = g });
            GridBox.SelectedIndex = 0;
            ApplyTexts();
            // XML-редактор (AvalonEdit) при першому відкритті довго «прогрівається» — готуємо його заздалегідь, коли застосунок нічим не зайнятий
            Loaded += (s, e) => Dispatcher.BeginInvoke(new Action(WarmUpXmlEditor), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        }

        Window Owner => Window.GetWindow(this);

        void ApplyTexts()
        {
            BackBtn.ToolTip = S.Get("back");
            UndoBtn.ToolTip = S.Get("undo") + " (Ctrl+Z)";
            RedoBtn.ToolTip = S.Get("redo") + " (Ctrl+Y)";
            PreviewBtn.Content = S.Get("preview");
            // текст і стрілка окремо: стрілка зі шрифту значків, по центру висоти (у спільному рядку вона «стрибала» вгору)
            var fileContent = new StackPanel { Orientation = Orientation.Horizontal };
            fileContent.Children.Add(new TextBlock { Text = S.Get("fileMenu"), VerticalAlignment = VerticalAlignment.Center });
            fileContent.Children.Add(new TextBlock { Text = "\uE70D", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 10, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 1, 0, 0) });
            FileBtn.Content = fileContent;
            InstallBtn.Content = S.Get("installBand");
            VisualMode.Content = S.Get("modeVisual");
            XmlMode.Content = "XML";
            LayersTab.Content = S.Get("layers");
            ImagesTab.Content = S.Get("imagesTab");
            ImagesHint.Text = S.Get("imagesHint");
            AddBtn.Content = "+ " + S.Get("add");
            UpBtn.ToolTip = S.Get("layerUp") + " (Ctrl+])";
            DownBtn.ToolTip = S.Get("layerDown") + " (Ctrl+[)";
            DupBtn.ToolTip = S.Get("duplicate") + " (Ctrl+D)";
            DelBtn.ToolTip = S.Get("delete") + " (Delete)";
            SnapText.Text = S.Get("snap");
            GridText.Text = S.Get("grid");
            FitBtn.Content = S.Get("fit");
            LockBtn.ToolTip = S.Get(locked ? "unlockMove" : "lockMove");
            NameText.ToolTip = S.Get("faceProps");
            FaceRowTitle.Text = S.Get("face");
            FaceRowSub.Text = S.Get("faceRowSub");
            FaceRow.ToolTip = S.Get("faceProps") + " (Esc)";
        }

        // MARK: Відкриття

        public void Open(FaceProject p)
        {
            if (project != null) project.Changed -= OnChanged;
            project = p;
            p.Changed += OnChanged;
            Watch();
            renderer = new FaceRenderer(p);
            theme = 0; variant = 0; selected = null; fit = false; zoom = 1; // відкривається в 100%; «Вмістити» — кнопкою
            // новий проєкт відкривається у візуальному режимі
            xmlBase = null;
            VisualMode.IsChecked = true; XmlMode.IsChecked = false;
            XmlView.Visibility = Visibility.Collapsed; VisualView.Visibility = Visibility.Visible;
            if (p.Themes.Count == 0) p.Edit(x => x.Root.Add("Theme").Set("type", "normal").Set("name", "").Set("bgColor", "#000000"));
            RefreshAll();
            Focus();
        }

        void OnChanged()
        {
            if (project == null) return;
            if (theme >= project.Themes.Count) theme = 0;
            if (selected != null && !project.Layouts(theme).Contains(selected)) selected = null;
            if (variant >= ColorVariants.Colors(project).Count) variant = 0;
            RefreshAll();
            XmlProjectChanged();
        }

        void RefreshAll()
        {
            if (project == null) return;
            NameText.Text = project.DisplayName;
            InfoText.Text = project.Meta.Device.Title + " · " + project.Meta.Device.Width + "×" + project.Meta.Device.Height;
            UndoBtn.IsEnabled = project.CanUndo;
            RedoBtn.IsEnabled = project.CanRedo;
            RefreshScreens();
            RefreshLayers();
            if (ImagesPane.Visibility == Visibility.Visible) RefreshImages();
            RefreshSwatches();
            Redraw();
            BuildInspector();
        }

        void RefreshScreens()
        {
            syncingList = true;
            ScreenBox.Items.Clear();
            var ts = project.Themes;
            for (int i = 0; i < ts.Count; i++)
                ScreenBox.Items.Add(new ComboBoxItem { Content = ts[i].Str("type") == "AOD" ? S.Get("screenAod") : S.Get("screenMain"), Tag = i });
            ScreenBox.SelectedIndex = Math.Min(theme, ts.Count - 1);
            ScreenBox.IsEnabled = ts.Count > 1;
            syncingList = false;
        }

        void Screen_Changed(object sender, SelectionChangedEventArgs e)
        {
            if (syncingList || !(ScreenBox.SelectedItem is ComboBoxItem it)) return;
            theme = (int)it.Tag;
            selected = null;
            RefreshAll();
        }

        public void ShowTheme(int t)
        {
            theme = Math.Max(0, Math.Min(t, project.Themes.Count - 1));
            selected = null;
            RefreshAll();
        }

        // MARK: Шари

        static string Glyph(ElementKind k)
        {
            switch (k)
            {
                case ElementKind.Text: case ElementKind.Label: return "Aa";
                case ElementKind.Digits: return "12";
                case ElementKind.Image: return "▣";
                case ElementKind.Animation: return "▶";
                case ElementKind.Pointer: return "◷";
                case ElementKind.Arc: return "◔";
                case ElementKind.Line: return "▬";
                case ElementKind.Values: return "▦";
                case ElementKind.Widget: return "◫";
                case ElementKind.Slot: return "⬚";
                default: return "□";
            }
        }

        void RefreshLayers()
        {
            syncingList = true;
            LayersList.Items.Clear();
            var ls = project.Layouts(theme);
            for (int i = ls.Count - 1; i >= 0; i--)
            {
                var l = ls[i];
                var res = project.ElementOf(l);
                var kind = Elements.Of(res, project);
                var row = new Grid();
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.Children.Add(new TextBlock
                {
                    Text = Glyph(kind), FontFamily = new FontFamily("Segoe UI Symbol"), FontSize = kind == ElementKind.Text || kind == ElementKind.Label || kind == ElementKind.Digits ? 12 : 15,
                    FontWeight = FontWeights.Bold, VerticalAlignment = VerticalAlignment.Center, Foreground = (Brush)FindResource("Sub"),
                });
                var sp = new StackPanel();
                sp.Children.Add(new TextBlock { Text = Elements.Title(kind), FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis });
                var src = res?.Str("source");
                var sub = src != null ? SampleData.Title(src)
                        : kind == ElementKind.Label ? "«" + project.Meta.Gen(res?.Str("name"))?.Text + "»" : res?.Str("name") ?? "";
                var app = ElementFactory.TapApp(project, l);
                if (app != null) sub += "  ↗ " + S.App(app);
                sp.Children.Add(new TextBlock { Text = sub, FontSize = 11, Foreground = (Brush)FindResource("Sub"), TextTrimming = TextTrimming.CharacterEllipsis });
                Grid.SetColumn(sp, 1);
                row.Children.Add(sp);
                var item = new ListBoxItem { Content = row, Tag = l };
                LayersList.Items.Add(item);
                if (l == selected) LayersList.SelectedItem = item;
            }
            bool has = selected != null;
            FaceRow.Background = has ? Brushes.Transparent : (Brush)FindResource("NavSel");
            UpBtn.IsEnabled = DownBtn.IsEnabled = DupBtn.IsEnabled = DelBtn.IsEnabled = has;
            syncingList = false;
        }

        void Layers_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (syncingList) return;
            var l = (LayersList.SelectedItem as ListBoxItem)?.Tag as XNode;
            if (l == selected) return;
            Select(l);
        }

        void Select(XNode l)
        {
            selected = l;
            syncingList = true;
            LayersList.SelectedItem = LayersList.Items.Cast<ListBoxItem>().FirstOrDefault(i => i.Tag == l);
            LayersList.SelectedItem?.Let(it => LayersList.ScrollIntoView(it));
            syncingList = false;
            UpBtn.IsEnabled = DownBtn.IsEnabled = DupBtn.IsEnabled = DelBtn.IsEnabled = l != null;
            FaceRow.Background = l == null ? (Brush)FindResource("NavSel") : Brushes.Transparent;
            DrawOverlay();
            BuildInspector();
            // вкладка «Зображення» показує картинки вибраного шару — оновити після зміни вибору
            if (ImagesPane.Visibility == Visibility.Visible)
                Dispatcher.BeginInvoke(new Action(RefreshImages), System.Windows.Threading.DispatcherPriority.Background);
        }

        void MoveSelected(int delta)
        {
            if (selected == null) return;
            var ls = project.Layouts(theme);
            int i = ls.IndexOf(selected);
            if (i < 0) return;
            int t = Math.Max(0, Math.Min(ls.Count - 1, i + delta));
            if (t == i) return;
            var l = selected;
            project.Edit(p => ElementFactory.Move(p, l, theme, t));
        }

        void Up_Click(object sender, RoutedEventArgs e) => MoveSelected(1);
        void Down_Click(object sender, RoutedEventArgs e) => MoveSelected(-1);
        void Dup_Click(object sender, RoutedEventArgs e) => DuplicateSelected();
        void Del_Click(object sender, RoutedEventArgs e) => DeleteSelected();

        void DuplicateSelected()
        {
            if (selected == null) return;
            var l = selected;
            XNode copy = null;
            project.Edit(p => copy = ElementFactory.Duplicate(p, l, theme));
            if (copy != null) Select(copy);
        }

        void DeleteSelected()
        {
            if (selected == null) return;
            var l = selected;
            selected = null;
            project.Edit(p => ElementFactory.Delete(p, l, theme));
        }

        // MARK: Полотно

        double Dpi => VisualTreeHelper.GetDpi(this).DpiScaleX;

        void Workspace_SizeChanged(object sender, SizeChangedEventArgs e) { if (fit && project != null) Redraw(); }

        double FitZoom()
        {
            var dev = project.Meta.Device;
            double vw = Workspace.ViewportWidth > 0 ? Workspace.ViewportWidth : Workspace.ActualWidth;
            double vh = Workspace.ViewportHeight > 0 ? Workspace.ViewportHeight : Workspace.ActualHeight;
            if (vw <= 0 || vh <= 0) return 1;
            return Math.Max(0.4, Math.Min(6, Math.Min((vw - 40) / dev.Width, (vh - 40) / dev.Height)));
        }

        public void Redraw()
        {
            if (project == null) return;
            if (fit) zoom = FitZoom();
            var dev = project.Meta.Device;
            renderer.ColorVariant = variant;
            renderer.Overrides.Clear();
            var r = renderer.Render(theme, zoom * Dpi);
            boxes = r.Boxes;
            ImgBelow.Source = r.Image;
            ImgLayer.Source = null; ImgAbove.Source = null; ImgLayer.RenderTransform = null;
            double w = dev.Width * zoom, h = dev.Height * zoom;
            Face.Width = w; Face.Height = h;
            Overlay.Width = w; Overlay.Height = h;
            double rad = dev.Corner * zoom;
            Face.Clip = new RectangleGeometry(new Rect(0, 0, w, h), rad, rad);
            Ring.CornerRadius = new CornerRadius(rad + 3);
            if (!ZoomBox.IsKeyboardFocused) ZoomBox.Text = Math.Round(zoom * 100) + " %";
            DrawOverlay();
        }

        void SetZoom(double z) { fit = false; zoom = Math.Max(0.25, Math.Min(8, z)); Redraw(); }

        /// <summary>Масштаб числом: «150», «150%» або «150 %», Enter — застосувати, Esc — повернути.</summary>
        void ZoomBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter) { ApplyZoomText(); Workspace.Focus(); e.Handled = true; }
            else if (e.Key == Key.Escape) { ZoomBox.Text = Math.Round(zoom * 100) + " %"; Workspace.Focus(); e.Handled = true; }
        }

        void ZoomBox_LostFocus(object sender, KeyboardFocusChangedEventArgs e) => ApplyZoomText();

        void ApplyZoomText()
        {
            var t = new string(ZoomBox.Text.Where(c => char.IsDigit(c) || c == '.' || c == ',').ToArray()).Replace(',', '.');
            if (double.TryParse(t, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v) && v > 0)
                SetZoom(Math.Max(25, Math.Min(800, v)) / 100.0);
            else ZoomBox.Text = Math.Round(zoom * 100) + " %";
        }

        void FaceRow_Click(object sender, MouseButtonEventArgs e) => Select(null);
        void ZoomIn_Click(object sender, RoutedEventArgs e) => SetZoom(zoom * 1.25);
        void ZoomOut_Click(object sender, RoutedEventArgs e) => SetZoom(zoom / 1.25);
        void Fit_Click(object sender, RoutedEventArgs e) { fit = true; Redraw(); }

        void Workspace_Wheel(object sender, MouseWheelEventArgs e)
        {
            if (!Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) return;
            SetZoom(zoom * (e.Delta > 0 ? 1.1 : 1 / 1.1));
            e.Handled = true;
        }

        void Snap_Click(object sender, RoutedEventArgs e) => snap = SnapBox.IsChecked == true;
        void Grid_Changed(object sender, SelectionChangedEventArgs e) => grid = (GridBox.SelectedItem as ComboBoxItem)?.Tag as int? ?? 1;

        Rect? SelectedBox()
        {
            if (selected == null) return null;
            return boxes.FirstOrDefault(b => b.Layout == selected)?.Rect;
        }

        void DrawOverlay()
        {
            Overlay.Children.Clear();
            if (project == null) return;
            var dev = project.Meta.Device;
            var sel = (Brush)FindResource("Select");
            var b0 = SelectedBox();
            if (b0.HasValue)
            {
                var b = b0.Value;
                if (dragPos.HasValue && moved) b.Offset(dragPos.Value.X - dragStart.X, dragPos.Value.Y - dragStart.Y);
                var r = new Rect(b.X * zoom, b.Y * zoom, Math.Max(b.Width * zoom, 6), Math.Max(b.Height * zoom, 6));
                var rect = new Rectangle { Width = r.Width, Height = r.Height, Stroke = sel, StrokeThickness = 1.5, StrokeDashArray = new DoubleCollection { 4, 2 }, RadiusX = 3, RadiusY = 3 };
                Canvas.SetLeft(rect, r.X); Canvas.SetTop(rect, r.Y);
                Overlay.Children.Add(rect);
                // у дуги й лінії — свої ручки на кінцях (DrawHandles), кутові не показуємо
                bool gauge = GaugeRes(out _) != null;
                if (!gauge) foreach (var pt in new[] { r.TopLeft, r.TopRight, r.BottomLeft, r.BottomRight })
                {
                    var hnd = new Ellipse { Width = 9, Height = 9, Fill = Brushes.White, Stroke = sel, StrokeThickness = 1.5 };
                    Canvas.SetLeft(hnd, pt.X - 4.5); Canvas.SetTop(hnd, pt.Y - 4.5);
                    Overlay.Children.Add(hnd);
                }
                if (dragPos.HasValue && moved)
                {
                    var tag = new Border
                    {
                        Background = sel, CornerRadius = new CornerRadius(3), Padding = new Thickness(5, 1, 5, 1),
                        Child = new TextBlock { Text = "X " + (int)dragPos.Value.X + " · Y " + (int)dragPos.Value.Y, Foreground = Brushes.White, FontSize = 11, FontWeight = FontWeights.SemiBold },
                    };
                    Canvas.SetLeft(tag, r.X); Canvas.SetTop(tag, Math.Max(0, r.Y - 22));
                    Overlay.Children.Add(tag);
                }
            }
            DrawHandles(sel);
            var guide = (Brush)FindResource("Guide");
            if (guideV) { var ln = new Rectangle { Width = 1, Height = dev.Height * zoom, Fill = guide }; Canvas.SetLeft(ln, dev.Width * zoom / 2); Overlay.Children.Add(ln); }
            if (guideH) { var ln = new Rectangle { Width = dev.Width * zoom, Height = 1, Fill = guide }; Canvas.SetTop(ln, dev.Height * zoom / 2); Overlay.Children.Add(ln); }
        }

        XNode Hit(Point pt)
        {
            // спершу вже вибраний (щоб його легко тягнути), далі — верхній шар
            if (selected != null)
            {
                var b = boxes.FirstOrDefault(x => x.Layout == selected);
                if (b != null) { var r = b.Rect; r.Inflate(6, 6); if (r.Contains(pt)) return selected; }
            }
            for (int i = boxes.Count - 1; i >= 0; i--)
            {
                var r = boxes[i].Rect; r.Inflate(4, 4);
                if (r.Contains(pt)) return boxes[i].Layout;
            }
            return null;
        }

        Point FacePoint(MouseEventArgs e) { var p = e.GetPosition(Face); return new Point(p.X / zoom, p.Y / zoom); }

        /// <summary>Замок: елементи не пересуваються; клік лише вибирає, перетягування прокручує полотно</summary>
        bool locked;
        Point? panFrom;
        double panH, panV;

        void Lock_Click(object sender, RoutedEventArgs e)
        {
            locked = LockBtn.IsChecked == true;
            LockBtn.Content = locked ? "\uE72E" : "\uE785";
            LockBtn.ToolTip = S.Get(locked ? "unlockMove" : "lockMove");
        }

        void Stage_Down(object sender, MouseButtonEventArgs e)
        {
            if (project == null) return;
            Focus();
            var pt = FacePoint(e);
            if (locked)
            {
                var hit = Hit(pt);
                if (hit != selected) Select(hit);
                panFrom = e.GetPosition(Workspace);
                panH = Workspace.HorizontalOffset; panV = Workspace.VerticalOffset;
                StageHost.CaptureMouse();
                StageHost.Cursor = Cursors.SizeAll;
                e.Handled = true;
                return;
            }
            if (StartHandleDrag(pt)) { StageHost.CaptureMouse(); e.Handled = true; return; }
            var l = Hit(pt);
            if (l == null) { if (selected != null) Select(null); return; }
            if (l != selected) Select(l);
            dragLayout = l;
            dragStart = new Point(l.Int("x"), l.Int("y"));
            mouseStart = pt;
            moved = false;
            StageHost.CaptureMouse();
            e.Handled = true;
        }

        void Stage_Move(object sender, MouseEventArgs e)
        {
            if (panFrom.HasValue)
            {
                var p = e.GetPosition(Workspace);
                Workspace.ScrollToHorizontalOffset(panH - (p.X - panFrom.Value.X));
                Workspace.ScrollToVerticalOffset(panV - (p.Y - panFrom.Value.Y));
                return;
            }
            if (handle != null) { MoveHandle(FacePoint(e)); return; }
            if (dragLayout == null) return;
            var pt = FacePoint(e);
            double dx = pt.X - mouseStart.X, dy = pt.Y - mouseStart.Y;
            if (!moved)
            {
                if ((Math.Abs(dx) + Math.Abs(dy)) * zoom < 3) return;
                moved = true;
                MakeCache(dragLayout);
            }
            var dev = project.Meta.Device;
            double W = dev.Width, H = dev.Height;
            double x = dragStart.X + dx, y = dragStart.Y + dy;
            double g = Math.Max(1, grid);
            x = Math.Round(x / g) * g; y = Math.Round(y / g) * g;
            guideV = guideH = false;
            var bx = boxes.FirstOrDefault(b => b.Layout == dragLayout);
            if (snap && bx != null && !Keyboard.Modifiers.HasFlag(ModifierKeys.Alt))
            {
                var b = bx.Rect;
                double offX = b.X - dragStart.X, offY = b.Y - dragStart.Y;
                double cx = x + offX + b.Width / 2, cy = y + offY + b.Height / 2;
                if (Math.Abs(cx - W / 2) < 4) { x = W / 2 - b.Width / 2 - offX; guideV = true; }
                if (Math.Abs(cy - H / 2) < 4) { y = H / 2 - b.Height / 2 - offY; guideH = true; }
                if (Math.Abs(x + offX) < 4) x = -offX;
                if (Math.Abs(y + offY) < 4) y = -offY;
                if (Math.Abs(x + offX + b.Width - W) < 4) x = W - b.Width - offX;
                if (Math.Abs(y + offY + b.Height - H) < 4) y = H - b.Height - offY;
            }
            dragPos = new Point(Math.Round(x), Math.Round(y));
            ImgLayer.RenderTransform = new TranslateTransform((dragPos.Value.X - dragStart.X) * zoom, (dragPos.Value.Y - dragStart.Y) * zoom);
            DrawOverlay();
        }

        void Stage_Up(object sender, MouseButtonEventArgs e)
        {
            if (panFrom.HasValue) { panFrom = null; StageHost.ReleaseMouseCapture(); StageHost.Cursor = null; return; }
            if (handle != null) { StageHost.ReleaseMouseCapture(); EndHandleDrag(); return; }
            if (dragLayout == null) return;
            StageHost.ReleaseMouseCapture();
            var l = dragLayout;
            var p = dragPos;
            bool wasMoved = moved;
            dragLayout = null; dragPos = null; moved = false; guideV = guideH = false;
            if (wasMoved && p.HasValue && (p.Value.X != l.Int("x") || p.Value.Y != l.Int("y")))
                project.Edit(x => l.Set("x", (int)p.Value.X).Set("y", (int)p.Value.Y));
            else Redraw();
        }

        /// <summary>Три шари для перетягування: під вибраним, сам шар і над ним (далі лише зсувається картинка шару)</summary>
        void MakeCache(XNode l)
        {
            int i = project.Layouts(theme).IndexOf(l);
            if (i < 0) return;
            double s = zoom * Dpi;
            renderer.Overrides.Clear();
            ImgBelow.Source = renderer.Render(theme, s, j => j < i).Image;
            ImgLayer.Source = renderer.Render(theme, s, j => j == i, false).Image;
            ImgAbove.Source = renderer.Render(theme, s, j => j > i, false).Image;
        }

        void Nudge(int dx, int dy)
        {
            if (selected == null || locked) return;
            var l = selected;
            int step = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) ? 10 : Math.Max(1, grid);
            project.Edit(p => l.Set("x", l.Int("x") + dx * step).Set("y", l.Int("y") + dy * step));
        }

        /// <summary>Клавіші редактора (викликає вікно, коли фокус не в полі введення)</summary>
        public bool HandleKey(KeyEventArgs e)
        {
            // у режимі XML клавіші належать текстовому редактору
            if (project == null || XmlShown) return false;
            bool ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control), shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
            switch (e.Key)
            {
                case Key.Z when ctrl && shift: project.Redo(); return true;
                case Key.Z when ctrl: project.Undo(); return true;
                case Key.Y when ctrl: project.Redo(); return true;
                case Key.D when ctrl: DuplicateSelected(); return true;
                case Key.S when ctrl: Export_Click(null, null); return true;
                case Key.OemCloseBrackets when ctrl: MoveSelected(1); return true;
                case Key.OemOpenBrackets when ctrl: MoveSelected(-1); return true;
                case Key.Delete: if (selected == null) return false; DeleteSelected(); return true;
                case Key.Escape: Select(null); return true;
                case Key.Left: Nudge(-1, 0); return selected != null;
                case Key.Right: Nudge(1, 0); return selected != null;
                case Key.Up: Nudge(0, -1); return selected != null;
                case Key.Down: Nudge(0, 1); return selected != null;
            }
            return false;
        }

        // MARK: Кольорові варіанти на полотні

        void RefreshSwatches()
        {
            Swatches.Children.Clear();
            var cols = ColorVariants.Colors(project);
            if (cols.Count < 2) return;
            Swatches.Children.Add(new TextBlock { Text = S.Get("colorShown"), FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
            for (int i = 0; i < cols.Count; i++)
            {
                int idx = i;
                var b = new Border
                {
                    Width = 22, Height = 22, CornerRadius = new CornerRadius(11), Background = Imaging.Brush(cols[i]), Margin = new Thickness(0, 0, 6, 0),
                    BorderThickness = new Thickness(2), BorderBrush = i == variant ? (Brush)FindResource("Accent") : (Brush)FindResource("CardBorder"),
                    Cursor = Cursors.Hand, ToolTip = i == 0 ? S.Get("baseColor") : cols[i],
                };
                b.MouseLeftButtonUp += (s, e) => { variant = idx; RefreshSwatches(); Redraw(); };
                Swatches.Children.Add(b);
            }
        }

        // MARK: Додавання елементів

        /// <summary>Галерея «Додати елемент»: що додати, потім (для чисел і шкал) — що показувати</summary>
        void Add_Click(object sender, RoutedEventArgs e)
        {
            if (project == null) return;
            var c = AddGallery.Pick(Owner);
            if (c == null) return;
            Center(out var cx, out var cy);
            switch (c.Kind)
            {
                case "digits": AddWithSource(ElementKind.Digits, c.Source); break;
                case "values": AddWithSource(ElementKind.Values, c.Source); break;
                case "pointer": AddWithSource(ElementKind.Pointer, c.Source); break;
                case "arc": AddWithSource(ElementKind.Arc, c.Source); break;
                case "line": AddWithSource(ElementKind.Line, c.Source); break;
                case "clock": AddAndSelect(p => ElementFactory.AddAnalogClock(p, theme, cx, cy)); break;
                case "image": AddImage(); break;
                case "animation": AddAnimation(); break;
                case "background": AddBackground(); break;
            }
        }

        /// <summary>Стани редактора для знімків екрана в CI</summary>
        public Window DemoMode(string mode)
        {
            int w = project.Meta.Device.Width;
            project.Edit(p =>
            {
                ElementFactory.AddArc(p, "healthStepProgress", new Generator(GenKind.Arc) { Color = "#30B455", BgColor = "#3A3A3C", Radius = 70, Width = 12, Start = 225, Range = 270 }, theme, w / 2, 400);
                ElementFactory.AddLine(p, "systemStatusBattery", new Generator(GenKind.Line) { Color = "#0A6CF0", BgColor = "#3A3A3C", Width = 8, Length = 120, Angle = -45 }, theme, w / 2, 400);
            });
            var ls = project.Layouts(theme);
            XNode Find(ElementKind k) => ls.LastOrDefault(l => Elements.Of(project.ElementOf(l), project) == k);
            switch (mode)
            {
                case "arc": Select(Find(ElementKind.Arc)); break;
                case "line": Select(Find(ElementKind.Line)); break;
                case "digits": Select(Find(ElementKind.Digits)); break;
                case "images": ShowImagesTab(true); break;
                case "xml": Dispatcher.BeginInvoke(new Action(() => SetXmlMode(true)), System.Windows.Threading.DispatcherPriority.Loaded); break;
                case "gallery": return AddGallery.Demo(Owner, 1);
                case "gallery2": return AddGallery.Demo(Owner, 2);
            }
            return null;
        }

        void Center(out int cx, out int cy) { cx = project.Meta.Device.Width / 2; cy = project.Meta.Device.Height / 2; }

        void AddAndSelect(Action<FaceProject> add)
        {
            project.Edit(add);
            var ls = project.Layouts(theme);
            if (ls.Count > 0) Select(ls[ls.Count - 1]);
        }

        void AddWithSource(ElementKind k, string src)
        {
            if (src == null) return;
            Center(out var cx, out var cy);
            switch (k)
            {
                case ElementKind.Digits:
                {
                    // 10 картинок 0–9 (за назвою файла)
                    var imgs = PickImages(true, 400);
                    if (imgs.Count == 0) break;
                    if (imgs.Count != 10 && MessageBox.Show(Owner, S.Get("digitsCountAsk", imgs.Count), S.Get("kind_digits"), MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) break;
                    AddAndSelect(p => ElementFactory.AddDigitImages(p, src, imgs, theme, cx, cy));
                    break;
                }
                case ElementKind.Pointer:
                    AddAndSelect(p => ElementFactory.AddPointer(p, src, new Generator(GenKind.Pointer) { Color = "#FFFFFF", Width = 6, Length = 80 }, theme, cx, cy));
                    break;
                case ElementKind.Arc:
                    AddAndSelect(p => ElementFactory.AddArc(p, src, new Generator(GenKind.Arc) { Color = "#30B455", BgColor = "#3A3A3C", Radius = 60, Width = 10 }, theme, cx, cy));
                    break;
                case ElementKind.Line:
                    AddAndSelect(p => ElementFactory.AddLine(p, src, new Generator(GenKind.Line) { Color = "#0A6CF0", BgColor = "#3A3A3C", Width = 8, Length = 140 }, theme, cx, cy));
                    break;
                case ElementKind.Values:
                {
                    var imgs = PickImages(true, 200);
                    if (imgs.Count > 0) AddAndSelect(p => ElementFactory.AddValues(p, src, imgs, theme, cx, cy));
                    break;
                }
            }
        }

        public const string ImageFilter = "*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.ico";

        /// <summary>Вибір картинок (кілька — за назвою файла, як кадри); null у списку немає</summary>
        public List<RgbaImage> PickImages(bool many, double maxSide)
        {
            var dlg = new OpenFileDialog { Multiselect = many, Filter = S.Get("images") + "|" + ImageFilter };
            var o = new List<RgbaImage>();
            if (dlg.ShowDialog(Owner) != true) return o;
            foreach (var f in dlg.FileNames.OrderBy(x => x, StringComparer.CurrentCultureIgnoreCase))
            {
                try { o.Add(Imaging.Load(f, maxSide)); }
                catch (Exception ex) { MessageBox.Show(Owner, S.Get("imageFail", System.IO.Path.GetFileName(f), ex.Message), "BandFace"); }
            }
            return o;
        }

        /// <summary>Напис картинкою: одразу по центру, рядок і шрифт — у властивостях
        /// (текст, який малює сам браслет, не підтримується — на Smart Band 10 не перевірений)</summary>
        void AddImage()
        {
            var dev = project.Meta.Device;
            var imgs = PickImages(false, Math.Max(dev.Width, dev.Height));
            if (imgs.Count == 0) return;
            Center(out var cx, out var cy);
            AddAndSelect(p => ElementFactory.AddImage(p, imgs[0], theme, cx, cy));
        }

        void AddAnimation()
        {
            var imgs = PickImages(true, 1000);
            if (imgs.Count == 0) return;
            // кадри одного розміру: як перший, не ширше 200
            var f0 = Imaging.Fit(imgs[0], 200);
            var frames = imgs.Select(i => Imaging.Contain(i, f0.W, f0.H)).ToList();
            Center(out var cx, out var cy);
            AddAndSelect(p => ElementFactory.AddAnimation(p, frames, 100, theme, cx, cy));
        }

        void AddBackground()
        {
            var imgs = PickImages(false, 2000);
            if (imgs.Count == 0) return;
            project.Edit(p => ElementFactory.AddBackground(p, imgs[0], theme));
        }

        // MARK: Верхня панель

        void Back_Click(object sender, RoutedEventArgs e) => BackRequested?.Invoke();
        void Undo_Click(object sender, RoutedEventArgs e) => project?.Undo();
        void Redo_Click(object sender, RoutedEventArgs e) => project?.Redo();
        void Name_Click(object sender, MouseButtonEventArgs e) { Select(null); focusName = true; BuildInspector(); }

        void Preview_Click(object sender, RoutedEventArgs e)
        {
            if (project == null) return;
            new PreviewWindow(project, theme, variant) { Owner = Owner }.Show();
        }

        void Export_Click(object sender, RoutedEventArgs e)
        {
            if (project != null) Actions.ExportBin(Owner, project);
        }

        void Install_Click(object sender, RoutedEventArgs e)
        {
            if (project == null) return;
            var bin = Actions.Build(Owner, project);
            if (bin != null) InstallRequested?.Invoke(bin, project.DisplayName);
        }
    }

    static class LetExt
    {
        public static void Let<T>(this T v, Action<T> f) where T : class { if (v != null) f(v); }
    }
}
