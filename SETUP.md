# 墨屏阅读 — E-ink Reader (Flutter + WebView Engine + Android EPD Plugin)

**English | [简体中文](SETUP.zh-CN.md)**

The e-ink reader implemented as a five-layer architecture, targeting Android only (with a Chrome debugging channel).

```
L1  Flutter Shell (Dart)      Bookshelf / Settings / Notes / Reader container
L2  Bridge Layer              MethodChannel (EPD) + JS Handlers (unified JSON envelope)
L3  WebView Engine (TS)       in-house EPUB/TXT engine: parsing / pagination / themes / gestures / highlights
L4  Android Native (Kotlin)   EpdRefreshPlugin (Boox / Hisense / Moaan reflection adapters)
L5  Data Layer                sqflite library + sandbox files + shared_preferences
```

## 1. Quick Start

### 0. Requirements
- Flutter ≥ 3.19 (Dart ≥ 3.3)
- Android SDK 34, minSdk 23 (covers common older Boox/Hisense/Moaan models)
- Engine build: Node ≥ 18 + pnpm (or npm)

### 1. First run (no engine build needed, works out of the box)

The repo ships a **build-free fallback engine** (`assets/web/main.js`, vanilla JS, TXT only).
It runs right after `flutter pub get`:

```bash
flutter pub get
flutter run -d <android-device>   # real device / emulator
flutter run -d chrome             # Chrome debugging (shell + TXT only, see §4)
```

A sample book "Ink Folio · Sample Book" with 8 chapters is preloaded on the shelf to verify
pagination / TOC / progress restore / highlights / theme switching end to end.

### 2. Enable the EPUB engine (build the TS bundle)

```bash
# Linux/macOS
./build_web.sh
# Windows
.\build_web.ps1
```

Each script does `cd web_engine && pnpm install && pnpm build && cp -r dist/* ../assets/web/`.
The output overrides the fallback engine; re-run the app and EPUB is supported.

### 3. Build the APK

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

> If the first build fails with gradle wrapper errors (the repo doesn't include the
> `gradle-wrapper.jar` binary), run `flutter create --platforms=android .` in the project
> root to regenerate the scaffolding, then build again — existing files are not overwritten.

## 2. Directory Structure

```
ebook_reader/
├── android/                        # L4: gradle + EpdRefreshPlugin.kt + MainActivity.kt
├── assets/
│   ├── web/                        # engine output (currently the build-free fallback engine)
│   ├── books/sample.txt            # sample book
│   └── fonts/                      # drop-in directory for bundled fonts (optional, see notes file)
├── lib/
│   ├── main.dart / app.dart        # entry + grayscale ThemeData + instant routes
│   ├── bridge/
│   │   ├── bridge_protocol.dart    # unified JSON envelope + action/event constants
│   │   ├── js_bridge.dart          # Dart↔TS two-way bridge + WebView settings
│   │   └── epd_channel.dart        # e-ink refresh MethodChannel
│   ├── features/
│   │   ├── shelf/                  # bookshelf (import / delete / placeholder covers)
│   │   ├── reader/                 # ReaderPage + controller + chrome/TOC/highlight menu
│   │   ├── settings/               # reading settings (font size/line height/theme/font/refresh rate)
│   │   └── annotation/             # global notes list
│   ├── data/                       # models / sqflite / dual-platform repositories
│   ├── services/                   # book import / font manager / web asset copying
│   └── theme/                      # grayscale theme + PageRouteBuilder(Duration.zero)
├── web_engine/                     # L3: TypeScript project (Vite + jszip)
├── build_web.sh / build_web.ps1
└── pubspec.yaml
```

## 3. Bridge Protocol (Dart ↔ TS)

Unified envelope: `{ action, payload, requestId? }`.
Dart→TS: `window.__reader.dispatch(msg)`; TS→Dart: `callHandler('event', msg)`.

| Dir | Name | Payload | Purpose |
|---|---|---|---|
| ↓ | openBook | `{bookId, kind, filePath, text?, cfi?, start?, highlights?}` | open a book; TXT content may be inlined (required on web) |
| ↓ | applyTheme | `{mode, fontSize, lineHeight, fontFamily, fontPath?}` | live theme/font changes |
| ↓ | scrollToPercent | `{percent}` | jump by percentage |
| ↓ | scrollToOffset | `{start}` | global character offset (TXT/EPUB TOC & highlight jump) |
| ↓ | scrollToCfi | `{cfi}` | EPUB locator `<spineIndex>#<anchor>` (TOC & internal links) |
| ↓ | nextPage / prevPage | `{}` | page turn |
| ↓ | addAnnotation | `{id, start?, end?, cfiRange?, color}` | render highlight |
| ↓ | removeAnnotation | `{id}` | remove highlight |
| ↓ | exportAnnotations | `{}` | request current annotations back |
| ↑ | onReady | — | bridge handshake complete |
| ↑ | onMeta | `{title, author}` | metadata |
| ↑ | onToc | `{items:[{title, offset?, cfi?}]}` | table of contents |
| ↑ | onPageChanged | `{percent, cfi?, start?, chapter?, index, total}` | page rendered (triggers Dart progress save + full refresh) |
| ↑ | onLongPress | `{text, start?, end?, cfiRange?}` | selection reported → Flutter shows highlight menu |
| ↑ | onToggleChrome | — | center tap → Flutter shows/hides top/bottom bars |
| ↑ | onNeedRefresh | `{type: 'full'\|'partial'}` | EPD refresh request |

