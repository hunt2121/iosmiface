// SPDX-License-Identifier: MIT
// Вкладка «Зображення»: усі картинки проєкту з мініатюрами; заміна по одній (кнопкою або перетягнувши PNG на рядок),
// «Показати в теці», «Зберегти як PNG…». Ті самі дії — в інспекторі вибраного елемента.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BandFace.Faces;
using Microsoft.Win32;

namespace BandFace.Creator
{
    public partial class EditorView
    {
        sealed class ImageRef { public string Src; public XNode Owner; public XNode Node; }

        /// <summary>Усі картинки, на які посилаються ресурси (для масиву кадрів — кожен кадр окремо)</summary>
        List<ImageRef> AllImages()
        {
            var o = new List<ImageRef>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            void Walk(XNode owner, XNode n)
            {
                var src = n.Str("src");
                if (src != null && project.File(src) != null && seen.Add(MemoryStorage.Normalize(src))) o.Add(new ImageRef { Src = src, Owner = owner, Node = n });
                foreach (var c in n.Elements) Walk(owner, c);
            }
            foreach (var r in project.Resources.Elements) Walk(r, r);
            return o;
        }

        /// <summary>Картинки ресурсу вибраного елемента (разом із фоном дуги/лінії, кадрами цифр тощо)</summary>
        List<ImageRef> ImagesOf(XNode res)
        {
            var names = new HashSet<string>();
            void Refs(XNode n)
            {
                foreach (var a in n.Attrs) { var v = n.Str(a.Key); if (v != null && v.StartsWith("@")) names.Add(v.Substring(1)); }
                foreach (var c in n.Elements) Refs(c);
            }
            if (res != null) { names.Add(res.Str("name") ?? ""); Refs(res); }
            return AllImages().Where(i => names.Contains(i.Owner.Str("name") ?? "")).ToList();
        }

        void LayersTab_Click(object sender, RoutedEventArgs e) => ShowImagesTab(false);
        void ImagesTab_Click(object sender, RoutedEventArgs e) => ShowImagesTab(true);

        void ShowImagesTab(bool images)
        {
            LayersTab.IsChecked = !images; ImagesTab.IsChecked = images;
            var v = images ? Visibility.Collapsed : Visibility.Visible;
            LayersList.Visibility = FaceRow.Visibility = FaceRowLine.Visibility = LayerButtons.Visibility = v;
            ImagesPane.Visibility = images ? Visibility.Visible : Visibility.Collapsed;
            if (images) RefreshImages();
        }

