// SPDX-License-Identifier: MIT
// Режим XML: manifest.xml проєкту в редакторі з підсвіткою й номерами рядків, живе превʼю праворуч,
// рядок з помилкою підсвічується червоним. «Застосувати» — одна зміна в історії (Ctrl+Z повертає).

using System;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using BandFace.Faces;
using ICSharpCode.AvalonEdit;
using ICSharpCode.AvalonEdit.Highlighting;
using ICSharpCode.AvalonEdit.Rendering;

namespace BandFace.Creator
{
    public partial class EditorView
    {
        TextEditor xmlEditor;
        DispatcherTimer xmlTimer;
        ErrorLine xmlError;
        /// <summary>Текст, з якого почали редагувати (для «Скасувати зміни» й перевірки, чи є зміни)</summary>
        string xmlBase;
        bool xmlLoading;

        /// <summary>Червоне тло рядка з помилкою</summary>
        sealed class ErrorLine : IBackgroundRenderer
        {
            public int Line;
            public KnownLayer Layer => KnownLayer.Background;
            public void Draw(TextView view, DrawingContext dc)
            {
                if (Line <= 0 || !view.VisualLinesValid) return;
                var brush = new SolidColorBrush(Color.FromArgb(0x40, 0xFF, 0x45, 0x3A));
                foreach (var vl in view.VisualLines)
                {
                    if (vl.FirstDocumentLine.LineNumber != Line) continue;
                    double y = vl.VisualTop - view.ScrollOffset.Y;
                    dc.DrawRectangle(brush, null, new Rect(0, y, view.ActualWidth, vl.Height));
                }
            }
        }

        bool XmlShown => XmlView.Visibility == Visibility.Visible;
        bool XmlDirty => xmlEditor != null && xmlBase != null && xmlEditor.Text != xmlBase;

        void EnsureXmlEditor()
        {
            if (xmlEditor != null) return;
            xmlEditor = new TextEditor
            {
                ShowLineNumbers = true, FontFamily = new FontFamily("Cascadia Mono, Consolas"), FontSize = 13,
                HorizontalScrollBarVisibility = System.Windows.Controls.ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = System.Windows.Controls.ScrollBarVisibility.Auto,
                Padding = new Thickness(6, 0, 0, 0), WordWrap = false,
            };
            xmlEditor.Options.ConvertTabsToSpaces = true;
            xmlEditor.Options.IndentationSize = 2;
            xmlEditor.Options.EnableHyperlinks = false;
            xmlEditor.SetResourceReference(TextEditor.BackgroundProperty, "Card");
            xmlEditor.SetResourceReference(TextEditor.ForegroundProperty, "Text");
            xmlEditor.SetResourceReference(TextEditor.LineNumbersForegroundProperty, "Sub");
            xmlError = new ErrorLine();
            xmlEditor.TextArea.TextView.BackgroundRenderers.Add(xmlError);
            xmlEditor.TextChanged += (s, e) =>
            {
                if (xmlLoading) return;
                xmlTimer.Stop(); xmlTimer.Start();
                RefreshXmlButtons();
            };
            XmlHost.Child = xmlEditor;
            xmlTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
            xmlTimer.Tick += (s, e) => { xmlTimer.Stop(); CheckXml(); };
            XmlRevertBtn.Content = S.Get("xmlRevert");
            XmlApplyBtn.Content = S.Get("xmlApply");
            XmlPreviewTitle.Text = S.Get("preview");
        }

        static IHighlightingDefinition hlLight, hlDark;

