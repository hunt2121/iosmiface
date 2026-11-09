// SPDX-License-Identifier: MIT
// Інспектор віджета і слота (макет погоджено 9 листопада).

using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BandFace.Faces;

namespace BandFace.Creator
{
    public partial class EditorView
    {
        /// <summary>Віджет слота, відкритий для налаштування (інакше — список віджетів слота)</summary>
        XNode slotWidget;

        /// <summary>Мініатюра ресурсу (як він виглядає на циферблаті) на чорному тлі</summary>
        FrameworkElement Thumb(XNode res, double w = 54, double h = 40)
        {
            var host = new Border { Width = w, Height = h, CornerRadius = new CornerRadius(6), Background = Brushes.Black, ClipToBounds = true };
            try
            {
                var r = new FaceRenderer(project) { ColorVariant = variant };
                var box = r.Draw(res, new Point(0, 0), null, 0);
                if (box.HasValue && box.Value.Width > 0 && box.Value.Height > 0)
                {
                    var b = box.Value;
                    int bw = Math.Max(1, (int)Math.Ceiling(b.Width)), bh = Math.Max(1, (int)Math.Ceiling(b.Height));
                    var img = Imaging.Render(bw, bh, dc => r.Draw(res, new Point(-b.X, -b.Y), dc, 0)).ToBitmap();
                    var im = new Image { Source = img, Stretch = Stretch.Uniform, Margin = new Thickness(3), StretchDirection = StretchDirection.Both };
                    RenderOptions.SetBitmapScalingMode(im, BitmapScalingMode.HighQuality);
                    host.Child = im;
                }
            }
            catch (Exception) { }
            return host;
        }

