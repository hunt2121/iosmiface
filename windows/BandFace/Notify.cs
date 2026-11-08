// SPDX-License-Identifier: MIT
// Сповіщення на пристрій: вітання при підключенні та пересилання сповіщень Windows (WhatsApp, Telegram, інші).
// Кожне пересилання — короткий сеанс: вхід, сповіщення, вихід (як «активація» після підключення).
// Один сеанс за раз: _bandGate спільний зі встановленням циферблата.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using BandFace.Protocol;

namespace BandFace
{
    public partial class MainWindow
    {
        readonly SemaphoreSlim _bandGate = new SemaphoreSlim(1, 1);
        readonly Queue<WinNotifications.Note> _notes = new Queue<WinNotifications.Note>();
        bool _sendingNotes;
        int _noteId = Environment.TickCount & 0xFFFF;

        int NextNoteId() => ++_noteId;

        static HashSet<string> ForwardKinds()
        {
            var v = Storage.LoadText("notifyApps");
            return new HashSet<string>((string.IsNullOrEmpty(v) ? "wa,tg" : v).Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries));
        }

        void Welcome_Click(object sender, RoutedEventArgs e) => Storage.SaveText("notifyWelcome", WelcomeSwitch.IsChecked == true ? "" : "0");

        async void Forward_Click(object sender, RoutedEventArgs e)
        {
            bool on = ForwardSwitch.IsChecked == true;
            Storage.SaveText("notifyForward", on ? "1" : "");
            if (on) await StartForwardAsync();
            else { WinNotifications.Stop(); RefreshForward(null); }
        }

        void ForwardApps_Click(object sender, RoutedEventArgs e)
        {
            var l = new List<string>();
            if (AppWa.IsChecked == true) l.Add("wa");
            if (AppTg.IsChecked == true) l.Add("tg");
            if (AppOther.IsChecked == true) l.Add("other");
            Storage.SaveText("notifyApps", l.Count == 0 ? "," : string.Join(",", l));
        }

        async Task StartForwardAsync()
        {
            var err = await WinNotifications.StartAsync();
            AddLog("notifications: " + (err ?? "listening"));
            RefreshForward(err);
        }

        void RefreshForward(string err)
        {
            bool on = ForwardSwitch.IsChecked == true;
            ForwardApps.IsEnabled = on;
            RowForwardDesc.Text = err != null ? S.Get("forwardFail", err)
                                : on && WinNotifications.Running ? S.Get("forwardOn")
                                : S.Get("forwardDesc");
            RowForwardDesc.Foreground = (System.Windows.Media.Brush)FindResource(err != null ? "Err" : "Sub");
        }

        void OnWindowsNotification(WinNotifications.Note n)
        {
            // у журнал — кожне сповіщення Windows, яке побачили, навіть якщо його не пересилаємо
            AddLog("windows toast: «" + n.App + "» → " + WinNotifications.Kind(n.App) + (ForwardSwitch.IsChecked == true && ForwardKinds().Contains(WinNotifications.Kind(n.App)) ? "" : " (skip)"));
            if (ForwardSwitch.IsChecked != true) return;
            // власні сповіщення BandFace не пересилаємо
            if ((n.App ?? "").IndexOf("BandFace", StringComparison.OrdinalIgnoreCase) >= 0) return;
            if (!ForwardKinds().Contains(WinNotifications.Kind(n.App))) return;
            AddLog("notification from " + n.App);
            lock (_notes) { _notes.Enqueue(n); while (_notes.Count > 8) _notes.Dequeue(); }
            _ = SendNotesAsync();
        }

        /// <summary>Тимчасово: пронумеровані смайли й символи, щоб побачити, які пристрій уміє показати
        /// (1 — ❤ без варіанта, 2 — ❤️ з U+FE0F, 3–9 — емодзі поза BMP, 10–14 — прості символи)</summary>
        const string EmojiProbe = "1\u2764 2\u2764\uFE0F 3\U0001F600 4\U0001F602 5\U0001F44D 6\U0001F64F 7\U0001F525 8\U0001F389 9\u2705 10\u2B50 11\u263A 12\u2665 13\u2714 14\u2605";

        void TestNotify_Click(object sender, RoutedEventArgs e)
        {
            lock (_notes) _notes.Enqueue(new WinNotifications.Note { App = "BandFace", Title = S.Get("testTitle"), Body = S.Get("testBody") + "\n" + EmojiProbe });
            _ = SendNotesAsync(true);
        }

        /// <summary>Надсилає чергу одним сеансом; пристрій не підключений — сповіщення пропадають (як на телефоні без зв'язку)</summary>
        async Task SendNotesAsync(bool test = false)
        {
            if (_sendingNotes) return;
            var key = Bytes.ParseHex(KeyBox.Text);
            if (key == null || key.Length != 16 || !_ble.IsConnected)
            {
                lock (_notes) _notes.Clear();
                if (test) SetStatus(S.Get(key == null || key.Length != 16 ? "needKey" : "needBand"), true);
                return;
            }
            _sendingNotes = true;
            await _bandGate.WaitAsync();
            var session = new BandSession(_ble, NewConfig());
            _session = session;
            try
            {
                await session.OpenAsync();
                await session.AuthenticateAsync(key, "Windows PC", "UK", Command.PhoneInfoMiFitness(Region()));
                try { await session.CommandAsync(Command.AfterAuthMiFitness, 3000); } catch (BandException) { }
                var icons = new IconResponder(session, AddLogSafe);
                while (true)
                {
                    WinNotifications.Note n;
                    lock (_notes) { if (_notes.Count == 0) break; n = _notes.Dequeue(); }
                    var kind = WinNotifications.Kind(n.App);
                    var appName = kind == "wa" ? "WhatsApp" : kind == "tg" ? "Telegram" : (string.IsNullOrEmpty(n.App) ? "Windows" : n.App);
                    await session.SendAsync(Command.Notification(NextNoteId(), WinNotifications.PackageFor(kind, n.App), appName, Cut(n.Title, 64), Cut(n.Body, 400), DateTime.Now));
                    AddLog("notification sent: " + appName);
                    await Task.Delay(250);
                }
                // не рвемо зв'язок одразу: пристрій має встигнути показати сповіщення й попросити значок
                await icons.SettleAsync(2500, 20000);
                icons.Detach();
                await session.CloseAsync();
            }
            catch (Exception ex) { AddLog("notification: " + ex.Message); if (test) SetStatus(Describe(ex), true); }
            finally
            {
                try { session.Dispose(); } catch (Exception) { }
                _session = null;
                _bandGate.Release();
                _sendingNotes = false;
            }
            // поки надсилали, могли прийти нові
            bool more; lock (_notes) more = _notes.Count > 0;
            if (more) _ = SendNotesAsync();
        }

        static string Cut(string s, int max) => s == null ? "" : s.Length <= max ? s : s.Substring(0, max - 1) + "…";
    }
}
