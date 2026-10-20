# AGENTS.md

Long-term working rules for AI coding agents (and human contributors) in this repository.
For user-facing documentation see [`README.md`](README.md) / [`README_zh.md`](README_zh.md).

## 1. Project Overview

**SignalScope** is a Flutter + Dart + Kotlin Android app that inspects the device's network and positioning signals:

- SIM / carrier information (multi-SIM, each subscription handled independently)
- Cellular signal: LTE, 5G NR (NSA/SA detection), and legacy GSM/WCDMA/TD-SCDMA/CDMA values when the system reports them
- Wi-Fi connection details, nearby access points, and a 2.4 / 5 / 6 GHz channel graph
- GNSS location and satellites (constellations, sky plot, C/N0 chart)
- IPv4 / IPv6 / MAC display where the OS allows it
- A TCP-handshake / DNS latency test (not ICMP ping)
- An in-app updater that checks / downloads the latest GitHub Release (section 8 lists its limits)
- Signal history charts, CSV / JSON export, settings, and a session-only demo mode

Facts you should rely on (verify in `pubspec.yaml` and `android/` before changing):

| Item | Value |
| --- | --- |
| Android package | `com.signalscope.app` |
| `minSdk` | 29 (Android 10); `compileSdk` / `targetSdk` follow the Flutter default |
| Dart / Flutter | `sdk: ^3.13.5` (Flutter 3.47.x at the time of writing) |
| State management | Riverpod 3.x (`flutter_riverpod`) |
| Charts | `fl_chart` plus custom `CustomPainter` charts |
| UI | Material 3, dark theme preferred, built-in zh/en string table |
| Flutter plugins | **None** besides the SDK itself (see below) |
| Windows | UI shell only: no cellular / Wi-Fi / GNSS collection |
| Web / other | Not supported (the `web/` folder is the untouched Flutter scaffold) |

The app uses **no Flutter plugins** for storage, export, permissions, or opening system settings. These go through native Android channels (Kotlin) or `dart:io` (Windows shell). Do not add a plugin to "simplify" this without the maintainer's approval.

## 2. Architecture

### 2.1 Flutter structure (feature-first + repository layering)

```
lib/
  main.dart, app.dart        Entry point and MaterialApp (theme, locale, shell)
  core/                      Cross-cutting code
    providers.dart           Platform / settings / history providers
    lifecycle.dart           Foreground + page-visibility gating of sensors
    history.dart             In-memory ring buffer (5 min, <= 700 points per series)
    demo_mode.dart           Session-only demo mode switch
    theme/                   app_theme.dart (SignalColors, dark + light themes)
    i18n/                    strings_zh.dart, strings_en.dart, strings.dart (context.tr)
    utils/                   band_lookup, signal_quality, wifi_utils, throttle, format, network_type
  data/
    models/                  Immutable models; null means "the system did not report it"
    platform/                SignalPlatform abstraction + implementations
  features/<feature>/        overview, cellular, wifi, gnss, latency, settings,
                             permissions, export, shell, monitoring
    data/                    Repository (talks to SignalPlatform / dart:io)
    application/             Notifier / controller (Riverpod)
    presentation/            Pages and feature widgets
  shared/widgets/            Reusable cards, gauges, trend charts, monitor bar, address widgets
test/                        Unit and widget tests (see section 6)
```

Dependencies flow one way: `presentation` -> `application` -> `data` (repository) -> `data/platform`. Models are shared. Do not call a platform channel from a widget.

### 2.2 Platform abstraction

`SignalPlatform` (`lib/data/platform/signal_platform.dart`) is the only boundary to the device:

- `AndroidPlatform`: talks to Kotlin via channels.
- `UnsupportedPlatform`: Windows / other. Reports "not supported" and never fabricates data.
- `DemoPlatform`: deterministic, clearly fictional data, enabled only by the user in Settings.

`realPlatformProvider` is overridden in `main()` with the platform chosen by `platform_factory.dart`; `signalPlatformProvider` selects real vs. demo. Tests override the provider with `FakeAndroidPlatform` (`test/fakes.dart`).