        /// <summary>Рядок-картка: мініатюра, назва, підпис, меню ⋮; клік — дія</summary>
        FrameworkElement Card(XNode res, string title, string sub, bool selectedCard, Action click, Action<ContextMenu> menu, string badge = null)
        {
            var b = new Border { CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(selectedCard ? 2 : 1), Padding = new Thickness(10, 6, 6, 6), Margin = new Thickness(0, 0, 0, 8), Cursor = click != null ? Cursors.Hand : null };
            b.SetResourceReference(Border.BorderBrushProperty, selectedCard ? "Accent" : "CardBorder");
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.Children.Add(Thumb(res));
            var sp = new StackPanel { Margin = new Thickness(12, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
            var tl = new StackPanel { Orientation = Orientation.Horizontal };
            tl.Children.Add(new TextBlock { Text = title, FontSize = 14, TextTrimming = TextTrimming.CharacterEllipsis });
            if (badge != null)
            {
                var bd = new Border { CornerRadius = new CornerRadius(9), BorderThickness = new Thickness(1), Padding = new Thickness(7, 0, 7, 1), Margin = new Thickness(6, 1, 0, 0), VerticalAlignment = VerticalAlignment.Center };
                bd.SetResourceReference(Border.BorderBrushProperty, "Accent");
                var bt = new TextBlock { Text = badge, FontSize = 11 };
                bt.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
                bd.Child = bt;
                tl.Children.Add(bd);
            }
            sp.Children.Add(tl);
            var st = new TextBlock { Text = sub, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis };
            st.SetResourceReference(TextBlock.ForegroundProperty, "Sub");
            sp.Children.Add(st);
            Grid.SetColumn(sp, 1);
            g.Children.Add(sp);
            if (menu != null)
            {
                var more = Ui.Icon("", S.Get("more"), () => { });
                more.Click += (s, e) =>
                {
                    var cm = new ContextMenu();
                    menu(cm);
                    Ui.MenuBelow(cm, more, true);
                    e.Handled = true;
                };
                Grid.SetColumn(more, 2);
                g.Children.Add(more);
            }
            b.Child = g;
            if (click != null) b.MouseLeftButtonUp += (s, e) => click();
            return b;
        }

        string TapTitle(string app) => string.IsNullOrEmpty(app) ? S.Get("tapNone") : S.App(app);

        string ItemTitle(XNode res)
        {
            if (res == null) return "?";
            var kind = Elements.Of(res, project);
            if (kind == ElementKind.Widget && WidgetSlots.IsUserWidget(project, res)) return res.Str("widgetName") ?? Elements.Title(kind);
            return Elements.Title(kind);
        }

        string ItemSub(XNode res)
        {
            var src = res?.Str("source");
            if (src != null) return SampleData.Title(src);
            if (res != null && Elements.Of(res, project) == ElementKind.Label) return "«" + project.Meta.Gen(res.Str("name"))?.Text + "»";
            return res?.Str("name") ?? "";
        }

        /// <summary>Налаштування віджета. origin — де стоїть віджет (для «Додати у віджет» і «Вийняти»)</summary>
        void WidgetSection(XNode w, Point origin, XNode ownLayout)
        {
            int t0 = theme;
            Add(Ui.Header(S.Get("elWidget")));
            var name = new TextBox { Text = w.Str("widgetName") ?? "", VerticalContentAlignment = VerticalAlignment.Center, Height = 32 };
            Action commitName = () => { var v = name.Text.Trim(); if (v.Length > 0 && v != w.Str("widgetName")) EditRes(() => w.Set("widgetName", v)); };
            name.LostFocus += (s, e) => commitName();
            name.KeyDown += (s, e) => { if (e.Key == Key.Enter) commitName(); };
            Add(Ui.Row(S.Get("wName"), name, 220));
            var apps = new List<KeyValuePair<string, string>> { P("", S.Get("tapNone")) };
            apps.AddRange(ElementFactory.Apps.Select(a => P(a, S.App(a))).OrderBy(x => x.Value, StringComparer.CurrentCultureIgnoreCase));
            Add(Ui.Row(S.Get("tap"), Ui.Combo(apps, w.Str("jumpApp") ?? "", a => EditRes(() => WidgetSlots.SetTap(w, a))), 220));

            Add(Ui.Header(S.Get("wLayout")));
            var arr = WidgetSlots.Arrange(w);
            Add(Ui.Chips(S.Get("wArrange"), new[] { P("row", S.Get("wRow")), P("column", S.Get("wColumn")), P("free", S.Get("wFree")) }, arr,
                v => project.Edit(p => WidgetSlots.SetLayout(p, w, v, WidgetSlots.Align(w), Math.Max(WidgetSlots.Gap(w), v == "free" ? 0 : 4), ownLayout))));
            if (arr != "free")
            {
                Add(Ui.Chips(S.Get("wAlign"), new[] { P("start", S.Get("wLeft")), P("center", S.Get("wCenter")), P("end", S.Get("wRight")) }, WidgetSlots.Align(w),
                    v => project.Edit(p => WidgetSlots.SetLayout(p, w, arr, v, WidgetSlots.Gap(w), ownLayout))));
                Add(Ui.Slider(S.Get("wGap") + ", px", WidgetSlots.Gap(w), 0, 40, 1,
                    v => { int g = (int)Math.Round(v); if (g != WidgetSlots.Gap(w)) project.Edit(p => WidgetSlots.SetLayout(p, w, arr, WidgetSlots.Align(w), g, ownLayout)); }));
            }

            var items = w.All("Item");
            Add(Ui.Header(S.Get("wContent") + " · " + items.Count));
            for (int i = 0; i < items.Count; i++)
            {
                int idx = i;
                var child = project.ResourceRef(items[i].Str("ref"));
                Add(Card(child, ItemTitle(child), ItemSub(child), false, null, cm =>
                {
                    if (idx > 0) Ui.MenuAdd(cm, S.Get("moveUp"), "", () => EditRes(() => WidgetSlots.MoveItem(w, idx, -1)));
                    if (idx < items.Count - 1) Ui.MenuAdd(cm, S.Get("moveDown"), "", () => EditRes(() => WidgetSlots.MoveItem(w, idx, 1)));
                    Ui.MenuAdd(cm, S.Get("wTakeOut"), "", () => project.Edit(p => WidgetSlots.TakeOut(p, w, idx, origin, t0, ownLayout)));
                }));
            }
            if (items.Count == 0) Add(Ui.Note(S.Get("wEmpty")));
            var row = new System.Windows.Controls.Primitives.UniformGrid { Columns = ownLayout != null ? 2 : 1, Margin = new Thickness(0, 0, 0, 8) };
            var addBtn = new Button { Content = "+ " + S.Get("wAddTo"), Style = (Style)FindResource("Btn"), Margin = new Thickness(0, 0, ownLayout != null ? 4 : 0, 0) };
            addBtn.Click += (s, e) =>
            {
                var cm = new ContextMenu();
                var cands = project.Layouts(t0).Where(l => l != ownLayout && !AodDim.Is(project, l, t0)
                    && project.ElementOf(l) != w && Elements.Of(project.ElementOf(l), project) != ElementKind.Slot).Reverse().ToList();
                if (cands.Count == 0) Ui.MenuAdd(cm, S.Get("wNoLayers"), "", () => { }).IsEnabled = false;
                foreach (var l in cands)
                {
                    var res = project.ElementOf(l);
                    var lay = l;
                    Ui.MenuAdd(cm, ItemTitle(res) + " — " + ItemSub(res), "", () => project.Edit(p => WidgetSlots.AddToWidget(p, w, origin, lay, t0, ownLayout)));
                }
                Ui.MenuBelow(cm, addBtn);
            };
            row.Children.Add(addBtn);
            if (ownLayout != null)
            {
                var ug = new Button { Content = S.Get("wUngroup"), Style = (Style)FindResource("Btn"), Margin = new Thickness(4, 0, 0, 0) };
                ug.Click += (s, e) => { selected = null; project.Edit(p => WidgetSlots.Ungroup(p, ownLayout, t0)); };
                row.Children.Add(ug);
            }
            Add(row);
            Add(Ui.Note(S.Get("wHint")));
        }

        /// <summary>Налаштування слота: список віджетів на вибір (або відкритий віджет слота)</summary>
        void SlotSection(XNode slot, XNode layout)
        {
            var ws = WidgetSlots.Widgets(project, slot);
            var origin = new Point(layout.Int("x"), layout.Int("y"));
            if (slotWidget != null && ws.Contains(slotWidget))
            {
                var back = new TextBlock { Text = "‹ " + S.Get("wBackToSlot"), FontSize = 13, Cursor = Cursors.Hand, Margin = new Thickness(0, 8, 0, 0) };
                back.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
                back.MouseLeftButtonUp += (s, e) => { slotWidget = null; BuildInspector(); };
                Add(back);
                WidgetSection(slotWidget, origin, null);
                return;
            }
            Add(Ui.Header(S.Get("slChoices") + " · " + ws.Count));
            int shownIdx = Math.Min(WidgetSlots.Shown(project, slot), Math.Max(0, ws.Count - 1));
            for (int i = 0; i < ws.Count; i++)
            {
                int idx = i;
                var w = ws[i];
                var sub = S.Get("slTap", TapTitle(w.Str("jumpApp"))) + (idx == shownIdx ? " · " + S.Get("slShown") : "");
                Add(Card(w, w.Str("widgetName") ?? S.Get("elWidget"), sub, idx == shownIdx, () =>
                {
                    WidgetSlots.Show(project, slot, idx);
                    slotWidget = w;
                    RefreshAll();
                }, cm =>
                {
                    if (idx > 0) Ui.MenuAdd(cm, S.Get("moveUp"), "", () => EditRes(() => WidgetSlots.SlotMove(slot, idx, -1)));
                    if (idx < ws.Count - 1) Ui.MenuAdd(cm, S.Get("moveDown"), "", () => EditRes(() => WidgetSlots.SlotMove(slot, idx, 1)));
                    if (ws.Count > 1) Ui.MenuAdd(cm, S.Get("slRemove"), "", () => project.Edit(p => WidgetSlots.SlotRemove(p, slot, idx)), true);
                }, idx == 0 ? S.Get("slDefault") : null));
            }
            var row = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 8) };
            var nw = new Button { Content = "+ " + S.Get("slNew"), Style = (Style)FindResource("Btn"), Margin = new Thickness(0, 0, 4, 0) };
            nw.Click += (s, e) =>
            {
                XNode made = null;
                project.Edit(p => made = WidgetSlots.SlotNewWidget(p, slot, S.Get("widgetDefault")));
                if (made != null) { WidgetSlots.Show(project, slot, WidgetSlots.Widgets(project, slot).Count - 1); slotWidget = made; RefreshAll(); }
            };
            row.Children.Add(nw);
            var ex = new Button { Content = "+ " + S.Get("slExisting"), Style = (Style)FindResource("Btn"), Margin = new Thickness(4, 0, 0, 0) };
            ex.Click += (s, e) =>
            {
                var cm = new ContextMenu();
                var cands = WidgetSlots.Candidates(project, slot);
                if (cands.Count == 0) Ui.MenuAdd(cm, S.Get("slNoWidgets"), "", () => { }).IsEnabled = false;
                foreach (var c in cands)
                {
                    var cw = c;
                    Ui.MenuAdd(cm, (c.Str("widgetName") ?? c.Str("name")) + " · " + c.All("Item").Count, "", () => project.Edit(p => WidgetSlots.SlotAddExisting(p, slot, cw)));
                }
                Ui.MenuBelow(cm, ex);
            };
            row.Children.Add(ex);
            Add(row);
            Add(Ui.Note(S.Get("slHint")));
            Add(Ui.Header(S.Get("slOnBand")));
            Add(Ui.Note(S.Get("slOnBandHint")));
        }
    }
}
