# BandFaceKit

Відкрита бібліотека Swift для встановлення циферблатів на **Xiaomi Smart Band 10** з iPhone по Bluetooth LE.
Ліцензія — [MIT](LICENSE).

Код написано з нуля за текстовим описом протоколу («Протокол Xiaomi Smart Band 10 по BLE — опис без коду»),
без використання коду Gadgetbridge чи BandFace. Проєкт не пов'язаний з Xiaomi; назви — торговельні марки їхніх власників.

> ⚠️ Частина поведінки Band 10 з'ясована лише експериментально (модель M2459B1, прошивка 3.2.7).
> Перевіряйте на справжньому браслеті й ведіть журнал кадрів.

## Що всередині

| Файл | Рівень |
|---|---|
| `Checksums.swift` | CRC-16/ARC (кадри), CRC-32 IEEE (потік файлу) |
| `Frame.swift` | Кадр `A5 A5 · тип · номер · довжина · CRC`, розбирач потоку зі сповіщень, канали й коди операцій |
| `SessionControl.swift` | Відкриття / закриття сесії, параметри TLV |
| `Protobuf.swift` | Мінімальний кодувальник і розбирач protobuf (varint, length-delimited, fixed32) |
| `Commands.swift` | Команди 1/26, 1/27, 2/1, 2/2, 4/0, 4/1, 4/2, 4/4, 22/0 і розбір відповідей |
| `Crypto.swift` | HKDF-SHA256 («miwear-auth»), HMAC, AES-128-CTR (IV = ключ), AES-128-CCM (тег 4 байти) |
| `BandSession.swift` | Актор сесії: автентифікація, шифрування, **сукупні підтвердження з вікном 6 кадрів**, передача файлу |
| `WatchfaceInstaller.swift` | Повний сценарій 4/4 → 22/0 → файл → 4/1, резервне видалення старої версії |
| `FileTransfer.swift` | Потік `00 10 · MD5 · розмір · дані · CRC-32` і частини по C−4 байти |
| `FaceFile.swift` | Заголовок `.face`/`.bin`: ID, назва, прев'ю (BGRA, RGB565 LE/BE, палітра, RLE A/B) |
| `BLETransport.swift` | CoreBluetooth: FE95, TX `0x5F` без відповіді, RX `0x5E` сповіщення, керування потоком |
| `AuthKeyStore.swift` | Читання auth key з `MHWCahe/…/VirtualDevice_registerList/manifest.sqlite` Mi Fitness |

## Підключення

Swift Package Manager, iOS 16+ / macOS 13+:

```swift
.package(url: "https://github.com/<you>/BandFaceKit.git", from: "0.1.0")
```

У `Info.plist` застосунку потрібен `NSBluetoothAlwaysUsageDescription`.

## Використання

```swift
import BandFaceKit

// 1. Auth key: користувач вибирає папку «На iPhone › Mi Fitness» у UIDocumentPickerViewController.
let bookmark = try FolderBookmark.make(for: pickedFolder)          // збережіть одразу
let band = try AuthKeyStore.credentials(inMiFitnessFolder: pickedFolder).first!

// 2. Пошук браслета (серед підключених до системи і скануванням).
let transport = BLEBandTransport()
let found = try await transport.discover()

// 3. Встановлення.
let face = try FaceFile(contentsOf: faceURL)
try await WatchfaceInstaller().install(
    face,
    authKey: band.authKey,
    bandIdentifier: found[0].identifier,
    transport: transport
) { phase in
    print(phase)   // .authenticating, .uploading(sent:total:), .activating, .done(...)
}
```

Нижчий рівень — власна сесія над будь-яким транспортом:

```swift
let session = BandSession(transport: transport)
transport.onReceive = { session.receive($0) }
try await transport.connect(to: id)
try await session.open()
try await session.authenticate(authKey: key)
let info = try await session.deviceInfo()      // «3.2.7», «M2459B1»
let faces = try await session.watchfaces()
await session.close()
transport.disconnect()
```

Сесію **завжди закривайте** й відключайтеся: інакше браслет лишається в цій сесії, і Mi Fitness не може підключитися.
`WatchfaceInstaller` робить це сам, навіть після помилки.

## Важливі особливості Band 10

- Телефон **не підтверджує** вхідні кадри поодинці — після цього браслет перестає приймати команди.
  `BandSession` надсилає одне сукупне підтвердження (номер останнього кадру) через ~0,5 с після команди,
  лише коли браслет уже надіслав 6 непідтверджених кадрів, а телефон чекає ще одну відповідь.
- Повтори кадрів браслета відкидаються за номером.
- Шифрування CTR щоразу починається з IV = ключ; лічильник не продовжується між кадрами.
- Якщо браслет не відповідає на відкриття сесії, запит повторюється з попереднім закриттям (сесію може тримати Mi Fitness).
- Журнал (`BandSession.Configuration.log`) не містить ключів і вмісту команд автентифікації.

## Тести

```sh
swift test
```

Тест-вектори (CRC, HKDF, HMAC, CTR, CCM, protobuf, потік файлу) отримано незалежною реалізацією на Python
з бібліотекою `cryptography`: `python3 Tools/generate_vectors.py`. `SessionTests` проганяє весь сценарій
встановлення на імітації браслета, яка, як Band 10, притримує сьомий кадр до сукупного підтвердження.

## Що не з'ясовано

- Смисл полів 1, 2, 4 в інформації про телефон (використовуються значення 0, 34.0, 224).
- Причина статусу встановлення 5 (ліміт, стара версія чи несумісний файл).
- Чи обов'язкові паузи по 1,5 с після автентифікації (`WatchfaceInstaller.pauseAfterAuth` / `pauseBeforeInstall`).
- Для палітрового прев'ю з RLE припускається, що стиснення охоплює і палітру, і індекси.
