# 墨屏阅读 · Ink Folio

**[English](README.md) | 简体中文**

墨屏阅读是一款专为墨水屏设备打造的电子书阅读器。导入 TXT / EPUB 书籍，翻页即时无延迟，随手划线做笔记——全部以干净的黑白灰呈现，无任何动画，屏幕不留残影、不起闪。支持 Android，在 Boox、海信、墨案等主流墨水屏设备上开箱即用（全刷/局刷正确适配），在普通设备上则自动回退为常规显示，不做任何多余刷新。

**主要特性**

- 为墨水屏而生的阅读体验——无动画、无转场、无视觉噪点
- 书架管理：免权限导书、章节目录、阅读进度精确恢复
- 长按选区划线/写笔记，重启后高亮仍在，另有全局笔记一览
- 精细的屏幕刷新控制，最大限度减少墨水屏闪烁
- 字号、行距、灰阶主题、自定义字体随时可调

<details>
<summary>五层架构（L1–L5）</summary>

```
L1 Flutter 壳层(Dart)   书架 / 设置 / 笔记 / 阅读页容器
L2 桥接层               MethodChannel(EPD) + JS Handler(统一 JSON 信封)
L3 WebView 阅读引擎(TS)  自研 EPUB/TXT 引擎：解析 / 分页 / 主题 / 手势 / 高亮
L4 Android 原生(Kotlin)  EpdRefreshPlugin（Boox/海信/墨案 反射适配）
L5 数据层               sqflite 书库 + 沙盒文件 + shared_preferences
```

</details>

## 功能特性

- **墨水屏优先**：全黑白灰主题、零时长页面转场，无动画/发光/渐变/阴影——从设计层面规避残影。
- **全刷/局刷控制**：真机翻页触发全刷；支持「每 N 页一次全刷」设置，适配对闪屏敏感的机型。
- **TXT 与 EPUB**：仓库内置免构建 TXT 回退引擎，一条脚本即可构建完整的自研 EPUB 引擎（运行时依赖仅 npm 官方 jszip）。
- **划线笔记**：长按选区 → 划线/笔记，高亮持久化、重启恢复；全局笔记列表。
- **进度恢复**：TXT 与 EPUB 统一按全局字符偏移 + 百分比双轨存储（不再使用 CFI）。
- **内置字体**：思源宋体/黑体投放 `assets/fonts/`，`FontManager` 首次启动拷贝到沙盒并以 `@font-face` 注入引擎。
- **SAF 导书**：免存储权限。

## 环境要求

- Flutter ≥ 3.19（Dart ≥ 3.3）
- Android SDK 34、minSdk 23（覆盖 Boox/海信/墨案常见老机型）
- Node ≥ 18 + npm/pnpm（仅构建 EPUB 引擎时需要）

## 快速开始

### 1. 免构建引擎直接运行（开箱即跑）

仓库内置一份免构建回退引擎（`assets/web/main.js`，vanilla JS，仅 TXT）：

```bash
flutter pub get
flutter run -d <android设备>   # 真机 / 模拟器
flutter run -d chrome          # Chrome 联调（仅壳层+TXT，见「平台差异」）
```

书架已预置 8 章示例书《墨屏阅读 · 示例书》，可立即验证翻页 / 目录 / 进度恢复 / 划线 / 主题切换全链路。

### 2. 启用 EPUB 引擎（构建 TS 引擎产物）

```bash
# Windows
.\build_web.ps1
# Linux/macOS
./build_web.sh
```

脚本执行 `cd web_engine && 安装依赖 && 构建`，产物覆盖到 `assets/web/`。重新运行 App 即支持 EPUB。

### 3. 出 APK

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 若首次构建报 Gradle Wrapper 相关错误（仓库未附带 `gradle-wrapper.jar` 二进制），
> 在工程根执行 `flutter create --platforms=android .` 补齐脚手架后再构建，已有文件不会被覆盖。
> 注意：重建 `android/` **会覆盖**墨水屏原生定制文件（`EpdRefreshPlugin.kt`），操作前先阅读 `AGENTS.md`。

### 一键引导

`.\init.ps1`（Windows）：生成缺失的 android/web 平台目录 + `pub get` + `flutter analyze` + `flutter test`；重建 android 前会检查墨水屏定制文件并要求确认。

## 目录结构

```
├── android/                        # L4：gradle + EpdRefreshPlugin.kt + MainActivity.kt
├── assets/
│   ├── web/                        # 引擎产物（当前为免构建回退引擎）
│   ├── books/sample.txt            # 预置示例书
│   └── fonts/                      # 内置字体投放目录（可选，附字体说明）
├── lib/
│   ├── main.dart / app.dart        # 入口 + 灰阶 ThemeData + 瞬时路由
│   ├── bridge/                     # JSON 信封协议、Dart↔TS 桥、EPD MethodChannel
│   ├── features/
│   │   ├── shelf/                  # 书架（导入/删除/占位封面）
│   │   ├── reader/                 # 阅读页 + controller + 顶底栏/目录/划线菜单
│   │   ├── settings/               # 阅读设置（字号/行距/主题/字体/全刷频率）
│   │   └── annotation/             # 全局笔记列表
│   ├── data/                       # models / sqflite / 双平台仓库
│   ├── services/                   # 导书 / 字体管理 / web 资产拷贝
│   ├── core/ 与 theme/             # 公共辅助 + 灰阶主题与 Duration.zero 路由
├── web_engine/                     # L3：TS 阅读引擎（Vite + jszip）
├── build_web.sh / build_web.ps1    # 构建引擎产物到 assets/web/
└── pubspec.yaml
```

