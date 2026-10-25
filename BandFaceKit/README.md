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
| `Commands.swift` | Команди 1/26, 1/27, 2/1, 2/2, 4/0, 4/1, 4/2, 4/4, 22/0 і розбір потрібних відповідей |
| `Crypto.swift` | HKDF-SHA256 («miwear-auth»), HMAC, AES-128-CTR (IV = ключ), AES-128-CCM (тег 4 байти) |
| `BandSession.swift` | Актор сесії: автентифікація, шифрування, підтвердження кожного кадру, передача файлу з повтором загублених частин |
| `WatchfaceInstaller.swift` | Повний сценарій 4/4 → 22/0 → файл → статус 4/5; 4/1 лише для вже наявного циферблата |
| `FileTransfer.swift` | Потік `00 10 · MD5 · розмір · дані · CRC-32` і частини по C−4 байти |
| `FaceFile.swift` | Заголовок `.face`/`.bin`: ID, назва, прев'ю (BGRA, RGB565 LE/BE, палітра, RLE A/B) |
| `BandGATT.swift` | UUID сервісу FE95 і характеристик TX `0x5F`, RX `0x5E` |
| `AuthKeyStore.swift` | Читання auth key з `MHWCahe/…/VirtualDevice_registerList/manifest.sqlite` Mi Fitness |

## Підключення

Swift Package Manager, iOS 16+ / macOS 13+:

```swift
.package(url: "https://github.com/<you>/BandFaceKit.git", from: "0.1.0")
```

У `Info.plist` застосунку потрібен `NSBluetoothAlwaysUsageDescription`.

## Використання

Бібліотека не працює з Bluetooth сама: застосунок підключає браслет і реалізує `BandTransport`
(запис цілого кадру в `BandGATT.tx`), а сповіщення з `BandGATT.rx` передає в `session.receive`.

```swift
import BandFaceKit

// Auth key з папки «На iPhone › Mi Fitness» (вибрана в UIDocumentPickerViewController).
let bookmark = try FolderBookmark.make(for: pickedFolder)          // збережіть одразу
let manifest = AuthKeyStore.findManifests(in: pickedFolder).first!
let band = try AuthKeyStore.credentials(fromManifest: manifest).first!

// Встановлення поверх свого транспорту.
let session = BandSession(transport: myTransport)
let face = try FaceFile(data: fileData)
try await WatchfaceInstaller().install(face, authKey: band.authKey, session: session) { phase in
    print(phase)   // .authenticating, .uploading(sent:total:), .activating, .done(...)
}
```

Сесію **завжди закривайте** й відключайтеся: інакше браслет лишається в цій сесії, і Mi Fitness не може підключитися.
`WatchfaceInstaller` робить це сам, навіть після помилки.

## Важливі особливості Band 10

- Кожен кадр браслета телефон підтверджує одразу (так робить і офіційний застосунок). Повтор кадру означає,
  що підтвердження загубилося, — його надсилають ще раз.
- Частини файлу йдуть вікном до 12 непідтверджених; якщо браслет 3 с мовчить, непідтверджені частини надсилаються повторно.
- Прийнявши файл, браслет сам вмикає новий циферблат і надсилає 4/5 (статус 3 — прийнято).
- Відразу після автентифікації браслет може надіслати запити до компаньйона (`2/42`, `17/7`, погода `10/3`);
  відповідати на них не обов'язково, достатньо підтвердити кадри.
- Чужу сесію (Mi Fitness) бібліотека не закриває. Про те, що браслет працює з іншим застосунком,
  повідомляє `Configuration.onOtherApp`.
- Шифрування CTR щоразу починається з IV = ключ; лічильник не продовжується між кадрами.
- Журнал (`BandSession.Configuration.log`) не містить ключів і вмісту команд автентифікації.

## Тести

```sh
swift test
```

Тест-вектори (CRC, HKDF, HMAC, CTR, CCM, protobuf, потік файлу) отримано незалежною реалізацією на Python
з бібліотекою `cryptography`: `python3 Tools/generate_vectors.py`. `SessionTests` проганяє весь сценарій
встановлення на імітації браслета, яка, як Band 10, не надсилає більше 6 непідтверджених кадрів.

## Що не з'ясовано

- Смисл полів інформації про телефон (застосунок BandFace передає ті самі значення, що й офіційний застосунок).
- Для палітрового прев'ю з RLE припускається, що стиснення охоплює і палітру, і індекси.
