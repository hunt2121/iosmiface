using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;

namespace BandFace.Store
{
    /// <summary>Те, що магазину потрібно від головного вікна: браслет, встановлення, вибір і видалення, редактор</summary>
    interface IStoreHost
    {
        /// <summary>Модель підключеного браслета (10, 11); не підключено — 10</summary>
        int BandModel { get; }
        /// <summary>Браслет підключено й ключ задано: можна встановлювати</summary>
        bool CanOperate { get; }
        /// <summary>Іде встановлення (з будь-якої вкладки)</summary>
        bool Busy { get; }
        string ActiveId { get; }
        IReadOnlyCollection<string> InstalledIds { get; }
        /// <summary>Встановлює файл; прогрес — у report. Повертає текст помилки або null</summary>
        Task<string> InstallAsync(Protocol.FaceFile face, string name, Action<Creator.InstallUpdate> report);
        Task<string> ActivateAsync(string faceId);
        Task<string> DeleteAsync(string faceId);
        /// <summary>Копія циферблата в редакторі</summary>
        void EditCopy(byte[] bin, string name);
    }

    /// <summary>Вкладка «Магазин»: список циферблатів і сторінка циферблата (як у BandFace для iOS)</summary>
    sealed class StoreView : UserControl
    {
        public IStoreHost Host;

        StoreCatalog _catalog;
        string _filter = "all";
        string _sort = "date";
        /// <summary>Протилежний до звичного напрямок: старі першими, найменше переглядів/завантажень першими</summary>
        bool _sortReversed;
        /// <summary>Сортування (порядок у меню): ключ → рядки назви (звичний напрямок, протилежний). Числа — з сервера</summary>
        static readonly Dictionary<string, string[]> SortTitles = new Dictionary<string, string[]>
        {
            ["date"] = new[] { "storeSortNew", "storeSortOld" },
            ["views"] = new[] { "storeSortViews", "storeSortViewsFew" },
            ["downloads"] = new[] { "storeSortDownloads", "storeSortDownloadsFew" },
        };
        string SortTitle(string key) => S.Get(SortTitles[key][key == _sort && _sortReversed ? 1 : 0]);
        string _error;
        bool _loading;
        readonly Dictionary<string, string> _variantOverride = new Dictionary<string, string>();

        // сторінка циферблата
        StoreEntry _open;
        int _style, _color;
        Creator.InstallUpdate _progress;
        string _actionError;