## 桥接协议（Dart ↔ TS）

统一信封：`{ action, payload, requestId? }`。
Dart→TS：`window.__reader.dispatch(msg)`；TS→Dart：`callHandler('event', msg)`。

| 方向 | 名称 | payload | 说明 |
|---|---|---|---|
| ↓ | openBook | `{bookId, kind, filePath, text?, cfi?, start?, highlights?}` | 打书；txt 可直传内容（web 平台必须） |
| ↓ | applyTheme | `{mode, fontSize, lineHeight, fontFamily, fontPath?}` | 实时改主题/字体 |
| ↓ | scrollToPercent / scrollToOffset / scrollToCfi | `{percent}` / `{start}` / `{cfi}` | 百分比 / 字符偏移 / CFI 跳转 |
| ↓ | nextPage / prevPage | `{}` | 翻页 |
| ↓ | addAnnotation / removeAnnotation | `{id, start?, end?, cfiRange?, color}` / `{id}` | 渲染/移除高亮 |
| ↓ | exportAnnotations | `{}` | 触发回传当前注解 |
| ↑ | onReady / onMeta / onToc | — / `{title, author}` / `{items:[...]}` | 握手、元信息、目录 |
| ↑ | onPageChanged | `{percent, cfi?, start?, chapter?, index, total}` | 翻页完成（Dart 存进度 + 触发全刷） |
| ↑ | onLongPress | `{text, start?, end?, cfiRange?}` | 选区上报 → Flutter 弹划线菜单 |
| ↑ | onToggleChrome | — | 点中央 → Flutter 显隐顶/底栏 |
| ↑ | onNeedRefresh | `{type: 'full'\|'partial'}` | 请求 EPD 刷新 |

**关键时序（不可反）**：TS 渲染完成 → `onPageChanged` → Dart `EpdChannel.full()` → 原生全刷。

## EPD 刷新插件说明（L4）

厂商无统一公开 API，`EpdRefreshPlugin.kt` 采用「候选类 + 反射 + 逐个尝试」策略：

- **Boox/Onyx**：`com.onyx.android.sdk.device.EpdController` / `EpdDeviceManager` / `DeviceInfoSingleton`
- **海信 Hisense**：`com.hisense.epd.Epd` / `com.hisense.android.graphics.EPDManager`
- **墨案 Moaan**：走 Boox 候选（系统内核同源），失败走通用兜底
- **通用兜底**：`decorView.invalidate()`（默认局刷模式下等效局刷）
- `isEink()`：按 `Build.MANUFACTURER` 白名单识别，非墨水屏设备 Flutter 侧自动静默

若拿到厂商正式 AAR SDK，在 `resolveEntry()` 对应分支替换反射调用即可，Dart 协议不变。
**注**：反射适配需在真机上验证（模拟器无 EPD 控制器）。

## 平台差异与已知边界

1. **web（chrome）**：使用 `flutter_inappwebview` v6 的 web 实现（iframe）。TXT 引擎可用（内容直传 payload）；EPUB 引擎在 web 上不可用（file:// 不可达）。sqflite 在 web 不可用：`Repositories` 工厂自动切换 SharedPreferences + 内存实现。
2. **EPUB 引擎**：自研实现（JSZip 读 zip + 浏览器原生 DOMParser 解析 OPF/NCX/NAV），无第三方黑盒引擎；关键调用包了 try/catch，引擎异常不会拖垮壳层，错误经 `onError` 事件上浮日志。
3. **未随包交付的二进制**：`gradle-wrapper.jar`（`flutter create .` 补齐）、字体文件（自行投放 `assets/fonts/`）、厂商 EPD AAR（按需）。

## 开发验证

```bash
flutter analyze        # 静态分析
flutter test           # 冒烟测试（Repositories.overrideForTest() 注入内存实现，无需平台插件）
cd web_engine && npm run build   # TS 引擎构建（含 tsc --noEmit）
```

关键约定（完整清单见 `AGENTS.md`）：
- Dart 包名是 `ebook_reader`（与仓库目录名不同）——import 一律 `package:ebook_reader/...`。
- 墨水屏原则：**全局瞬时无动画**（主题/路由 `Duration.zero`）、禁 OverscrollGlow，新 UI 不得引入转场/发光动画。

编译后可按 [SETUP.zh-CN.md §七](SETUP.zh-CN.md) 的验证清单自测（书架/阅读/目录/划线/设置/进度/真机全刷）。英文版见 [SETUP.md](SETUP.md)。

## 文档

- [README.md](README.md) — 本文档英文版
- [SETUP.zh-CN.md](SETUP.zh-CN.md) — 完整中文部署与验证清单（英文版：[SETUP.md](SETUP.md)）
- [AGENTS.md](AGENTS.md) — 架构边界与开发约定
- [web_engine/README.md](web_engine/README.md) — TS 引擎细节