        /// <summary>Своя проста підсвітка XML (теги, атрибути, значення, коментарі) — окремо для світлої й темної теми</summary>
        static IHighlightingDefinition Highlighting(bool dark)
        {
            var cached = dark ? hlDark : hlLight;
            if (cached != null) return cached;
            string tag = dark ? "#7AB4FF" : "#1F5FBF", attr = dark ? "#F2A27A" : "#B0442A", val = dark ? "#8FD6A4" : "#1D7F45",
                   com = dark ? "#8A8F98" : "#7A7F87", decl = dark ? "#C49BF0" : "#7A3FB0";
            var xshd = $@"<SyntaxDefinition name=""BandFaceXml"" xmlns=""http://icsharpcode.net/sharpdevelop/syntaxdefinition/2008"">
  <Color name=""Tag"" foreground=""{tag}""/>
  <Color name=""Attr"" foreground=""{attr}""/>
  <Color name=""Value"" foreground=""{val}""/>
  <Color name=""Comment"" foreground=""{com}"" fontStyle=""italic""/>
  <Color name=""Decl"" foreground=""{decl}""/>
  <RuleSet>
    <Span color=""Comment"" multiline=""true""><Begin>&lt;!--</Begin><End>--&gt;</End></Span>
    <Span color=""Decl"" multiline=""true""><Begin>&lt;\?</Begin><End>\?&gt;</End></Span>
    <Span color=""Tag"" multiline=""true"" ruleSet=""InTag""><Begin>&lt;/?</Begin><End>/?&gt;</End></Span>
  </RuleSet>
  <RuleSet name=""InTag"">
    <Span color=""Value""><Begin>""</Begin><End>""</End></Span>
    <Span color=""Value""><Begin>'</Begin><End>'</End></Span>
    <Rule color=""Attr"">[\w:.\-]+(?=\s*=)</Rule>
  </RuleSet>
</SyntaxDefinition>";
            using (var r = System.Xml.XmlReader.Create(new System.IO.StringReader(xshd)))
                cached = ICSharpCode.AvalonEdit.Highlighting.Xshd.HighlightingLoader.Load(r, HighlightingManager.Instance);
            if (dark) hlDark = cached; else hlLight = cached;
            return cached;
        }

        void ApplyXmlColors() => xmlEditor.SyntaxHighlighting = Highlighting(Theme.SystemIsDark());

        string CurrentXml() => Encoding.UTF8.GetString(Xml.Print(project.Root));

        void LoadXml()
        {
            xmlLoading = true;
            var t = CurrentXml();
            var caret = xmlEditor.CaretOffset;
            var scroll = xmlEditor.VerticalOffset;
            xmlEditor.Text = t;
            xmlBase = t;
            xmlEditor.CaretOffset = Math.Min(caret, t.Length);
            xmlEditor.ScrollToVerticalOffset(scroll);
            xmlLoading = false;
            CheckXml();
            RefreshXmlButtons();
        }

        void RefreshXmlButtons() => XmlApplyBtn.IsEnabled = XmlRevertBtn.IsEnabled = XmlDirty;

        void VisualMode_Click(object sender, RoutedEventArgs e) => SetXmlMode(false);
        void XmlMode_Click(object sender, RoutedEventArgs e) => SetXmlMode(true);