### 2.3 Kotlin modules

All in `android/app/src/main/kotlin/com/signalscope/app/`:

| File | Responsibility |
| --- | --- |
| `MainActivity.kt` | Registers the channels |
| `NativeChannelHandler.kt` | `MethodChannel` and the four `EventChannel`s; listener lifecycle |
| `PermissionService.kt` | Runtime permissions, system location switch, settings intents |
| `SimInfoService.kt` | Active subscriptions (multi-SIM) |
| `CellularService.kt` | `TelephonyCallback` (API 31+) / `PhoneStateListener` (API 29-30) + `CellInfo` |
| `WifiSignalService.kt` | Connection info, cached scan results, change listeners, throttled `startScan` |
| `GnssService.kt` | `LocationManager` + `GnssStatus.Callback` |
| `NetworkAddresses.kt` | IPv4 / IPv6 from `LinkProperties`; per-SIM matching; real MAC only |
| `ExportService.kt` | Writes exports to `MediaStore.Downloads` |
| `UpdateInstaller.kt` | Installed version / ABIs, private download dir, pre-install checks (SHA-256, package, newer version, same signing key), opens the system installer through a `FileProvider` limited to `cache/updates` |
| `NativeUtils.kt` | Small shared helpers |

### 2.4 MethodChannel / EventChannel contract

| Channel | Type | Purpose |
| --- | --- | --- |
| `signalscope/method` | MethodChannel | Capabilities, permissions, SIM list, one-shot Wi-Fi query / scan request, settings read/write, export |
| `signalscope/cellular` | EventChannel | Per-subscription cellular snapshots and SIM-change events |
| `signalscope/wifi` | EventChannel | Current Wi-Fi connection changes |
| `signalscope/wifi_scan` | EventChannel | New scan results published by the system |
| `signalscope/gnss` | EventChannel | Location + satellite status |

Rules:

- Register native listeners in `onListen`, unregister in `onCancel`; also release everything when the Flutter engine is destroyed.
- A channel name, method name, or payload key is a contract between `*.kt` and `lib/data/platform/android_platform.dart` / `lib/data/models/`. Change both sides together and update the tests (`test/android_platform_test.dart`, model tests).
- Missing values cross the channel as `null`, never as `0`, `-1`, or `Integer.MAX_VALUE`.

### 2.5 State management and data flow

```
Android callback -> Kotlin service (merge 200-300 ms) -> EventChannel
  -> AndroidPlatform stream -> Repository -> Controller (Notifier)
  -> KeyedThrottle (user-selected refresh interval; leading + trailing)
  -> UI state + HistoryBuffer -> Widgets (ref.watch)
```

- Controllers are Riverpod `Notifier`s (some `autoDispose`). Prefer `ref.watch` in widgets, `ref.listen` for side effects.
- Sensors listen only while the app is in the foreground **and** the relevant page is visible (`lib/core/lifecycle.dart`). Keep it that way.
- Cellular state is keyed by subscription ID; data from one SIM must never appear under another.
- Persisted settings (`AppSettings`, including custom latency targets) are stored natively on Android and in `%APPDATA%\SignalScope\settings.json` on Windows.

## 3. Development Rules