**Critical ordering (do not invert)**: TS finishes rendering → `onPageChanged` → Dart `EpdChannel.full()` → native full refresh.

## 4. E-ink Adaptation Checklist

| Item | Implementation |
|---|---|
| Grayscale theme | `AppTheme`: pure black/white/gray, `elevation=0`, `NoSplash.splashFactory`, no transition animations |
| Page transitions | `instantRoute`: `PageRouteBuilder(transitionDuration: Duration.zero)` |
| Full refresh on page turn | `onPageChanged` → `EpdChannel.full()`; closing TOC/settings → full; highlights/menus → partial |
| Ghosting avoidance | engine CSS globally sets `transition/animation: none`, no gradients/blur/shadows; hard page cuts (instant transform jumps) |
| Chrome show/hide | hidden by default, center tap pops it up, one partial refresh each time it appears/disappears |
| Fonts | drop Source Han Serif/Sans into `assets/fonts/` → FontManager copies to sandbox → injected via @font-face |
| WebView | animation options disabled, transparent background, zoom/scroll disabled, file access enabled (reads books/fonts from the same sandbox) |
| Refresh mode | settings panel offers "full refresh every N pages" for flicker-sensitive devices |

## 5. EPD Refresh Plugin (EpdRefreshPlugin.kt)

Vendors expose no unified public API, so the plugin uses a "candidate classes + reflection + try each" strategy:

- **Boox/Onyx**: `com.onyx.android.sdk.device.EpdController` / `EpdDeviceManager` / `DeviceInfoSingleton`
- **Hisense**: `com.hisense.epd.Epd` / `com.hisense.android.graphics.EPDManager`
- **Moaan**: reuses the Boox candidates (same kernel lineage), falls back to the generic path on failure
- **Generic fallback**: `decorView.invalidate()` (equivalent to a partial refresh under the default mode)
- `isEink()`: whitelist-matches `Build.MANUFACTURER`; on non-e-ink devices the Flutter side goes silent automatically.

If you obtain an official vendor AAR SDK, replace the reflection branch in `resolveEntry()` — the Dart protocol stays unchanged.
**Note**: reflection adapters must be verified on real devices (emulators have no EPD controller).

## 6. Platform Differences & Known Limits

1. **Web (Chrome)**: uses the `flutter_inappwebview` v6 web implementation (iframe).
   - The TXT engine works (content passed inline in the payload); the EPUB engine does not (file:// unreachable on web).
   - sqflite is unavailable on web: the `Repositories` factory automatically switches to SharedPreferences + in-memory implementations.
   - Debugging entry point: `flutter run -d chrome`.
2. **EPUB engine**: in-house implementation (JSZip for zip + native DOMParser for OPF/NCX/NAV) — no third-party black box; key calls are wrapped in try/catch
   so engine failures never take down the shell — errors surface through the `onError` event.
3. **TXT progress**: stored on dual tracks (character offset + percentage); after re-layout it is restored
   approximately by percentage (error ≤ 1 page).
4. **Binaries not delivered with the package**: `gradle-wrapper.jar` (regenerate with `flutter create .`),
   font files (drop into `assets/fonts/` yourself), vendor EPD AARs (as needed).
5. This repo has not been compiled on real hardware (source delivered as agreed); `web_engine` requires `pnpm install` first.

## 7. Suggested Verification Checklist (self-test after building)

- [ ] Shelf: sample book appears, import TXT/EPUB, long-press to delete
- [ ] Reading: hard page cuts with no animation, center tap opens/closes the menu (one refresh each)
- [ ] TOC: TXT chapter detection and jumps; EPUB TOC (NAV / NCX)
- [ ] Highlights: selection → highlight/note → highlight rendered → restored after restart
- [ ] Settings: font size / line height / three grayscale themes / fonts take effect instantly
- [ ] Progress: precise restore after quit and re-enter (TXT percentage, EPUB CFI)
- [ ] Real e-ink device: full refresh visible on page turns, no ghosting accumulation, no color ripples / scroll glow

## Documentation

- [README.md](README.md) — English project overview
- [README.zh-CN.md](README.zh-CN.md) — 中文版项目总览
- [SETUP.zh-CN.md](SETUP.zh-CN.md) — 本文档中文版