        void SetXmlMode(bool xml)
        {
            if (project == null) { VisualMode.IsChecked = true; XmlMode.IsChecked = false; return; }
            if (!xml && XmlDirty)
            {
                var r = MessageBox.Show(Owner, S.Get("xmlLeaveAsk"), "BandFace", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
                if (r == MessageBoxResult.Cancel) { VisualMode.IsChecked = false; XmlMode.IsChecked = true; return; }
                if (r == MessageBoxResult.Yes && !ApplyXml()) { VisualMode.IsChecked = false; XmlMode.IsChecked = true; return; }
            }
            VisualMode.IsChecked = !xml; XmlMode.IsChecked = xml;
            XmlView.Visibility = xml ? Visibility.Visible : Visibility.Collapsed;
            VisualView.Visibility = xml ? Visibility.Collapsed : Visibility.Visible;
            if (xml)
            {
                EnsureXmlEditor();
                ApplyXmlColors();
                LoadXml();
                xmlEditor.Focus();
            }
            else { xmlBase = null; Redraw(); }
        }

        /// <summary>Розбір і превʼю; true — XML правильний</summary>
        bool CheckXml()
        {
            if (xmlEditor == null) return false;
            XNode root = null;
            string err = null;
            int line = 0;
            try
            {
                root = Xml.Parse(Encoding.UTF8.GetBytes(xmlEditor.Text));
                if (root == null) err = S.Get("xmlEmpty");
                else if (root.Tag != "Watchface") err = S.Get("xmlRoot", root.Tag);
            }
            catch (Exception ex)
            {
                err = ex.Message;
                var m = System.Text.RegularExpressions.Regex.Match(ex.Message, @"Line number=(\d+)");
                if (m.Success) { line = int.Parse(m.Groups[1].Value); err = ex.Message.Substring(0, m.Index).Trim(); }
            }
            xmlError.Line = line;
            xmlEditor.TextArea.TextView.InvalidateLayer(KnownLayer.Background);
            if (err != null)
            {
                XmlStatus.Text = line > 0 ? S.Get("xmlErrorAt", line, err) : err;
                XmlStatus.Foreground = (Brush)FindResource("Err");
                XmlStatus.Tag = line;
                return false;
            }
            XmlStatus.Text = XmlDirty ? S.Get("xmlOkDirty") : S.Get("xmlOk");
            XmlStatus.Foreground = (Brush)FindResource(XmlDirty ? "Text" : "Sub");
            XmlStatus.Tag = 0;
            RenderXmlPreview(root);
            return true;
        }

        void RenderXmlPreview(XNode root)
        {
            try
            {
                var p = new FaceProject("xml", null, root, project.Files, project.Meta);
                // малюємо з запасом, а Viewbox вписує в панель будь-якого розміру
                var dev = project.Meta.Device;
                var r = new FaceRenderer(p) { ColorVariant = variant };
                XmlPreview.Source = r.Render(Math.Min(theme, Math.Max(0, p.Themes.Count - 1)), 2 * Dpi).Image;
                XmlPreview.Width = dev.Width; XmlPreview.Height = dev.Height;
                XmlPreview.Clip = new RectangleGeometry(new Rect(0, 0, dev.Width, dev.Height), dev.Corner, dev.Corner);
                XmlPreviewRing.CornerRadius = new CornerRadius(dev.Corner + 3);
            }
            catch (Exception ex)
            {
                XmlStatus.Text = S.Get("buildFail", ex.Message);
                XmlStatus.Foreground = (Brush)FindResource("Err");
            }
        }

        /// <summary>Клік по помилці — до рядка</summary>
        void XmlStatus_Click(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            if (!(XmlStatus.Tag is int line) || line <= 0 || xmlEditor == null) return;
            line = Math.Min(line, xmlEditor.Document.LineCount);
            xmlEditor.ScrollToLine(line);
            xmlEditor.TextArea.Caret.Line = line;
            xmlEditor.Focus();
        }

        void XmlRevert_Click(object sender, RoutedEventArgs e) => LoadXml();
        void XmlApply_Click(object sender, RoutedEventArgs e) => ApplyXml();

        bool ApplyXml()
        {
            if (!CheckXml()) { MessageBox.Show(Owner, S.Get("xmlFixFirst"), "BandFace", MessageBoxButton.OK, MessageBoxImage.Warning); return false; }
            var root = Xml.Parse(Encoding.UTF8.GetBytes(xmlEditor.Text));
            selected = null;
            project.Edit(p => p.SetRoot(root));
            LoadXml();
            return true;
        }

        /// <summary>Проєкт змінився (Ctrl+Z, зміна файла ззовні): якщо в редакторі XML немає своїх правок — показати нове</summary>
        void XmlProjectChanged()
        {
            if (!XmlShown || xmlEditor == null) return;
            if (!XmlDirty) LoadXml(); else CheckXml();
        }
    }
}