        void RefreshImages()
        {
            if (project == null) return;
            syncingList = true;
            ImagesList.Items.Clear();
            foreach (var im in AllImages())
            {
                var data = project.File(im.Src);
                var bmp = project.Images.Get(MemoryStorage.Normalize(im.Src), () => Imaging.Decode(data)?.ToBitmap());
                var row = new Grid { Background = Brushes.Transparent };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(48) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                // мініатюра на «шаховому» фоні — видно прозорість
                var thumb = new Border { Width = 40, Height = 40, CornerRadius = new CornerRadius(4), Background = Checker(), ClipToBounds = true,
                    Child = new Image { Source = bmp, Stretch = Stretch.Uniform, Margin = new Thickness(2) } };
                RenderOptions.SetBitmapScalingMode(thumb.Child, BitmapScalingMode.HighQuality);
                row.Children.Add(thumb);
                var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 4, 0) };
                sp.Children.Add(new TextBlock { Text = im.Src, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = im.Src });
                sp.Children.Add(new TextBlock
                {
                    Text = (bmp != null ? bmp.PixelWidth + "×" + bmp.PixelHeight + " · " : "") + Math.Max(1, (data.Length + 512) / 1024) + " KB · " + (im.Owner.Str("name") ?? im.Owner.Tag),
                    FontSize = 11, Foreground = (Brush)FindResource("Sub"), TextTrimming = TextTrimming.CharacterEllipsis,
                });
                Grid.SetColumn(sp, 1);
                row.Children.Add(sp);
                var more = Ui.Icon("", S.Get("more"), () => { });
                more.Click += (s, e) => ImageMenu(im, (Button)s).IsOpen = true;
                Grid.SetColumn(more, 2);
                row.Children.Add(more);
                var item = new ListBoxItem { Content = row, Tag = im, AllowDrop = true, ToolTip = S.Get("imageRowTip") };
                item.ContextMenu = ImageMenu(im, item);
                item.MouseDoubleClick += (s, e) => ReplaceImageFile(im);
                item.DragEnter += ImageDragOver; item.DragOver += ImageDragOver;
                item.Drop += (s, e) =>
                {
                    var f = DroppedImage(e);
                    if (f != null) { ReplaceImageFile(im, f); e.Handled = true; }
                };
                ImagesList.Items.Add(item);
            }
            if (ImagesList.Items.Count == 0)
                ImagesList.Items.Add(new ListBoxItem { Content = Ui.Note(S.Get("noImages")), IsEnabled = false });
            syncingList = false;
        }

        static Brush checker;
        static Brush Checker()
        {
            if (checker != null) return checker;
            var g = new DrawingGroup();
            g.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(0x5A, 0x5A, 0x5A)), null, new RectangleGeometry(new Rect(0, 0, 12, 12))));
            g.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(0x46, 0x46, 0x46)), null, new GeometryGroup { Children = { new RectangleGeometry(new Rect(0, 0, 6, 6)), new RectangleGeometry(new Rect(6, 6, 6, 6)) } }));
            var b = new DrawingBrush(g) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 12, 12), ViewportUnits = BrushMappingMode.Absolute };
            b.Freeze();
            return checker = b;
        }

        ContextMenu ImageMenu(ImageRef im, FrameworkElement target)
        {
            var menu = new ContextMenu { PlacementTarget = target, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
            void Item(string t, string glyph, Action a)
            {
                var m = new MenuItem { Header = t, Icon = new TextBlock { Text = glyph, FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 14 } };
                m.Click += (s, e) => a();
                menu.Items.Add(m);
            }
            Item(S.Get("replaceImage") + "…", "", () => ReplaceImageFile(im));
            Item(S.Get("showInFolderShort"), "", () => ShowImageInFolder(im.Src));
            Item(S.Get("savePng"), "", () => SaveImagePng(im.Src));
            return menu;
        }

        /// <summary>Клік по картинці — вибрати шар, що її показує</summary>
        void Images_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (syncingList || !((ImagesList.SelectedItem as ListBoxItem)?.Tag is ImageRef im)) return;
            var l = project.Layouts(theme).LastOrDefault(x => ImagesOf(project.ElementOf(x)).Any(i => i.Src == im.Src));
            if (l != null && l != selected) Select(l);
        }

        static readonly string[] ImageExt = { ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff" };

        static string DroppedImage(DragEventArgs e)
        {
            if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return null;
            var f = (e.Data.GetData(DataFormats.FileDrop) as string[])?.FirstOrDefault();
            return f != null && ImageExt.Contains(Path.GetExtension(f).ToLowerInvariant()) ? f : null;
        }

        void ImageDragOver(object sender, DragEventArgs e)
        {
            e.Effects = DroppedImage(e) != null ? DragDropEffects.Copy : DragDropEffects.None;
            e.Handled = true;
        }

        /// <summary>Замінити одну картинку; інший розмір — запитати, чи підігнати під старий</summary>
        void ReplaceImageFile(ImageRef im, string path = null)
        {
            if (path == null)
            {
                var dlg = new OpenFileDialog { Filter = S.Get("images") + "|" + ImageFilter };
                if (dlg.ShowDialog(Owner) != true) return;
                path = dlg.FileName;
            }
            RgbaImage img;
            try { img = Imaging.Load(path, 2000); }
            catch (Exception ex) { MessageBox.Show(Owner, S.Get("imageFail", Path.GetFileName(path), ex.Message), "BandFace"); return; }
            var old = Imaging.Decode(project.File(im.Src));
            if (old != null && (old.W != img.W || old.H != img.H))
            {
                var r = MessageBox.Show(Owner, S.Get("imageSizeAsk", img.W, img.H, old.W, old.H), "BandFace", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
                if (r == MessageBoxResult.Cancel) return;
                if (r == MessageBoxResult.Yes) img = Imaging.Contain(img, old.W, old.H);
            }
            var owner = im.Owner;
            var src = im.Src;
            project.Edit(p =>
            {
                p.SetFile(src, img.Png());
                // своя картинка — параметри малювання цього ресурсу більше не діють
                p.Meta.Generators.Remove(owner.Str("name") ?? "");
                ColorVariants.Refresh(p, owner);
            });
        }

        string DiskPath(string src) => Path.Combine(project.Folder, "files", MemoryStorage.Normalize(src).Replace('/', Path.DirectorySeparatorChar));

        void ShowImageInFolder(string src)
        {
            var f = DiskPath(src);
            try { Process.Start("explorer.exe", File.Exists(f) ? "/select,\"" + f + "\"" : "\"" + project.Folder + "\""); } catch (Exception) { }
        }

        void SaveImagePng(string src)
        {
            var img = Imaging.Decode(project.File(src));
            if (img == null) return;
            var dlg = new SaveFileDialog { Filter = "PNG|*.png", FileName = Path.GetFileNameWithoutExtension(src) + ".png" };
            if (dlg.ShowDialog(Owner) != true) return;
            try
            {
                var enc = new PngBitmapEncoder();
                enc.Frames.Add(BitmapFrame.Create(img.ToBitmap()));
                using (var fs = File.Create(dlg.FileName)) enc.Save(fs);
            }
            catch (Exception ex) { MessageBox.Show(Owner, ex.Message, "BandFace"); }
        }

        /// <summary>Блок «Зображення» в інспекторі будь-якого елемента: усі його картинки мініатюрами
        /// (клік — замінити, перетягування PNG — замінити), «Відкрити теку», «Намалювати шрифтом…»</summary>
        void BuildImageActions(XNode res)
        {
            var list = ImagesOf(res);
            var kind = Elements.Of(res, project);
            // шрифтом малюються лише текстові елементи: числа, написи, значки за значенням (дні тижня, місяці, AM/PM);
            // фон, картинки, стрілки, шкали, анімації — лише свої картинки
            bool canFont = ElementFactory.SlotCount(project, res) > 0 &&
                           (kind == ElementKind.Digits || kind == ElementKind.Label || kind == ElementKind.Values);
            if (list.Count == 0 && !canFont) return;
            Add(Ui.Header(S.Get("imagesTab") + (list.Count > 1 ? " · " + list.Count : "")));
            if (list.Count > 0)
            {
                var wrap = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
                foreach (var im in list)
                {
                    var data = project.File(im.Src);
                    var bmp = project.Images.Get(MemoryStorage.Normalize(im.Src), () => Imaging.Decode(data)?.ToBitmap());
                    var cell = new Border
                    {
                        Width = 52, Height = 52, Margin = new Thickness(0, 0, 6, 6), CornerRadius = new CornerRadius(6), Background = Checker(),
                        Cursor = Cursors.Hand, AllowDrop = true, ClipToBounds = true,
                        ToolTip = im.Src + (bmp != null ? "\n" + bmp.PixelWidth + "×" + bmp.PixelHeight : "") + "\n" + S.Get("imageRowTip"),
                        Child = new Image { Source = bmp, Stretch = Stretch.Uniform, Margin = new Thickness(3) },
                    };
                    RenderOptions.SetBitmapScalingMode(cell.Child, BitmapScalingMode.HighQuality);
                    var r = im;
                    cell.MouseLeftButtonUp += (s, e) => { var m = ImageMenu(r, cell); m.IsOpen = true; };
                    cell.DragEnter += ImageDragOver; cell.DragOver += ImageDragOver;
                    cell.Drop += (s, e) => { var f = DroppedImage(e); if (f != null) { ReplaceImageFile(r, f); e.Handled = true; } };
                    wrap.Children.Add(cell);
                }
                Add(wrap);
                Add(Ui.Note(S.Get("elementImagesHint")));
            }
            var acts = new System.Windows.Controls.Primitives.UniformGrid { Columns = canFont && list.Count > 0 ? 2 : 1, Margin = new Thickness(0, 0, 0, 10) };
            if (list.Count > 0)
            {
                var open = new Button { Content = S.Get("openImagesFolder"), Style = (Style)FindResource("Btn"), Margin = new Thickness(0, 0, canFont ? 4 : 0, 0) };
                open.Click += (s, e) => ShowImageInFolder(list[0].Src);
                acts.Children.Add(open);
            }
            if (canFont)
            {
                var font = new Button { Content = S.Get("fontArtButton"), Style = (Style)FindResource(list.Count == 0 ? "PrimaryBtn" : "Btn"), Margin = new Thickness(list.Count > 0 ? 4 : 0, 0, 0, 0) };
                font.Click += (s, e) => FontArtWindow.Show(Owner, project, res);
                acts.Children.Add(font);
            }
            Add(acts);
        }
    }
}