1. **Follow the existing architecture.** New features go in `lib/features/<name>/{data,application,presentation}`; shared UI in `lib/shared/widgets/`.
2. **Keep changes small and focused.** One concern per change. Do not mix refactors with features or fixes.
3. **No new dependencies without need.** Do not add or bump packages, Gradle plugins, AGP, Kotlin, or Gradle versions unless the task requires it, and state why. Never ignore or regenerate `pubspec.lock` casually.
4. **No unrelated refactors, renames, formatting sweeps, or new files.** Do not delete existing files unless asked.
5. **No duplicate implementations.** Search for an existing helper (`core/utils/`, `shared/widgets/`, models) before writing one.
6. **No hard-coded sensitive configuration.** No keys, tokens, passwords, signing material, or personal paths in source, docs, or tests.
7. **Strings:** user-visible text goes through `context.tr('key')` with entries in **both** `strings_zh.dart` and `strings_en.dart`. `test/i18n_test.dart` enforces key parity and that every literal key exists.
8. **Derived values** may only use documented formulas (for example ECI >> 8, Wi-Fi percent from RSSI, channel from frequency, mean C/N0, unique-band EARFCN lookup). Label them as computed in the UI and document the formula.
9. **Generated and local files** (`build/`, `.dart_tool/`, `android/local.properties`, `GeneratedPluginRegistrant.java`, `windows/flutter/ephemeral/`) are not hand-edited and not committed.
10. **Version bump goes with the tag.** The release workflow (`android-release.yml`) takes the APK `versionName` from the git tag, but local builds and the Windows fallback use the values in source. Before creating a release tag `vX.Y.Z`, commit a version bump so these match, and tag that commit:
    - `version:` in `pubspec.yaml` -> `X.Y.Z+N` (the build number `N` only matters for local builds; CI overrides it with `--build-number=${{ github.run_number }}`);
    - `kAppVersion` in `lib/core/app_info.dart` -> `'X.Y.Z'`.

    Never tag first and bump afterwards. If a tag was placed too early and has not been pushed, move it to the bump commit; never move or delete a tag that has been pushed without the maintainer's approval.

## 4. Android Native API Rules