        readonly Grid _root = new Grid();
        readonly ScrollViewer _listScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 36, 0) };
        readonly ScrollViewer _pageScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 36, 0), Visibility = Visibility.Collapsed };

        public StoreView()
        {
            _root.Children.Add(_listScroll);
            _root.Children.Add(_pageScroll);
            Content = _root;
            SizeChanged += (s, e) => { if (e.WidthChanged && _open == null) RenderList(); };
        }

        // MARK: Дані

        /// <summary>Каталог з диска одразу, потім із сервера</summary>
        public async void Refresh()
        {
            if (_catalog == null) { _catalog = StoreClient.Cached(); Render(); }
            if (_loading) return;
            _loading = true;
            try { _catalog = await StoreClient.FetchAsync(); _error = null; }
            catch (Exception) { if (_catalog == null) _error = S.Get("storeNoNetwork"); }
            finally { _loading = false; }
            Render();
            // числа для сортування за переглядами й завантаженнями
            // свіжі числа (або збережені, якщо сервер не відповів) — у капсулах і для сортування
            _stats = await StoreClient.StatsAsync();
            Render();
        }

        /// <summary>Змінився браслет, список циферблатів на ньому або йде встановлення — перемалювати</summary>
        public void BandChanged()
        {
            if (_progress != null && Host != null && !Host.Busy) _progress = null;
            Render();
        }

        void Render()
        {
            if (_open != null) RenderPage(); else RenderList();
        }

        string VariantKey(StoreEntry e)
        {
            if (_variantOverride.TryGetValue(e.Id, out var k) && e.Variants.ContainsKey(k)) return k;
            // на браслеті вже стоїть один з варіантів — він
            var installed = Host?.InstalledIds ?? new string[0];
            var onBand = e.Variants.FirstOrDefault(kv => installed.Contains(kv.Value.FaceId)).Key;
            return onBand ?? StoreVariants.Choose(e, Host?.BandModel ?? 10);
        }

        StoreVariant Variant(StoreEntry e) => e.Variants.TryGetValue(VariantKey(e) ?? "", out var v) ? v : e.Variants.Values.First();

        bool OnBand(StoreEntry e) => Host != null && e.Variants.Values.Any(v => Host.InstalledIds.Contains(v.FaceId));
        bool IsActive(StoreEntry e) => Host?.ActiveId != null && e.Variants.Values.Any(v => v.FaceId == Host.ActiveId);

        /// <summary>Встановлено з магазину старішу версію</summary>
        bool HasUpdate(StoreEntry e)
        {
            if (!OnBand(e)) return false;
            var map = StoreClient.Installed();
            var v = Variant(e);
            return map.TryGetValue(v.FaceId, out var ver) && StoreVersions.Older(ver, e.Version);
        }

        /// <summary>Іконки лише в «Усі», «Безкоштовні», «Платні»; категорії з сервера — без іконок</summary>
        static readonly Dictionary<string, string> FilterIcons = new Dictionary<string, string>
        {
            // чотири квадратики
            { "all", "M2.5,2 H6 Q7,2 7,3 V6 Q7,7 6,7 H3 Q2,7 2,6 V3 Q2,2 3,2 Z M10,2 H13 Q14,2 14,3 V6 Q14,7 13,7 H10 Q9,7 9,6 V3 Q9,2 10,2 Z M3,9 H6 Q7,9 7,10 V13 Q7,14 6,14 H3 Q2,14 2,13 V10 Q2,9 3,9 Z M10,9 H13 Q14,9 14,10 V13 Q14,14 13,14 H10 Q9,14 9,13 V10 Q9,9 10,9 Z" },
            // стрілка завантаження
            { "free", "M7.25,2 H8.75 V8.9 L11,6.65 L12.06,7.71 L8,11.77 L3.94,7.71 L5,6.65 L7.25,8.9 Z M3,12.75 H13 V14.25 H3 Z" },
            // монета
            { "paid", "M8,1.5 A6.5,6.5 0 1 1 7.99,1.5 Z M8,3 A5,5 0 1 0 8.01,3 Z M7.3,4 H8.7 V5 Q10,5.2 10.4,6.3 L9.2,6.8 Q8.9,6.2 8,6.2 Q6.9,6.2 6.9,6.9 Q6.9,7.4 8.2,7.6 Q10.5,8 10.5,9.3 Q10.5,10.6 8.7,10.9 V12 H7.3 V10.9 Q5.9,10.7 5.5,9.6 L6.7,9.1 Q7,9.8 8,9.8 Q9.1,9.8 9.1,9.2 Q9.1,8.8 7.8,8.6 Q5.5,8.2 5.5,6.8 Q5.5,5.3 7.3,5 Z" },
        };

        /// <summary>Іконка й текст; колір іконки — колір тексту плитки (білий на вибраній)</summary>
        static FrameworkElement IconLabel(Control owner, string geometry, string text)
        {
            var path = new System.Windows.Shapes.Path { Data = Geometry.Parse(geometry), Width = 14, Height = 14, Stretch = Stretch.Uniform, Margin = new Thickness(0, 0, 7, 0), VerticalAlignment = VerticalAlignment.Center };
            path.SetBinding(System.Windows.Shapes.Shape.FillProperty, new System.Windows.Data.Binding("Foreground") { Source = owner });
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            sp.Children.Add(path);
            // колір тексту — теж від плитки: інакше загальний стиль TextBlock дає чорний на синій вибраній плитці
            var label = new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center };
            label.SetBinding(TextBlock.ForegroundProperty, new System.Windows.Data.Binding("Foreground") { Source = owner });
            sp.Children.Add(label);
            return sp;
        }

        string CategoryName(string key)
        {
            var c = _catalog?.Categories.FirstOrDefault(x => x.Key == key);
            var name = c == null ? key : StoreVariants.Text(c.Name, null);
            // назва з великої літери, навіть якщо на сервері записана з малої («digital» → «Digital»)
            return string.IsNullOrEmpty(name) ? name : char.ToUpper(name[0], System.Globalization.CultureInfo.CurrentCulture) + name.Substring(1);
        }

        static DateTime? Day(string iso) =>
            iso != null && iso.Length >= 10 && DateTime.TryParse(iso.Substring(0, 10), System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal, out var d) ? d : (DateTime?)null;

        static string SizeText(int bytes) => bytes >= 1024 * 1024 ? (bytes / 1048576.0).ToString("0.0") + " MB" : Math.Max(1, bytes / 1024) + " KB";

        // MARK: Список

        void RenderList()
        {
            _pageScroll.Visibility = Visibility.Collapsed;
            _listScroll.Visibility = Visibility.Visible;
            var sp = new StackPanel { Margin = new Thickness(0, 0, 0, 24) };
            sp.Children.Add(new TextBlock { Text = S.Get("store"), FontSize = 28, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 18) });

            if (_catalog == null)
            {
                sp.Children.Add(Notice(_error ?? S.Get("storeLoading"), _error != null));
                _listScroll.Content = sp;
                return;
            }

            // фільтри й сортування
            // нижній відступ 10 + 8 під кожною капсулою = 18 до карток
            var bar = new DockPanel { Margin = new Thickness(0, 0, 0, 10), LastChildFill = false };
            // висота як у плиток категорій — один рівний ряд
            var sort = new Button { Style = StyleOf("Btn"), Height = 32, VerticalAlignment = VerticalAlignment.Top, Content = SortTitle(_sort) + "  " };
            sort.FontFamily = new FontFamily("Segoe UI, Segoe MDL2 Assets");
            var menu = new ContextMenu();
            foreach (var kv in SortTitles)
            {
                var key = kv.Key;
                // вибраний пункт ще раз — протилежний напрямок
                Creator.Ui.MenuAdd(menu, SortTitle(key), _sort == key ? "" : null, () =>
                {
                    if (_sort == key) _sortReversed = !_sortReversed; else { _sort = key; _sortReversed = false; }
                    RenderList();
                });
            }
            sort.Click += (s, e) => { menu.PlacementTarget = sort; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true; };
            DockPanel.SetDock(sort, Dock.Right);
            bar.Children.Add(sort);
            // «Усі», «Безкоштовні», «Платні» — такі самі категорії, як категорії циферблатів (лише не з сервера).
            // Один рядок: що не вміщається — у меню кнопки «Ще»
            var chips = new CategoryRow { Margin = new Thickness(0, 0, 16, 0) };
            // як в iOS: «Усі», «Платні», «Безкоштовні» — завжди, навіть коли платних ще немає
            var filters = new List<KeyValuePair<string, string>>
            {
                new KeyValuePair<string, string>("all", S.Get("storeAll")),
                new KeyValuePair<string, string>("paid", S.Get("storePaid")),
                new KeyValuePair<string, string>("free", S.Get("storeFree")),
            };
            foreach (var c in _catalog.Categories.Where(c => _catalog.Faces.Any(f => f.Kinds.Contains(c.Key))))
                filters.Add(new KeyValuePair<string, string>(c.Key, CategoryName(c.Key)));
            foreach (var f in filters)
            {
                var key = f.Key;
                var chip = new ToggleButton { Style = StyleOf("CatTile"), IsChecked = _filter == key, Margin = new Thickness(0, 0, 8, 8) };
                chip.Content = FilterIcons.TryGetValue(key, out var icon) ? IconLabel(chip, icon, f.Value) : (object)f.Value;
                chip.Click += (s, e) => { _filter = key; RenderList(); };
                chips.Children.Add(chip);
            }
            // «Ще ⌄» і та сама кнопка з назвою вибраної категорії, якщо вона потрапила в меню
            var selected = filters.FirstOrDefault(x => x.Key == _filter);
            chips.Selected = filters.FindIndex(x => x.Key == _filter);
            foreach (var label in new[] { S.Get("storeMore"), selected.Value ?? S.Get("storeMore") })
            {
                var more = new ToggleButton { Style = StyleOf("CatTile"), Content = label + "  \ue70d", Margin = new Thickness(0, 0, 8, 8),
                    FontFamily = new FontFamily("Segoe UI, Segoe MDL2 Assets"), IsChecked = chips.Children.Count > filters.Count };
                more.Click += (s, e) =>
                {
                    more.IsChecked = chips.Children.IndexOf(more) > filters.Count;   // клік не перемикає підсвічення
                    var menu = new ContextMenu();
                    for (int i = chips.Shown; i < filters.Count; i++)
                    {
                        var key = filters[i].Key;
                        Creator.Ui.MenuAdd(menu, filters[i].Value, _filter == key ? "\ue73e" : null, () => { _filter = key; RenderList(); });
                    }
                    menu.PlacementTarget = more; menu.Placement = PlacementMode.Bottom; menu.IsOpen = true;
                };
                chips.Children.Add(more);
            }
            bar.Children.Add(chips);
            sp.Children.Add(bar);

            IEnumerable<StoreEntry> faces = _catalog.Faces.Where(f =>
                _filter == "all" || (_filter == "free" && f.Price == null) || (_filter == "paid" && f.Price != null) || f.Kinds.Contains(_filter));
            // за числами — спочатку більше, при рівних новіші вище; без статистики — 0
            int Count(StoreEntry f) => _stats != null && _stats.TryGetValue(f.Id, out var st) ? (_sort == "views" ? st.Item1 : st.Item2) : 0;
            faces = _sort == "date"
                ? faces.OrderByDescending(f => Day(f.Added ?? f.Updated) ?? DateTime.MinValue)
                : faces.OrderByDescending(Count).ThenByDescending(f => Day(f.Added ?? f.Updated) ?? DateTime.MinValue);
            if (_sortReversed) faces = faces.Reverse();
            var list = faces.ToList();
            if (list.Count == 0)
            {
                sp.Children.Add(new TextBlock { Text = S.Get("storeEmpty"), FontSize = 14, Foreground = BrushOf("Sub"), Margin = new Thickness(0, 24, 0, 0), HorizontalAlignment = HorizontalAlignment.Center });
            }
            else
            {
                double w = Math.Max(400, ActualWidth - 36);
                // картка не вужча за 218 px: капсула 150 px і поля; у звичайному вікні — 4 в ряд
                int cols = Math.Max(2, Math.Min(6, (int)((w + 12) / 230)));
                // у карток відступ праворуч 12 — сітка ширша на нього, щоб правий край збігався з кнопкою сортування
                var grid = new UniformGrid { Columns = cols, Margin = new Thickness(0, 0, -12, 0) };
                foreach (var f in list) grid.Children.Add(Card(f));
                sp.Children.Add(grid);
            }
            _listScroll.Content = sp;
        }

        FrameworkElement Card(StoreEntry e)
        {
            var v = Variant(e);
            var look = StoreVariants.Look(v, 0, 0);
            var sp = new StackPanel();
            sp.Children.Add(Capsule(look?.Main, 144, 354, IsActive(e)));

            // назва й кружечки кольорів праворуч
            var name = new DockPanel { Margin = new Thickness(0, 14, 0, 0), LastChildFill = true };
            if (v.Colors.Count > 1) { var d = Dots(v.Colors, 13); DockPanel.SetDock(d, Dock.Right); d.Margin = new Thickness(8, 0, 0, 0); name.Children.Add(d); }
            name.Children.Add(new TextBlock { Text = StoreVariants.Text(e.Name, v), FontSize = 15, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
            sp.Children.Add(name);
            // «розмір · версія», праворуч кількість стилів
            var meta = new DockPanel { Margin = new Thickness(0, 3, 0, 0), LastChildFill = true };
            if (v.Styles.Count > 1) { var st = Sub(Plural(v.Styles.Count, "storeStyle1", "storeStyle2", "storeStyle5"), 12); DockPanel.SetDock(st, Dock.Right); meta.Children.Add(st); }
            meta.Children.Add(Sub(SizeText(v.Size) + " · v" + e.Version, 12));
            sp.Children.Add(meta);

            sp.Children.Add(CardButton(e, ActionButton(e, compact: true)));

            var card = new Border { Style = StyleOf("CardBox"), Padding = new Thickness(14), Margin = new Thickness(0, 0, 12, 12), Child = sp, Cursor = Cursors.Hand };
            card.MouseLeftButtonUp += (s, ev) => { if (!(ev.OriginalSource is DependencyObject o && IsInButton(o))) Open(e); };
            return card;
        }

        static bool IsInButton(DependencyObject o)
        {
            for (; o != null; o = o is Visual || o is System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(o) : LogicalTreeHelper.GetParent(o))
                if (o is ButtonBase) return true;
            return false;
        }

        /// <summary>Кнопка картки й сторінки: «Встановити», ціна, «Оновити», «✓ Встановлено»</summary>
        Button ActionButton(StoreEntry e, bool compact)
        {
            var b = new Button { Style = StyleOf("PrimaryBtn"), FontSize = 13 };
            if (e.Price != null && !OnBand(e))
            {
                // платні купуються в BandFace для iPhone (App Store); на Windows лише видно ціну
                b.Content = S.Get("storePaidShort");
                b.IsEnabled = false;
                b.ToolTip = S.Get("storePaidOnly");
                ToolTipService.SetShowOnDisabled(b, true);
                return b;
            }
            if (HasUpdate(e)) { b.Content = S.Get("storeUpdate"); b.Click += (s, ev) => Install(e); }
            else if (OnBand(e))
            {
                b.Style = StyleOf("Btn");
                b.Content = new TextBlock { Text = "✓  " + S.Get("storeInstalled"), Foreground = BrushOf("Ok") };
                b.IsHitTestVisible = !compact;
                if (!compact) b.IsEnabled = false;
            }
            else { b.Content = S.Get("install"); b.Click += (s, ev) => Install(e); }
            bool busy = Host == null || Host.Busy;
            if (b.IsEnabled && b.IsHitTestVisible && (busy || !Host.CanOperate)) { b.IsEnabled = false; b.ToolTip = busy ? null : S.Get("storeConnect"); ToolTipService.SetShowOnDisabled(b, true); }
            return b;
        }

        // MARK: Сторінка циферблата

        void Open(StoreEntry e)
        {
            _open = e; _style = 0; _color = 0; _actionError = null;
            RenderPage();
            _pageScroll.ScrollToTop();
            _ = PrefetchAsync(e, Variant(e));
            _ = LoadStatsAsync(e);
        }

        /// <summary>Перегляди й завантаження (з сервера): відкриття сторінки — +1 перегляд, потім числа</summary>
        Dictionary<string, Tuple<int, int>> _stats = StoreClient.CachedStats();

        async Task LoadStatsAsync(StoreEntry e)
        {
            await StoreClient.SendViewAsync(e.Id);
            _stats = await StoreClient.StatsAsync();
            if (_open == e) RenderPage();
        }

        /// <summary>Перегляди й завантаження запису (Item1 — перегляди, Item2 — завантаження); ще немає — нулі</summary>
        Tuple<int, int> StatsOf(StoreEntry e) =>
            _stats != null && _stats.TryGetValue(e.Id, out var st) ? st : Tuple.Create(0, 0);

        /// <summary>Коротко для картки: до 999 — повністю; далі 1.1k, 15.5k, 120k, 1.2M (один знак до 100, округлення вниз)</summary>
        static string Short(int n)
        {
            if (n < 1000) return n.ToString(CultureInfo.InvariantCulture);
            string Cut(double v, string suffix)
            {
                if (v >= 100) return Math.Floor(v).ToString(CultureInfo.InvariantCulture) + suffix;
                double t = Math.Floor(v * 10) / 10;
                return t.ToString("0.#", CultureInfo.InvariantCulture) + suffix;
            }
            return n < 1000000 ? Cut(n / 1000.0, "k") : Cut(n / 1000000.0, "M");
        }

        /// <summary>Рядок у плашці «Розмір · Версія · Пристрої»: «↓ 1.2k завантажень   👁 3.4k переглядів» —
        /// числа коротко, як на картці, слово завжди «завантажень» / «переглядів»; проміжок — за правилом картки</summary>
        FrameworkElement StatsLine(StoreEntry e)
        {
            var st = StatsOf(e);
            string d = Short(st.Item2), vw = Short(st.Item1);
            return new StatsRow
            {
                Downloads = S.Get("storeDl5", d),
                Views = S.Get("storeView5", vw),
                GapDownloads = d, GapViews = vw,
                Spread = true, MinGap = 27, MaxGap = 44,
                TextSize = 13,
                Height = 20,
                Margin = new Thickness(16, 10, 16, 10),   // цифри (їх центр — по центру рядка) рівно посередині між лінією й низом плашки
            };
        }

        /// <summary>Низ картки: тонка лінія, під нею перегляди й завантаження; від тексту до лінії, від лінії до цифр і від цифр до кнопки — однаково;
        /// пари разом по центру, малі числа трохи розсунуті (проміжок від 28 до 18)</summary>
        FrameworkElement CardButton(StoreEntry e, Button btn)
        {
            var st = StatsOf(e);
            // від низу напису «вага · версія» до лінії, від лінії до верху цифр і від низу цифр до кнопки — однаково:
            // 10 + частина рядка Segoe UI 12 під базовою лінією
            var ff = new FontFamily("Segoe UI");
            double gap = 10 + (ff.LineSpacing - ff.Baseline) * 12, dh = StatsRow.DigitHeight(12), rowH = 18, m = gap - (rowH - dh) / 2;
            var sp = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
            sp.Children.Add(new Border { Height = 1, Background = BrushOf("CardBorder") });
            sp.Children.Add(new StatsRow { Downloads = Short(st.Item2), Views = Short(st.Item1), TextSize = 12, Spread = true, MinGap = 27, MaxGap = 44, Height = rowH,
                Margin = new Thickness(0, m, 0, m) });
            btn.Height = 32;
            sp.Children.Add(btn);
            return sp;
        }

        /// <summary>Сторінка запису за ID (для знімків екрана на збірковому сервері)</summary>
        public async void OpenById(string id)
        {
            if (_catalog == null)
            {
                _catalog = StoreClient.Cached();
                try { _catalog = await StoreClient.FetchAsync(); } catch (Exception) { }
            }
            var e = _catalog?.Faces.FirstOrDefault(f => f.Id == id);
            if (e != null) Open(e);
        }

        public void Back()
        {
            _open = null;
            RenderList();
        }

        /// <summary>Усі стилі й кольори одразу після відкриття: перемикання без очікування</summary>
        async Task PrefetchAsync(StoreEntry e, StoreVariant v)
        {
            var paths = v.Styles.SelectMany(s => s.Previews.SelectMany(p => new[] { p.Main, p.Aod })).Where(p => p != null).Distinct();
            await Task.WhenAll(paths.Select(StoreClient.FileAsync));
        }

        void RenderPage()
        {
            var e = _open;
            if (e == null) return;
            _listScroll.Visibility = Visibility.Collapsed;
            _pageScroll.Visibility = Visibility.Visible;
            var v = Variant(e);
            if (_style >= v.Styles.Count) _style = 0;
            if (_color >= Math.Max(1, v.Colors.Count)) _color = 0;
            var name = StoreVariants.Text(e.Name, v);

            var sp = new StackPanel { Margin = new Thickness(0, 0, 0, 24) };
            // «‹ Магазин › Visual»
            var crumb = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 18) };
            var back = new Button { Style = StyleOf("IconBtn"), Content = "", Width = 34, Height = 34, Margin = new Thickness(0, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center };
            back.Click += (s, ev) => Back();
            crumb.Children.Add(back);
            crumb.Children.Add(new TextBlock { Text = S.Get("store") + "  ›  ", FontSize = 28, Foreground = BrushOf("Sub"), VerticalAlignment = VerticalAlignment.Center });
            crumb.Children.Add(new TextBlock { Text = name, FontSize = 28, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });
            sp.Children.Add(crumb);

            var cols = new Grid();
            cols.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(356) });   // дві капсули 150 + 22 між ними + поля
            cols.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
            // права колонка займає все місце, але не ширша за 400 px; у широкому вікні праворуч лишається поле
            cols.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = 400 });
            var left = PreviewCard(e, v);
            left.VerticalAlignment = VerticalAlignment.Top;
            cols.Children.Add(left);
            var right = RightColumn(e, v);
            Grid.SetColumn(right, 2);
            cols.Children.Add(right);
            sp.Children.Add(cols);
            _pageScroll.Content = sp;
        }

        FrameworkElement PreviewCard(StoreEntry e, StoreVariant v)
        {
            var look = StoreVariants.Look(v, _style, _color);
            var sp = new StackPanel();
            var shots = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            shots.Children.Add(Shot(look?.Main, S.Get("storeNormal")));
            if (look?.Aod != null) { var a = Shot(look.Aod, S.Get("storeAod")); a.Margin = new Thickness(22, 0, 0, 0); shots.Children.Add(a); }
            sp.Children.Add(shots);

            bool looks = v.Styles.Count > 1 || v.Colors.Count > 1;
            // як на головній iOS: превʼю й налаштування стилю/кольору розділяє тонка лінія
            if (looks)
                sp.Children.Add(new Border { Height = 1, Background = BrushOf("CardBorder"), Margin = new Thickness(16, LookGap - LabelInkBelow, 16, 0) });
            if (v.Styles.Count > 1)
            {
                // перемикач стилів: сіра доріжка, вибраний — кольором акценту
                var seg = new UniformGrid { Columns = v.Styles.Count };
                for (int i = 0; i < v.Styles.Count; i++)
                {
                    int idx = i;
                    var t = new ToggleButton { Style = StyleOf("Chip"), Margin = new Thickness(0), Height = 26, IsChecked = i == _style, FontSize = 13,
                        Content = string.IsNullOrEmpty(v.Styles[i].Name) ? S.Get("storeStyleN", i + 1) : v.Styles[i].Name };
                    // без власних рамок: лише доріжка й вибраний стиль кольором акценту (подвійне обведення виглядало дивно)
                    t.Background = Brushes.Transparent;
                    t.BorderBrush = Brushes.Transparent;
                    t.Click += (s, ev) => { _style = idx; RenderPage(); };
                    seg.Children.Add(t);
                }
                sp.Children.Add(new Border { Background = BrushOf("ChipBg"), CornerRadius = new CornerRadius(6), Padding = new Thickness(3),
                    Width = Math.Min(340, 110 * v.Styles.Count), Margin = new Thickness(0, 16, 0, 0), Child = seg, HorizontalAlignment = HorizontalAlignment.Center });
            }
            if (v.Colors.Count > 1)
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center,
                    Margin = new Thickness(0, 16, 0, 0) };
                for (int i = 0; i < v.Colors.Count; i++)
                {
                    int idx = i;
                    var c = Hex(v.Colors[i]);
                    var dot = new Border { Width = 36, Height = 36, CornerRadius = new CornerRadius(18), Padding = new Thickness(3), BorderThickness = new Thickness(2.5), Margin = new Thickness(i == 0 ? 0 : 10, 0, 0, 0),
                        BorderBrush = i == _color ? new SolidColorBrush(c) : Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = v.Colors[i],
                        Child = new Ellipse { Fill = new SolidColorBrush(c), Stroke = new SolidColorBrush(Color.FromArgb(40, 128, 128, 128)), StrokeThickness = 0.5 } };
                    dot.MouseLeftButtonUp += (s, ev) => { _color = idx; RenderPage(); };
                    row.Children.Add(dot);
                }
                sp.Children.Add(row);
            }
            if (looks)
                sp.Children.Add(new TextBlock { Text = S.Get("storeLooksHint"), FontSize = 12, Foreground = BrushOf("Sub"), TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 14, 0, 0) });
            return new Border { Style = StyleOf("CardBox"), Padding = new Thickness(0, 22, 0, 20), Margin = new Thickness(0), Child = sp };
        }

        /// <summary>Проміжок між капсулою, підписом під нею й перемикачем стилів — однаковий на око</summary>
        const double LookGap = 14;

        /// <summary>Порожнє місце над великими літерами в рядку тексту (px)</summary>
        static double InkAbove(TextBlock t)
        {
            var tf = new Typeface(t.FontFamily, t.FontStyle, t.FontWeight, t.FontStretch);
            return (t.FontFamily.Baseline - tf.CapsHeight) * t.FontSize;
        }

        /// <summary>Порожнє місце під базовою лінією підпису «Звичайний» (12 px, той самий шрифт)</summary>
        double LabelInkBelow
        {
            get
            {
                var ff = new TextBlock().FontFamily;
                var family = FontFamily ?? ff;
                return (family.LineSpacing - family.Baseline) * 12;
            }
        }

        FrameworkElement Shot(string path, string title)
        {
            var sp = new StackPanel();
            sp.Children.Add(Capsule(path, 144, 354, false));
            // від низу капсули до верху великих літер — LookGap (порожнє місце над літерами в рядку шрифту віднімається)
            var t = new TextBlock { Text = title, FontSize = 12, Foreground = BrushOf("Sub"), HorizontalAlignment = HorizontalAlignment.Center };
            t.Margin = new Thickness(0, Math.Max(0, LookGap - InkAbove(t)), 0, 0);
            sp.Children.Add(t);
            return sp;
        }

        FrameworkElement RightColumn(StoreEntry e, StoreVariant v)
        {
            var name = StoreVariants.Text(e.Name, v);
            var sp = new StackPanel();
            // Версія · Розмір · Пристрої
            var strip = new Grid();
            for (int i = 0; i < 3; i++) strip.ColumnDefinitions.Add(new ColumnDefinition());
            string[][] cells = { new[] { S.Get("storeSize"), SizeText(v.Size) }, new[] { S.Get("storeVersion"), e.Version }, new[] { S.Get("storeDevices"), "Band " + string.Join(" · ", e.Bands) } };
            for (int i = 0; i < 3; i++)
            {
                var c = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
                c.Children.Add(Sub(cells[i][0], 12));
                c.Children.Add(new TextBlock { Text = cells[i][1], FontSize = 15, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 3, 0, 0) });
                ((TextBlock)c.Children[0]).HorizontalAlignment = HorizontalAlignment.Center;
                var cell = new Border { Child = c, BorderBrush = BrushOf("CardBorder"), BorderThickness = new Thickness(i == 0 ? 0 : 1, 0, 0, 0) };
                Grid.SetColumn(cell, i);
                strip.Children.Add(cell);
            }
            // «Розмір · Версія · Пристрої», під лінією — завантаження й перегляди (та сама плашка, як на iPhone)
            var stripBox = new StackPanel();
            stripBox.Children.Add(strip);
            stripBox.Children.Add(new Border { Height = 1, Background = BrushOf("CardBorder"), Margin = new Thickness(16, 14, 16, 0) });
            stripBox.Children.Add(StatsLine(e));
            sp.Children.Add(new Border { Style = StyleOf("CardBox"), Padding = new Thickness(0, 14, 0, 0), Child = stripBox });

            // мова циферблата: кілька варіантів для цього браслета
            var options = StoreVariants.ForBand(e, Host?.BandModel ?? 10);
            if (options.Count > 1)
            {
                var row = new DockPanel { LastChildFill = false };
                var combo = new ComboBox { MinWidth = 180, Height = 32, VerticalContentAlignment = VerticalAlignment.Center };
                foreach (var kv in options.OrderBy(kv => StoreVariants.Languages.Contains(kv.Key.Substring(0, Math.Min(2, kv.Key.Length))) ? 0 : 1).ThenBy(kv => StoreVariants.Label(kv.Value)))
                {
                    combo.Items.Add(new ComboBoxItem { Content = StoreVariants.Label(kv.Value), Tag = kv.Key });
                    if (kv.Key == v.Key) combo.SelectedIndex = combo.Items.Count - 1;
                }
                combo.IsEnabled = Host == null || !Host.Busy;
                combo.SelectionChanged += (s, ev) =>
                {
                    if (combo.SelectedItem is ComboBoxItem it && it.Tag is string k && k != v.Key)
                    {
                        _variantOverride[e.Id] = k; _style = 0; _color = 0;
                        RenderPage();
                        _ = PrefetchAsync(e, Variant(e));
                    }
                };
                DockPanel.SetDock(combo, Dock.Right);
                row.Children.Add(combo);
                row.Children.Add(new TextBlock { Text = S.Get("storeFaceLang"), FontSize = 14, VerticalAlignment = VerticalAlignment.Center });
                sp.Children.Add(new Border { Style = StyleOf("CardBox"), Padding = new Thickness(16, 10, 10, 10), Child = row });
            }

            // перегляди й завантаження — окрема капсула над кнопками (однакова в усіх станах); далі кнопки або прогрес
            sp.Children.Add(Actions(e, v));
            if (_actionError != null)
                sp.Children.Add(new TextBlock { Text = _actionError, FontSize = 12, Foreground = BrushOf("Err"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(2, -4, 0, 12) });

            // «Що нового» — тим, у кого стара версія
            var news = StoreVariants.Text(e.WhatsNew, v);
            if (HasUpdate(e) && news.Length > 0)
            {
                var wn = new StackPanel();
                wn.Children.Add(new TextBlock { Text = S.Get("storeWhatsNew", e.Version), FontSize = 14, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 4) });
                wn.Children.Add(new TextBlock { Text = news, FontSize = 13, Foreground = BrushOf("Sub"), TextWrapping = TextWrapping.Wrap });
                sp.Children.Add(new Border { Style = StyleOf("CardBox"), Padding = new Thickness(16, 14, 16, 14), Child = wn });
            }

            var about = StoreVariants.Text(e.About, v);
            if (about.Length > 0)
                sp.Children.Add(new TextBlock { Text = about, FontSize = 13, Foreground = BrushOf("Sub"), TextWrapping = TextWrapping.Wrap, LineHeight = 19, Margin = new Thickness(2, 0, 2, 16) });

            sp.Children.Add(Information(e, v));

            // «Змінити в редакторі»: копія, оригінал не зміниться
            var edit = new Button { Style = StyleOf("Btn"), Height = 48, Padding = new Thickness(14, 0, 16, 0), HorizontalContentAlignment = HorizontalAlignment.Stretch, Background = BrushOf("Card"), BorderBrush = BrushOf("CardBorder"), Margin = new Thickness(0, 12, 0, 0) };
            var editRow = new DockPanel();
            var chev = new TextBlock { Text = "", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 11, Foreground = BrushOf("Sub"), VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(chev, Dock.Right);
            editRow.Children.Add(chev);
            var editLabel = new StackPanel { Orientation = Orientation.Horizontal };
            editLabel.Children.Add(Icon("edit", 13, BrushOf("Text")));
            editLabel.Children.Add(new TextBlock { Text = S.Get("storeEdit"), FontSize = 14, Margin = new Thickness(7, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            editRow.Children.Add(editLabel);
            edit.Content = editRow;
            edit.Click += async (s, ev) =>
            {
                edit.IsEnabled = false;
                try { var f = await StoreClient.DownloadAsync(v); Host?.EditCopy(f.Data, name); }
                catch (Exception ex) { _actionError = ex is StoreException ? ex.Message : S.Get("storeNoNetwork"); RenderPage(); }
                finally { edit.IsEnabled = true; }
            };
            sp.Children.Add(edit);
            sp.Children.Add(new TextBlock { Text = S.Get("storeEditHint"), FontSize = 12, Foreground = BrushOf("Sub"), Margin = new Thickness(2, 6, 0, 0) });

            // видалення — окремо внизу; лише для встановленого
            if (OnBand(e) && _progress == null)
            {
                var del = new Button { Style = StyleOf("DangerBtn"), Content = S.Get("storeDelete"), Height = 40, FontSize = 14, Margin = new Thickness(0, 12, 0, 0) };
                del.IsEnabled = Host != null && Host.CanOperate && !Host.Busy;
                del.Click += async (s, ev) =>
                {
                    if (MessageBox.Show(Window.GetWindow(this), S.Get("storeDeleteAsk", name), "BandFace", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
                    del.IsEnabled = false;
                    var id = e.Variants.Values.First(x => Host.InstalledIds.Contains(x.FaceId)).FaceId;
                    _actionError = await Host.DeleteAsync(id);
                    if (_actionError == null) StoreClient.SetInstalled(id, null);
                    RenderPage();
                };
                sp.Children.Add(del);
            }
            return sp;
        }

        /// <summary>Кнопки «Встановити / Оновити» і «Вибрати на браслеті», а під час встановлення — смужка прогресу</summary>
        FrameworkElement Actions(StoreEntry e, StoreVariant v)
        {
            if (_progress != null && (_progress.State == Creator.InstallUpdate.Kind.Connecting || _progress.State == Creator.InstallUpdate.Kind.Uploading))
            {
                var p = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
                var bar = new ProgressBar { Height = 6, Minimum = 0, Maximum = 1, Value = _progress.Fraction, Foreground = BrushOf("Accent"), Background = BrushOf("Track"), BorderThickness = new Thickness(0) };
                p.Children.Add(bar);
                var info = new DockPanel { Margin = new Thickness(0, 6, 0, 0) };
                var pct = Sub((int)(_progress.Fraction * 100) + "%", 12);
                DockPanel.SetDock(pct, Dock.Right);
                info.Children.Add(pct);
                info.Children.Add(Sub(_progress.Text ?? "", 12));
                p.Children.Add(info);
                return p;
            }
            var g = new Grid { Margin = new Thickness(0, 0, 0, 14) };
            g.ColumnDefinitions.Add(new ColumnDefinition());
            var main = ActionButton(e, compact: false);
            main.Height = 40; main.FontSize = 14;
            g.Children.Add(main);
            if (OnBand(e))
            {
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
                g.ColumnDefinitions.Add(new ColumnDefinition());
                var sel = new Button { Style = StyleOf("Btn"), Height = 40, FontSize = 14 };
                if (IsActive(e)) { sel.Content = new TextBlock { Text = "✓  " + S.Get("storeOnScreen"), Foreground = BrushOf("Ok") }; sel.IsEnabled = false; }
                else
                {
                    sel.Content = S.Get("storeSelect");
                    sel.IsEnabled = Host != null && Host.CanOperate && !Host.Busy;
                    sel.Click += async (s, ev) =>
                    {
                        sel.IsEnabled = false;
                        var id = e.Variants.Values.First(x => Host.InstalledIds.Contains(x.FaceId)).FaceId;
                        _actionError = await Host.ActivateAsync(id);
                        RenderPage();
                    };
                }
                Grid.SetColumn(sel, 2);
                g.Children.Add(sel);
            }
            return g;
        }

        async void Install(StoreEntry e)
        {
            if (Host == null || Host.Busy) return;
            var v = Variant(e);
            var name = StoreVariants.Text(e.Name, v);
            _actionError = null;
            _progress = new Creator.InstallUpdate { State = Creator.InstallUpdate.Kind.Connecting, Text = S.Get("storeDownloading") };
            Render();
            Protocol.FaceFile face;
            try { face = await StoreClient.DownloadAsync(v); }
            catch (Exception ex)
            {
                _progress = null;
                _actionError = ex is StoreException ? ex.Message : S.Get("storeNoNetwork");
                if (_open == null) MessageBox.Show(Window.GetWindow(this), _actionError, "BandFace", MessageBoxButton.OK, MessageBoxImage.Warning);
                Render();
                return;
            }
            var err = await Host.InstallAsync(face, name, u => { _progress = u; Render(); });
            _progress = null;
            if (err == null) StoreClient.SetInstalled(v.FaceId, e.Version);
            else
            {
                _actionError = err;
                if (_open == null) MessageBox.Show(Window.GetWindow(this), err, "BandFace", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            Render();
        }

        // MARK: Інформація

        FrameworkElement Information(StoreEntry e, StoreVariant v)
        {
            var sp = new StackPanel();
            sp.Children.Add(new TextBlock { Text = S.Get("storeInfo"), FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) });
            var tiles = new List<FrameworkElement>();
            tiles.Add(Tile("band", S.Get("storeCompat"), "Band " + string.Join(" · ", e.Bands), new TextBlock { Text = "Xiaomi Smart Band", FontSize = 12, Foreground = BrushOf("Sub") }));
            FrameworkElement lookNote;
            if (v.Colors.Count > 1)
            {
                var row = new StackPanel { Orientation = Orientation.Horizontal };
                row.Children.Add(Dots(v.Colors, 12));
                row.Children.Add(new TextBlock { Text = Plural(v.Colors.Count, "storeColor1", "storeColor2", "storeColor5"), FontSize = 12, Foreground = BrushOf("Sub"), Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
                lookNote = row;
            }
            else lookNote = new TextBlock { Text = S.Get("storeNoColors"), FontSize = 12, Foreground = BrushOf("Sub") };
            tiles.Add(Tile("palette", S.Get("storeLook"), Plural(Math.Max(1, v.Styles.Count), "storeStyle1", "storeStyle2", "storeStyle5"), lookNote));
            var lang = v.Langs.FirstOrDefault(l => l != "*");
            tiles.Add(Tile("globe", S.Get("language"), lang == null ? S.Get("storeAllLangs") : StoreVariants.LanguageName(lang),
                new TextBlock { Text = S.Get(v.Clock == "12h" ? "storeClock12" : v.Clock == "24h" ? "storeClock24" : "storeAnyClock"), FontSize = 12, Foreground = BrushOf("Sub") }));
            var day = Day(e.Updated ?? e.Added);
            if (day != null)
                tiles.Add(Tile("calendar", S.Get("storeUpdated"), day.Value.ToString("d MMMM", System.Globalization.CultureInfo.CurrentUICulture),
                    new TextBlock { Text = day.Value.Year.ToString(), FontSize = 12, Foreground = BrushOf("Sub") }));
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
            g.ColumnDefinitions.Add(new ColumnDefinition());
            for (int i = 0; i < tiles.Count; i++)
            {
                if (i % 2 == 0) g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                Grid.SetRow(tiles[i], i / 2);
                Grid.SetColumn(tiles[i], i % 2 == 0 ? 0 : 2);
                g.Children.Add(tiles[i]);
            }
            sp.Children.Add(g);
            if (e.Kinds.Count > 0)
            {
                var chips = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
                foreach (var k in e.Kinds)
                    chips.Children.Add(new Border { Background = BrushOf("ChipBg"), CornerRadius = new CornerRadius(12), Padding = new Thickness(11, 4, 11, 5), Margin = new Thickness(0, 0, 6, 0),
                        Child = new TextBlock { Text = CategoryName(k), FontSize = 12, FontWeight = FontWeights.SemiBold } });
                var cat = new StackPanel();
                cat.Children.Add(Caption("tag", S.Get("storeCategories")));
                cat.Children.Add(chips);
                sp.Children.Add(new Border { Style = StyleOf("CardBox"), Padding = new Thickness(14, 13, 14, 13), Margin = new Thickness(0, 0, 0, 0), Child = cat });
            }
            return sp;
        }

        FrameworkElement Tile(string icon, string caption, string value, FrameworkElement note)
        {
            var g = new Grid();
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g.Children.Add(Caption(icon, caption));
            var val = new TextBlock { Text = value, FontSize = 16, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis };
            Grid.SetRow(val, 2);
            g.Children.Add(val);
            Grid.SetRow(note, 3);
            g.Children.Add(note);
            return new Border { Style = StyleOf("CardBox"), Padding = new Thickness(14, 13, 14, 12), Margin = new Thickness(0, 0, 0, 10), Height = 88, Child = g };
        }

        FrameworkElement Caption(string icon, string text)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            var ic = Icon(icon, icon == "band" ? 14 : 11, BrushOf("Sub"));
            ic.VerticalAlignment = VerticalAlignment.Center;
            sp.Children.Add(ic);
            sp.Children.Add(new TextBlock { Text = text.ToUpper(System.Globalization.CultureInfo.CurrentUICulture), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = BrushOf("Sub"),
                Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            return sp;
        }

        // MARK: Дрібниці

        /// <summary>Значки підписів (ті самі, що в iOS): контур у сітці 24, браслет — суцільний (сітка 26)</summary>
        static readonly Dictionary<string, Tuple<Rect, string, bool>> Icons = new Dictionary<string, Tuple<Rect, string, bool>>
        {
            ["band"] = Tuple.Create(new Rect(6.4, 0.6, 13.2, 24.8), "M9.711,1.0 H16.289 L16.911,5.533 H9.089 Z M9.089,20.467 H16.911 L16.289,25.0 H9.711 Z M11.667,4.644 H14.333 Q19.222,4.644 19.222,9.444 V16.556 Q19.222,21.356 14.333,21.356 H11.667 Q6.778,21.356 6.778,16.556 V9.444 Q6.778,4.644 11.667,4.644 Z M10.333,7.133 Q9.356,7.133 9.356,8.2 V17.8 Q9.356,18.867 10.333,18.867 H15.667 Q16.644,18.867 16.644,17.8 V8.2 Q16.644,7.133 15.667,7.133 Z", true),
            ["palette"] = Tuple.Create(new Rect(1.6, 1.6, 20.8, 20.8), "M12 3a9 9 0 1 0 0 18c1.2 0 1.6-1 1.1-1.9-.6-1 .1-2.1 1.2-2.1H17a4 4 0 0 0 4-4c0-5.5-4-10-9-10z", false),
            ["globe"] = Tuple.Create(new Rect(1.6, 1.6, 20.8, 20.8), "M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0z M3 12h18 M12 3c3 3.5 3 14.5 0 18 M12 3c-3 3.5-3 14.5 0 18", false),
            ["calendar"] = Tuple.Create(new Rect(1.6, 1.6, 20.8, 20.8), "M6 5h12a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V8a3 3 0 0 1 3-3z M3 10h18 M8 3v4 M16 3v4", false),
            ["tag"] = Tuple.Create(new Rect(1.6, 2.6, 19.8, 19.8), "M3 12V4h8l9 9-8 8z M8.8 8.5a1.3 1.3 0 1 1-2.6 0a1.3 1.3 0 1 1 2.6 0z", false),
            ["edit"] = Tuple.Create(new Rect(3.6, 3.1, 17.3, 17.3), "M15.5 4.5l4 4L9 19H5v-4z", false),
        };

        static FrameworkElement Icon(string name, double height, Brush brush)
        {
            var t = Icons[name];
            var path = new System.Windows.Shapes.Path { Data = Geometry.Parse(t.Item2) };
            if (t.Item3) { path.Fill = brush; }
            else { path.Stroke = brush; path.StrokeThickness = name == "edit" ? 2.1 : 2.5; path.StrokeStartLineCap = path.StrokeEndLineCap = PenLineCap.Round; path.StrokeLineJoin = PenLineJoin.Round; }
            path.RenderTransform = new TranslateTransform(-t.Item1.X, -t.Item1.Y);
            var canvas = new Canvas { Width = t.Item1.Width, Height = t.Item1.Height, ClipToBounds = false };
            canvas.Children.Add(path);
            return new Viewbox { Height = height, Width = height * t.Item1.Width / t.Item1.Height, Child = canvas, Stretch = Stretch.Fill };
        }

        /// <summary>Капсула превʼю, як на вкладці «Циферблати»: сіре обведення 3 px, зелене — циферблат на екрані браслета</summary>
        FrameworkElement Capsule(string path, double w, double h, bool active)
        {
            var capsule = BandFace.PreviewCapsule.Make(w, h, active, out var img);
            _ = LoadImage(img, path);
            return capsule;
        }

        static readonly Dictionary<string, BitmapSource> Images = new Dictionary<string, BitmapSource>();

        static async Task LoadImage(Image img, string path)
        {
            if (string.IsNullOrEmpty(path)) return;
            if (Images.TryGetValue(path, out var cached)) { Sharp.Show(img, cached); return; }
            var data = await StoreClient.FileAsync(path);
            if (data == null) return;
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                bmp.StreamSource = new MemoryStream(data);
                bmp.EndInit();
                bmp.Freeze();
                Images[path] = bmp;
                Sharp.Show(img, bmp);
            }
            catch (Exception) { }
        }

        /// <summary>Кружечки кольорів внахлест (до 4, далі «+N»), як у магазині iOS</summary>
        FrameworkElement Dots(List<string> colors, double size)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var ring = BrushOf("Card");
            int n = Math.Min(4, colors.Count);
            for (int i = 0; i < n; i++)
            {
                var dot = new Ellipse { Width = size + 3, Height = size + 3, Fill = new SolidColorBrush(Hex(colors[i])), Stroke = ring, StrokeThickness = 1.5, Margin = new Thickness(i == 0 ? 0 : -5, 0, 0, 0) };
                Panel.SetZIndex(dot, 10 - i);
                sp.Children.Add(dot);
            }
            if (colors.Count > 4) sp.Children.Add(new TextBlock { Text = "+" + (colors.Count - 4), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = BrushOf("Sub"), Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center });
            return sp;
        }

        static Color Hex(string s)
        {
            try { return (Color)ColorConverter.ConvertFromString(s); } catch (Exception) { return Colors.Gray; }
        }

        FrameworkElement Notice(string text, bool error)
        {
            var sp = new StackPanel();
            sp.Children.Add(new TextBlock { Text = text, FontSize = 14, Foreground = error ? BrushOf("Err") : BrushOf("Sub"), TextWrapping = TextWrapping.Wrap });
            if (error)
            {
                var retry = new Button { Style = StyleOf("Btn"), Content = S.Get("storeRetry"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 12, 0, 0) };
                retry.Click += (s, e) => Refresh();
                sp.Children.Add(retry);
            }
            return new Border { Style = StyleOf("CardBox"), Padding = new Thickness(20), Child = sp };
        }

        TextBlock Sub(string text, double size) => new TextBlock { Text = text, FontSize = size, Foreground = BrushOf("Sub"), TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };

        static string Plural(int n, string one, string few, string many)
        {
            int a = n % 10, b = n % 100;
            var key = a == 1 && b != 11 ? one : a >= 2 && a <= 4 && (b < 12 || b > 14) ? few : many;
            return S.Get(key, n);
        }

        Style StyleOf(string key) => (Style)FindResource(key);
        Brush BrushOf(string key) => (Brush)FindResource(key);
    }

    /// <summary>Категорії магазину одним рядком: плитки, що не вміщаються, ховаються в меню кнопки «Ще».
    /// Діти: плитки категорій, потім кнопка «Ще» і кнопка з назвою вибраної категорії (коли вибрана в меню)</summary>
    public class CategoryRow : Panel
    {
        /// <summary>Номер вибраної категорії</summary>
        public int Selected = -1;
        /// <summary>Скільки плиток видно; решта — у меню</summary>
        public int Shown { get; private set; }
        UIElement _more;

        int Tiles => Children.Count - 2;

        protected override Size MeasureOverride(Size available)
        {
            var inf = new Size(double.PositiveInfinity, double.PositiveInfinity);
            double height = 0;
            foreach (UIElement c in Children) { c.Measure(inf); height = Math.Max(height, c.DesiredSize.Height); }
            int n = Tiles;
            double all = 0;
            for (int i = 0; i < n; i++) all += Children[i].DesiredSize.Width;
            if (n <= 0 || double.IsInfinity(available.Width) || all <= available.Width)
            {
                Shown = Math.Max(0, n); _more = null;
                return new Size(Math.Max(0, all), height);
            }
            // найбільше плиток, що вміщаються разом із кнопкою; вибрана в меню — кнопка з її назвою
            for (int k = n - 1; k >= 0; k--)
            {
                var more = Selected >= k ? Children[n + 1] : Children[n];
                double w = more.DesiredSize.Width;
                for (int i = 0; i < k; i++) w += Children[i].DesiredSize.Width;
                if (w <= available.Width || k == 0)
                {
                    Shown = k; _more = more;
                    return new Size(Math.Min(w, available.Width), height);
                }
            }
            return new Size(0, height);
        }

        protected override Size ArrangeOverride(Size final)
        {
            double x = 0;
            int n = Tiles;
            for (int i = 0; i < Children.Count; i++)
            {
                var c = Children[i];
                bool show = i < n ? i < Shown : c == _more;
                // сховані (у меню) — Hidden: місце не займають, не малюються й не натискаються
                var v = show ? Visibility.Visible : Visibility.Hidden;
                if (c.Visibility != v) c.Visibility = v;
                if (show) { c.Arrange(new Rect(x, 0, c.DesiredSize.Width, c.DesiredSize.Height)); x += c.DesiredSize.Width; }
                else c.Arrange(new Rect(0, 0, 0, 0));
            }
            return final;
        }
    }
}
