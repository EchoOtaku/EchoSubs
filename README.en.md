# EchoSubs

[简体中文](README.md) | **English**

A local-first subscription ledger for Windows and Android. Keep domains, servers, object storage, streaming memberships, and other subscriptions together, with clear renewal dates, billing cycles, and payment history.

No EchoSubs account or dedicated application server is required. Direct LAN sync and encrypted WebDAV sync can be enabled independently or used together. The application UI is currently in Simplified Chinese.

## Features

- **Subscription management:** categories, providers, prices, currencies, renewal methods, billing cycles, entitlement dates, notes, and archiving.
- **Overview and calendar:** upcoming renewals, overdue items, sync risks, search, and category filters.
- **Costs and payments:** fixed, metered, and lifetime subscriptions; separate monthly/yearly estimates and actual payments, grouped by currency.
- **Renewals:** record payments and gifted time separately, keeping entitlement expiry and the next renewal date distinct.
- **Two sync transports:** mutually confirmed LAN pairing, encrypted HTTPS WebDAV sync, and explicit conflict handling.
- **Backup and recovery:** encrypted backups, recovery keys, restoration into a separate ledger, and explicitly confirmed plaintext export.
- **Adaptive UI:** desktop sidebar, mobile navigation, light/dark themes, large text, and keyboard support.

The auto-renew flag is informational. It does not make payments, create payment records, or extend confirmed entitlements. Metered subscriptions and unknown prices are excluded from fixed recurring cost estimates.

## Download and install

Download from [Releases](https://github.com/EchoOtaku/EchoSubs/releases). Access to this private repository requires an authorized GitHub account.

| Platform | Installation | Reminders |
| --- | --- | --- |
| Windows x64 | Extract the entire ZIP and run `echo_subs.exe`; keep its DLLs and `data` directory together | In-app reminders while the app is running in the foreground; no background process or Windows toast after closing |
| Android 7.0 / API 24 or later | Install the APK; update an existing installation with the same signing certificate | Notification permission is required; force-stop and battery restrictions can delay or block reminders |

The current APK uses a **local test signing certificate**, not a production/store certificate. Updates require the same certificate. Do not uninstall an existing ledger to update it. If Windows reports a missing MSVC runtime, follow the [Flutter Windows deployment instructions](https://docs.flutter.dev/platform-integration/windows/building#distributing-windows-apps).

## Getting started

1. Add a subscription with its price, currency, billing cycle, entitlement dates, and provider.
2. Record actual payments in Payments or the subscription details. Record gifted time separately.
3. Open Settings → Backup and recovery, save the recovery key, and export an encrypted backup. Store the key separately from the backup.
4. Enable sync if needed. LAN pairing requires both apps to be running and their short codes to match. WebDAV requires your own HTTPS endpoint and credentials.
5. Review the ledger time zone, reminder rules, and permissions. Sync status and reminder scheduling status are shown separately.

Sync is not a substitute for backups. A change that has not reached another device cannot affect that device's reminders. If all devices and the recovery key are lost, encrypted backups cannot be decrypted.

## Data and privacy

- Business data is stored locally in SQLite. Keys and credentials use operating-system secure storage.
- Sync objects and encrypted backups use application-layer encryption. This is **not full-database encryption of the local SQLite file**; protect the device account and disk separately.
- Databases, recovery keys, private signing keys, credentials, personal exports, and local logs must stay out of Git and release assets.
- Tests use fictional data. Release checks cover current files, Git history, and packages; pattern-based scanning is not proof that every possible disclosure is absent.

See the [release audit record](docs/security/release-audit.md) for scope and findings.

## Development

Flutter is pinned in [`.flutter-version`](.flutter-version); dependencies are locked in `pubspec.lock`. With Flutter and the Windows C++ toolchain or Android SDK available, run from the project root:

```sh
flutter pub get
flutter test
flutter analyze
flutter build windows --release
flutter build apk --release
```

Alternatively, run `scripts/verify.ps1 -Stage unit`, or select `windows` or `android` for the respective platform. Android integration tests must use the [isolated runner](integration_test/support/run_native.ps1) and the separate `.integration` package. Never uninstall or clear the main app for testing.

Keep the default dependency/plugin generation steps for release builds. After an integration run, `--no-pub` can leave a development plugin in the generated registrant. See [build requirements](docs/build/toolchain.md).

## Documentation and validation

- [Builds and artifact verification](docs/build/release.md)
- [Acceptance evidence and limitations](docs/build/acceptance.md)
- [UI conventions](docs/design/ui-refresh.md)
- [Encrypted envelope protocol](docs/protocol/envelope-v1.md) / [Merge and conflict rules](docs/protocol/merge-v1.md)
- [Historical product design](docs/superpowers/specs/2026-10-19-echosubs-design.md) / [Historical implementation plan](docs/superpowers/plans/2026-10-30-echosubs-v1.md)

The current application passed 363 automated tests and four native offline-flow tests on each of Windows and MuMu Android 12/API32. Notification delivery, Android 13+/OEM devices, physical LAN/camera operation, vendor WebDAV interoperability, and the Windows OS file picker retain separate acceptance limitations. Emulator and controlled-test results do not establish complete coverage of those environments.
