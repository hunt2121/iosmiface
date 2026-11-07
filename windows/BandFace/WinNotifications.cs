// SPDX-License-Identifier: MIT
// Сповіщення Windows → пристрій. Читаємо спливаючі сповіщення інших програм через UserNotificationListener
// (Windows спершу питає дозвіл), раз на 2 секунди дивимося нові й віддаємо назву програми, заголовок і текст.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Threading;
using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;

namespace BandFace
{
    static class WinNotifications
    {
        public sealed class Note { public string App, Title, Body; public uint Id; }

        /// <summary>Нове сповіщення (на потоці інтерфейсу)</summary>
        public static event Action<Note> Arrived;
        public static bool Running => timer != null;

        static DispatcherTimer timer;
        static readonly HashSet<uint> seen = new HashSet<uint>();
        static bool polling;

        /// <summary>Запуск; null — працює, інакше — чому ні (для журналу й налаштувань)</summary>
        public static async Task<string> StartAsync()
        {
            if (timer != null) return null;
            try
            {
                var l = UserNotificationListener.Current;
                var st = await l.RequestAccessAsync();
                if (st != UserNotificationListenerAccessStatus.Allowed) return "access " + st;
                // те, що вже лежить у центрі сповіщень, не пересилаємо
                foreach (var n in await l.GetNotificationsAsync(NotificationKinds.Toast)) seen.Add(n.Id);
                timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                timer.Tick += async (s, e) => await PollAsync();
                timer.Start();
                return null;
            }
            catch (Exception ex) { return ex.GetType().Name + ": " + ex.Message; }
        }

        public static void Stop()
        {
            timer?.Stop();
            timer = null;
        }

        static async Task PollAsync()
        {
            if (polling) return;
            polling = true;
            try
            {
                var list = await UserNotificationListener.Current.GetNotificationsAsync(NotificationKinds.Toast);
                foreach (var n in list.OrderBy(x => x.CreationTime))
                {
                    if (!seen.Add(n.Id)) continue;
                    var note = Read(n);
                    if (note != null) Arrived?.Invoke(note);
                }
                // забуті сповіщення більше не тримаємо
                var alive = new HashSet<uint>(list.Select(x => x.Id));
                seen.RemoveWhere(id => !alive.Contains(id));
            }
            catch (Exception) { }
            finally { polling = false; }
        }

        static Note Read(UserNotification n)
        {
            try
            {
                string app = "";
                try { app = n.AppInfo.DisplayInfo.DisplayName; } catch (Exception) { }
                var b = n.Notification?.Visual?.GetBinding(KnownNotificationBindings.ToastGeneric);
                var texts = b?.GetTextElements()?.Select(t => t.Text).Where(t => !string.IsNullOrWhiteSpace(t)).ToList() ?? new List<string>();
                if (texts.Count == 0) return null;
                return new Note { App = app, Title = texts[0], Body = string.Join("\n", texts.Skip(1)), Id = n.Id };
            }
            catch (Exception) { return null; }
        }

        /// <summary>Який із вибраних у налаштуваннях: «wa», «tg» або «other»</summary>
        public static string Kind(string app)
        {
            var a = (app ?? "").ToLowerInvariant();
            if (a.Contains("whatsapp")) return "wa";
            if (a.Contains("telegram")) return "tg";
            return "other";
        }

        /// <summary>Ідентифікатор застосунку для пристрою: за ним він показує знайомий значок</summary>
        public static string Package(string kind)
        {
            switch (kind)
            {
                case "wa": return "com.whatsapp";
                case "tg": return "org.telegram.messenger";
                default: return "com.bandface.windows";
            }
        }
    }
}
