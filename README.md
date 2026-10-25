<div align="center">

# BandFace

**Install custom watch faces on Xiaomi Smart Band 10 straight from your iPhone.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![iOS 16+](https://img.shields.io/badge/iOS-16%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
[![Build IPA](https://github.com/hunt2121/iosmiface/actions/workflows/build.yml/badge.svg)](https://github.com/hunt2121/iosmiface/actions/workflows/build.yml)

**English** · [Українська](README.uk.md) · [Русский](README.ru.md)

</div>

---

BandFace is a small SwiftUI app that uploads `.face` / `.bin` watch face files to a **Xiaomi Smart Band 10** over Bluetooth LE — no computer, no Android phone, no third-party servers.

## Features

- **One-tap install.** Pick a watch face file, tap *Install on band* — the band receives the file and switches to the new face by itself.
- **Preview before installing.** The app shows the face's preview image, name, ID and size.
- **Auth key found automatically.** Choose the *Mi Fitness* folder in the Files app once; the key is re-read on every launch.
- **Remembers your band** and reconnects automatically.
- **Works alongside Mi Fitness.** If Mi Fitness starts syncing in the background, the install waits and resumes; the log tells you when it happens.
- **Reliable transfer.** Every part of the file is acknowledged by the band; lost parts are resent.
- **Log** with an optional detailed mode (timestamps, raw protocol frames) — handy for bug reports.
- **Localized:** English, Ukrainian, Russian. Light and dark themes.
- **Private:** no network access, no analytics. The key is stored in the iOS Keychain.

## Requirements

| | |
|---|---|
| Phone | iPhone with iOS 16 or later |
| Band | Xiaomi Smart Band 10 (tested: model M2459B1, firmware 3.2.7) |
| Key | The band paired with **Mi Fitness** on the same iPhone (the app reads the band's auth key from Mi Fitness data) |

## Installation

BandFace is not on the App Store yet, so it is installed by sideloading:

1. Download `BandFace-v….ipa` from the **[latest release](https://github.com/hunt2121/iosmiface/releases/latest)**.
2. Install it with **[Sideloadly](https://sideloadly.io)** or **AltStore** using your Apple ID.
3. On the iPhone: *Settings › General › VPN & Device Management* → your Apple ID → *Trust*. On iOS 16+ also turn on *Settings › Privacy & Security › Developer Mode*.

With a free Apple ID the app must be re-signed every 7 days. Test builds of every commit are in **[Actions → Build IPA](https://github.com/hunt2121/iosmiface/actions/workflows/build.yml)** (GitHub sign-in required).

## Usage

1. **Key** tab → *Find automatically* → in the picker open *On My iPhone › Mi Fitness* → *Open*. The key appears with a green check mark.
2. **Watch faces** tab → connect to your band.
3. *Choose file* → pick a `.face` or `.bin` file → *Install on band*.

If something goes wrong, turn on **Developer mode** in the **Log** tab, repeat, and attach the copied log to an issue.

## How it works

The Bluetooth protocol lives in a separate Swift package, **[BandFaceKit](BandFaceKit)** (MIT). It was written from scratch from a code-free textual description of the protocol and refined using recordings of the band's own traffic:

- framed transport over GATT service `FE95` (TX `0x5F`, RX `0x5E`), CRC-16, per-frame acknowledgements;
- session setup and authentication with the band's auth key (HKDF/HMAC-SHA256, AES-CCM, AES-CTR);
- protobuf commands: install request, upload request, file transfer with MD5/CRC-32, install status.

## Building from source

```sh
brew install xcodegen
xcodegen generate
open BandFace.xcodeproj
```

Library tests: `swift test --package-path BandFaceKit`.

```
Sources/            the iOS app (SwiftUI)
BandFaceKit/        protocol library (Swift package, MIT)
.github/workflows/  CI: library tests + unsigned IPA
```

## License

- **BandFace** — [MIT](LICENSE).
- **BandFaceKit** — [MIT](BandFaceKit/LICENSE).
- The app uses only Apple system frameworks (SwiftUI, CoreBluetooth, CryptoKit, CommonCrypto, SQLite); there are no third-party dependencies.
- Versions before the switch to BandFaceKit (git history up to commit `67755ea`) contained code ported from Gadgetbridge and remain under **AGPL-3.0**.
- Watch face files belong to their authors. Install only faces you have the right to use.

## Disclaimer

BandFace is an independent project and is **not affiliated with, endorsed or sponsored by Xiaomi**. Xiaomi, Mi Fitness and Smart Band are trademarks of their respective owners. The software is provided "as is", without warranty — use it at your own risk.