- **Public SDK APIs only.** No hidden APIs, no reflection into framework internals, no root, no `@hide` access, no shelling out to system tools.
- **Strict SDK checks.** Guard every API with `Build.VERSION.SDK_INT` (`minSdk` is 29) and give API 29/30 a working fallback when the newer API is missing.
- **Correct permissions.** Declare in `AndroidManifest.xml` only what the code uses, and check them at runtime before the call. Current set: `READ_PHONE_STATE`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `NEARBY_WIFI_DEVICES`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_NETWORK_STATE`, `INTERNET` (latency test and the update check / download only), `REQUEST_INSTALL_PACKAGES` (hand the downloaded SignalScope update to the system installer). Hardware features (telephony, Wi-Fi, GPS) stay `required=false`.
- **Do not bypass system limits.** Wi-Fi scan throttling, `CellInfo` update frequency, location-gated SSID/BSSID, and the Android 10+ MAC restriction are respected and explained in the UI.
- **Never fake signal data.** No random numbers or constants in real mode. If a field is unavailable, return `null` and show `--` with a reason. In particular:
  - `Integer.MAX_VALUE` / `UNAVAILABLE` -> `null`;
  - the placeholder MAC `02:00:00:00:00:00` is never displayed;
  - NSA must not be shown as NR data; SA is declared only when the data network type is NR.
- Distinguish **system-reported** values from **derived** values (section 3, rule 8).
- Listeners are registered only on demand and always unregistered; no polling loops for cellular, Wi-Fi, or GNSS.

## 5. Flutter UI Guidelines

- Use the theme in `lib/core/theme/app_theme.dart` (`SignalColors`, Material 3 color scheme). Do not hard-code colors per widget when a theme color exists. Dark theme is the default look; light and system modes must also work.
- Reuse components from `lib/shared/widgets/` (cards, gauges, trend chart, monitor bar, address widgets) and the page scaffold before creating new ones.
- Layouts must be responsive: no fixed pixel sizes that overflow on small phones, large text scale, or landscape. Lists that can grow must be lazy.
- Chart geometry that can be tested (for example `channel_geometry.dart`) stays separate from painting code.
- Signal-quality colors are a reference grading only; always show the original numeric value and unit.
- Emoji flags for constellations come from ISO region codes; SBAS uses a globe, not a single flag.

## 6. Testing and Validation

Run from the repository root before declaring work done:

```bash
dart format lib test
flutter analyze
flutter test
flutter build apk --release --split-per-abi   # when Android code, manifest, or Gradle files changed
```

- CI (`.github/workflows/flutter-ci.yml`) runs the same checks plus a debug APK build, with Flutter and JDK versions pinned in the workflow `env`. Update those pins deliberately when the project's Flutter / AGP / Gradle requirements change.
- `flutter analyze` must report no issues (`analysis_options.yaml` uses `flutter_lints`; `android/`, `web/`, `windows/`, `build/` are excluded).
- Add or update tests with behavior changes. Platform behavior is tested through `FakeAndroidPlatform`, not real hardware.
- **Never claim a check passed if you did not run it.** If you could not run something (no device, no SDK, no network), say so explicitly. Native sensor behavior on real multi-SIM / 5G hardware is not covered by the automated tests.

## 7. Documentation Guidelines

- Docs must match the source. Describe only implemented behavior; do not present unfinished ideas as features. If planned work is documented, mark it clearly as planned.
- Update `README.md` **and** `README_zh.md` together when you change: features, supported platforms / Android versions, permissions, build steps, or project structure. Keep the two files structurally identical.
- Update this file only for long-term rules (architecture, conventions, constraints). Do not record chat history, temporary plans, or task notes here.
- Do not describe third-party products as affiliated with this project, and do not add unverified badges, screenshots, download links, or release claims.
- License files (`LICENSE`, `NOTICE`, `ATTRIBUTION.md`) are not edited casually. The license is CC BY-NC-SA 4.0 by the maintainer's explicit choice; do not replace or "fix" it.

## 8. Security Rules

- Never commit: `.env*` (except `.env.example`), `*.jks`, `*.keystore`, `*.p12`, `*.pfx`, `*.pem`, `key.properties`, `google-services.json`, API keys, tokens, passwords, private certificates, or any local machine paths.
- `android/local.properties` is local-only (it holds SDK paths) and is git-ignored.
- Release signing: the `release` build type is signed only with the real release key, read from `ANDROID_KEYSTORE_PATH` / `ANDROID_STORE_PASSWORD` / `ANDROID_KEY_PASSWORD` / `ANDROID_KEY_ALIAS` or the git-ignored `android/key.properties`. Gradle fails the release build when these are missing; never add a fallback to the debug key. The key lives outside the repository; in CI it comes only from the `production` environment secrets and is used only by the `build` job of `android-release.yml`. Never regenerate or rotate the key casually: it breaks upgrades for installed apps.
- If you find a suspected real secret, stop, do not copy it into output, and report it. Adding a path to `.gitignore` does not erase it from Git history; a leaked secret must be rotated.
- `INTERNET` is used only by (1) the latency test after the user taps start, and (2) the updater (`lib/features/update/`). Do not add other network calls, analytics, or uploads. Exported files stay on the device.
- Updater limits (maintainer-approved exception to "no network calls"; keep them):
  - Only anonymous `GET`s of GitHub Releases for `kUpdateRepo`, over HTTPS to `github.com` / `*.githubusercontent.com` (`githubOnlyPolicy`, applied to every redirect). The only identifying data is the app version in the `User-Agent`; never send device identifiers.
  - The automatic check runs at most once per 24 h at launch and must stay switchable in Settings (`autoCheckUpdates`). Stable releases only; drafts and pre-releases are ignored.
  - An APK is installed only after its SHA-256 matches `SHA256SUMS.txt` of the same release, and `UpdateInstaller` confirms the package name, a higher version code and the installed app's signing certificate. If a check cannot be done, fail closed. The user confirms in the system installer; the app never installs silently.
  - Release asset names (`signalscope-<tag>-<abi>.apk`, `SHA256SUMS.txt`) are produced by `android-release.yml`; change both sides together.

## 9. Agent Working Guidelines

1. **Understand first.** Read the relevant feature folder, its tests, and the Kotlin service before editing.
2. **Analyze scope.** List the files a change touches (Dart, Kotlin, manifest, strings, tests, docs) and keep to them.
3. **Reuse modules.** Extend existing controllers, models, and widgets instead of adding parallel ones.
4. **Stay backward compatible.** Keep channel contracts, settings keys, and export formats working, or migrate them deliberately.
5. **Verify.** Run the commands in section 6 and fix what you broke.
6. **Report clearly.** State what changed, what was verified (and how), what was not verified, and any open risks or assumptions.
