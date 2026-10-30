using System.Collections.Generic;
using System.Globalization;

namespace BandFace
{
    /// <summary>Тексти інтерфейсу: українська (типова), англійська, російська.</summary>
    static class S
    {
        static readonly string Lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;

        static readonly Dictionary<string, string[]> T = new Dictionary<string, string[]>
        {
            // ключ → { uk, en, ru }
            ["faces"] = new[] { "Циферблати", "Watch faces", "Циферблаты" },
            ["key"] = new[] { "Ключ", "Key", "Ключ" },
            ["log"] = new[] { "Журнал", "Log", "Журнал" },
            ["band"] = new[] { "Браслет", "Band", "Браслет" },
            ["connected"] = new[] { "Підключено", "Connected", "Подключено" },
            ["notConnected"] = new[] { "Не підключено", "Not connected", "Не подключено" },
            ["disconnect"] = new[] { "Від'єднати", "Disconnect", "Отключить" },
            ["scan"] = new[] { "Шукати браслет", "Find band", "Найти браслет" },
            ["scanning"] = new[] { "Пошук…", "Searching…", "Поиск…" },
            ["installCard"] = new[] { "Встановлення циферблата", "Watch face installation", "Установка циферблата" },
            ["noFile"] = new[] { "Файл не вибрано", "No file selected", "Файл не выбран" },
            ["format"] = new[] { "Формат: .bin або .face", "Format: .bin or .face", "Формат: .bin или .face" },
            ["pickHint"] = new[] { "Натисніть «Вибрати файл»", "Click “Choose file”", "Нажмите «Выбрать файл»" },
            ["pick"] = new[] { "Вибрати файл", "Choose file", "Выбрать файл" },
            ["pickOther"] = new[] { "Вибрати інший файл", "Choose another file", "Выбрать другой файл" },
            ["install"] = new[] { "Встановити на браслет", "Install on band", "Установить на браслет" },
            ["progress"] = new[] { "Передача {0}/{1}", "Sending {0}/{1}", "Передача {0}/{1}" },
            ["keyTitle"] = new[] { "Auth key браслета", "Band auth key", "Auth key браслета" },
            ["paste"] = new[] { "Вставити з буфера", "Paste from clipboard", "Вставить из буфера" },
            ["fromFile"] = new[] { "Знайти у файлі", "Find in a file", "Найти в файле" },
            ["keySaved"] = new[] { "Ключ збережено", "Key saved", "Ключ сохранён" },
            ["keyInvalid"] = new[] { "Auth key має бути 32 hex-символи", "The auth key must be 32 hex characters", "Auth key должен быть из 32 hex-символов" },
            ["keyFound"] = new[] { "Ключ знайдено у файлі", "Key found in the file", "Ключ найден в файле" },
            ["keyNone"] = new[] { "У файлі немає ключа", "No key in the file", "В файле нет ключа" },
            ["keyNote"] = new[] { "Ключ зберігається лише на цьому комп'ютері (зашифрований Windows) і нікуди не надсилається.", "The key is stored only on this PC (encrypted by Windows) and is never sent anywhere.", "Ключ хранится только на этом компьютере (зашифрован Windows) и никуда не отправляется." },
            ["activity"] = new[] { "Активність", "Activity", "Активность" },
            ["dev"] = new[] { "Режим розробника", "Developer mode", "Режим разработчика" },
            ["copy"] = new[] { "Копіювати", "Copy", "Копировать" },
            ["clear"] = new[] { "Очистити", "Clear", "Очистить" },
            ["version"] = new[] { "Версія", "Version", "Версия" },
            ["logEmpty"] = new[] { "Журнал порожній", "The log is empty", "Журнал пуст" },
            ["doneNew"] = new[] { "Циферблат встановлено й активовано", "Watch face installed and activated", "Циферблат установлен и активирован" },
            ["doneOld"] = new[] { "Циферблат уже був на браслеті, його активовано", "The watch face was already on the band; it is now active", "Циферблат уже был на браслете, он активирован" },
            ["errAuth"] = new[] { "Автентифікація не вдалася: перевірте auth key", "Authentication failed: check the auth key", "Аутентификация не удалась: проверьте auth key" },
            ["errTimeout"] = new[] { "Браслет не відповів", "The band did not respond", "Браслет не ответил" },
            ["errConnect"] = new[] { "Спочатку підключіть браслет", "Connect to the band first", "Сначала подключите браслет" },
            ["errFace"] = new[] { "Некоректний файл циферблата", "Invalid watch face file", "Некорректный файл циферблата" },
            ["errInstall"] = new[] { "Браслет відхилив операцію (статус {0})", "The band rejected the operation (status {0})", "Браслет отклонил операцию (статус {0})" },
            ["errLost"] = new[] { "З'єднання розірвано", "Connection lost", "Соединение разорвано" },
            ["errService"] = new[] { "У браслета немає потрібних BLE-характеристик. Від'єднайте його від телефона й спробуйте ще раз.", "The band has no required BLE characteristics. Disconnect it from the phone and try again.", "У браслета нет нужных BLE-характеристик. Отключите его от телефона и повторите." },
            ["errGeneric"] = new[] { "Помилка: {0}", "Error: {0}", "Ошибка: {0}" },
            ["phConnect"] = new[] { "З'єднання…", "Connecting…", "Соединение…" },
            ["phAuth"] = new[] { "Автентифікація…", "Authenticating…", "Аутентификация…" },
            ["phInstall"] = new[] { "Запит на встановлення…", "Requesting install…", "Запрос на установку…" },
            ["phRemove"] = new[] { "Видалення старої версії…", "Removing old version…", "Удаление старой версии…" },
            ["phActivate"] = new[] { "Активація…", "Activating…", "Активация…" },
            ["phPair"] = new[] { "Підтвердіть підключення на браслеті…", "Confirm the connection on the band…", "Подтвердите подключение на браслете…" },
            ["cloudTitle"] = new[] { "Ключ з акаунта Xiaomi", "Key from Xiaomi account", "Ключ из аккаунта Xiaomi" },
            ["cloudBtn"] = new[] { "Отримати ключ через QR", "Get key via QR", "Получить ключ через QR" },
            ["cloudScan"] = new[] { "Відскануйте QR камерою телефона й увійдіть в акаунт Xiaomi", "Scan this QR with the phone camera and sign in to your Xiaomi account", "Отсканируйте QR камерой телефона и войдите в аккаунт Xiaomi" },
            ["cloudGet"] = new[] { "Отримую ключ…", "Fetching the key…", "Получаю ключ…" },
            ["cloudNone"] = new[] { "У акаунті не знайдено пристроїв із ключем", "No devices with a key were found in the account", "В аккаунте не найдено устройств с ключом" },
            ["cloudFail"] = new[] { "Не вдалося: {0}", "Failed: {0}", "Не удалось: {0}" },
            ["cloudPick"] = new[] { "Оберіть браслет:", "Choose your band:", "Выберите браслет:" },
            ["cloudCancel"] = new[] { "Скасувати", "Cancel", "Отмена" },
            ["cloudNote"] = new[] { "Вхід потрібен лише щоб прочитати ключ браслета. Дані входу не зберігаються й нікуди не надсилаються, крім серверів Xiaomi.", "Sign-in is only used to read the band key. Sign-in data is not stored and is sent nowhere except Xiaomi's servers.", "Вход нужен только чтобы прочитать ключ браслета. Данные входа не сохраняются и никуда не отправляются, кроме серверов Xiaomi." },
            ["noBle"] = new[] { "Bluetooth недоступний на цьому комп'ютері", "Bluetooth is not available on this PC", "Bluetooth недоступен на этом компьютере" },
        };

        public static string Get(string key, params object[] args)
        {
            int i = Lang == "en" ? 1 : Lang == "ru" ? 2 : 0;
            string s = T[key][i];
            return args.Length == 0 ? s : string.Format(s, args);
        }
    }
}
