# BeeCount OH (BeeCount for HarmonyOS) &nbsp; [中文](README.md)

<div align="center">

![Platform](https://img.shields.io/badge/platform-HarmonyOS-0A59F7?logo=harmonyos)
![Framework](https://img.shields.io/badge/Flutter-3.27.5--ohos-02569B?logo=flutter)
![License](https://img.shields.io/badge/license-BSL%201.1-orange)
![Release](https://img.shields.io/badge/release-v0.4.1-green)

**Unofficial third-party HarmonyOS port of BeeCount**

</div>

---

> ⚠️ **Not affiliated with the official project**
>
> This repository is an **unofficial third-party port** of [BeeCount](https://github.com/TNT-Likely/BeeCount). It is **not affiliated with, endorsed, or authorized by the original authors**.
>
> The official release supports Android / iOS / Web only. This repository ports the upstream open-source code to **HarmonyOS**. Feature trade-offs, UI adjustments, and bugs introduced by the port are maintained independently here — **please do not report port-specific issues to the official repository**.

---

## 📖 About

BeeCount is a lightweight bookkeeping app focused on data ownership: offline-first, no ads, no tracking. This port runs the upstream 3.8.6 Flutter codebase on HarmonyOS devices via Flutter-OH (the CPF-Flutter adaptation). The database schema, business logic, and most of the UI stay identical to upstream.

| Item | Value |
|---|---|
| Upstream baseline | [TNT-Likely/BeeCount](https://github.com/TNT-Likely/BeeCount) `main` (after tag `3.8.6`) |
| Framework | CPF-Flutter `flutter_flutter` tag `3.27.5-ohos-1.0.8` |
| Target platform | HarmonyOS (API 12+, `compatibleSdkVersion 5.0.0(12)`) |
| App ID | `com.example.myapplication` (placeholder bundleName; replace with your own AGC package name before release) |

## ✨ Current Status

Verified on a real HarmonyOS 7.0 device as of v0.4.1:

**✅ Ported**

- Full core bookkeeping: expense / income / transfer, multiple ledgers & accounts, two-level categories, tags, recurring transactions
- Charts (fl_chart, with category ranking / tag ranking) and annual report
- CSV import/export, multi-currency with conversion
- Cloud sync: BeeCount Cloud (self-hosted server, push/pull verified on device), WebDAV / S3 (code ready)
- AI-powered bookkeeping: chat bookkeeping / agent ledger queries / cloud OCR (Zhipu GLM / OpenAI, bring your own keys)
- JiQi-style transaction list (swipe to edit/delete, detail sheet) and single-page bookkeeping UI
- Drift database via the sqflite OHOS RDB driver — 25 tables (schemaVersion 33), identical to upstream

**❌ Not available** (platform limitations or not yet ported; entries are hidden)

- Home-screen widgets, screenshot auto-bookkeeping, voice bookkeeping, on-device OCR
- iCloud sync, App Intents, in-app update
- Notifications / voice reminders / lock-screen access / poster sharing

## 🔨 Build

### Requirements

| Component | Version |
|---|---|
| Flutter-OH SDK | [CPF-Flutter/flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter) tag `3.27.5-ohos-1.0.8` |
| DevEco Studio | 26.0.0+ (SDK API 26; older API 22 SDKs fail to compile) |
| Dart | 3.6.x (bundled with Flutter-OH) |

See [tool/ohos/README.md](tool/ohos/README.md) for environment setup details and pitfalls.

### Steps

```powershell
# 1. Inject OHOS-only dependency overrides (not committed; does not affect Android/iOS builds)
Copy-Item tool\ohos\pubspec_overrides.yaml.template pubspec_overrides.yaml

# 2. Configure signing (choose one)
#    a) In DevEco Studio: File > Project Structure > Signing Configs > automatically generate signature
#    b) Copy ohos\build-profile.json5.template to ohos\build-profile.json5 and fill in your own signing materials

# 3. Build
flutter pub get
flutter build hap --debug

# 4. Install on a device
hdc install -r build\ohos\hap\entry-default-signed.hap
```

> ⚠️ If present, `pubspec_overrides.yaml` **wholly replaces** the `dependency_overrides` section of `pubspec.yaml`; the upstream pins are mirrored in the template.

## 📦 Syncing with upstream

- This repository's `main` is the port development line; versions carry a `v` prefix to distinguish from upstream (no prefix). See [docs/VERSIONING.md](docs/VERSIONING.md)
- To follow upstream changes, `git fetch <upstream remote>` and merge; watch for conflicts in `pubspec.yaml` version fields and dependency changes

## 📄 License

- Upstream code is licensed under the [BeeCount Software License (BSL 1.1)](LICENSE): **free for non-commercial use; commercial use requires the original author's permission**. This port does not change the upstream license and follows the same terms
- Port-specific additions (the `ohos/` native layer, `tool/ohos/` build scripts, docs) are published under the same license

## 🙏 Credits

- [BeeCount](https://github.com/TNT-Likely/BeeCount) — the official project and its author
- [CPF-Flutter](https://gitcode.com/CPF-Flutter) — the Flutter HarmonyOS adaptation and plugin ecosystem
