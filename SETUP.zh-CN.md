# 墨屏阅读 —— 墨水屏阅读器（Flutter + WebView 引擎 + Android EPD 插件）

**[English](SETUP.md) | 简体中文**

按「五层架构」实现的墨水屏阅读器，只适配 Android（附带 Chrome 调试通道）。

```
L1 Flutter 壳层(Dart)   书架 / 设置 / 笔记 / 阅读页容器
L2 桥接层               MethodChannel(EPD) + JS Handler(统一 JSON 信封)
L3 WebView 阅读引擎(TS)  foliate-js 解析 / 分页 / 主题 / 手势 / 高亮
L4 Android 原生(Kotlin)  EpdRefreshPlugin（Boox/海信/墨案 反射适配）
L5 数据层               sqflite 书库 + 沙盒文件 + shared_preferences
```

## 一、快速开始

### 0. 环境要求
- Flutter ≥ 3.19（Dart ≥ 3.3）
- Android SDK 34、minSdk 23（覆盖 Boox/海信/墨案常见老机型）
- 引擎构建：Node ≥ 18 + pnpm（或 npm）

### 1. 首次运行（免构建引擎，开箱即跑）

仓库已内置一份 **免构建回退引擎**（`assets/web/main.js`，vanilla JS，仅 TXT），
`flutter pub get` 后可直接跑：

```bash
flutter pub get
flutter run -d <android设备>     # Android 真机/模拟器
flutter run -d chrome            # Chrome 联调（仅壳层+TXT，见 §四）
```

书架里已预置示例书《墨屏阅读 · 示例书》（含 8 个章节），可立即验证
翻页 / 目录 / 进度恢复 / 划线 / 主题切换 全链路。

### 2. 启用 EPUB 引擎（foliate-js，正式引擎）

```bash
# Linux/macOS
./build_web.sh
# Windows
.\build_web.ps1
```

脚本做的事 = `cd web_engine && pnpm install && pnpm build && cp -r dist/* ../assets/web/`。
产物放入后覆盖回退引擎，重新运行 App 即支持 EPUB。

### 3. 出 APK

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 若首次构建报 gradle wrapper 相关错误（仓库未附带 gradle-wrapper.jar 二进制），
> 在工程根执行 `flutter create --platforms=android .` 补齐脚手架后再构建，
> 已有文件不会被覆盖。

## 二、目录结构

```
ebook_reader/
├── android/                        # L4：gradle + EpdRefreshPlugin.kt + MainActivity.kt
├── assets/
│   ├── web/                        # 引擎产物（当前为免构建回退引擎）
│   ├── books/sample.txt            # 示例书
│   └── fonts/字体说明.txt           # 内置字体投放目录（可选）
├── lib/
│   ├── main.dart / app.dart        # 入口 + 灰阶 ThemeData + 瞬时路由
│   ├── bridge/
│   │   ├── bridge_protocol.dart    # 统一 JSON 信封 + action/event 常量
│   │   ├── js_bridge.dart          # Dart↔TS 双向桥 + WebView 设置
│   │   └── epd_channel.dart        # 墨水屏刷新 MethodChannel
│   ├── features/
│   │   ├── shelf/                  # 书架（导入/删除/占位封面）
│   │   ├── reader/                 # ReaderPage + controller + chrome/目录/划线菜单
│   │   ├── settings/               # 阅读设置（字号/行距/主题/字体/全刷频率）
│   │   └── annotation/             # 全局笔记列表
│   ├── data/                       # models / sqflite / 双平台仓库
│   ├── services/                   # 导书 / 字体管理 / web资产拷贝
│   └── theme/                      # 灰阶主题 + PageRouteBuilder(Duration.zero)
├── web_engine/                     # L3：TS 工程（Vite + foliate-js）
├── build_web.sh / build_web.ps1
└── pubspec.yaml
```

## 三、桥接协议（Dart ↔ TS）

统一信封：`{ action, payload, requestId? }`。
Dart→TS：`window.__reader.dispatch(msg)`；TS→Dart：`callHandler('event', msg)`。

| 方向 | 名称 | payload | 说明 |
|---|---|---|---|
| ↓ | openBook | `{bookId, kind, filePath, text?, cfi?, start?, highlights?}` | 打书；txt 可直传内容（web 平台必须） |
| ↓ | applyTheme | `{mode, fontSize, lineHeight, fontFamily, fontPath?}` | 实时改主题/字体 |
| ↓ | scrollToPercent | `{percent}` | 按百分比跳转 |
| ↓ | scrollToOffset | `{start}` | txt 字符偏移（目录跳转） |
| ↓ | scrollToCfi | `{cfi}` | epub CFI（foliate 引擎） |
| ↓ | nextPage / prevPage | `{}` | 翻页 |
| ↓ | addAnnotation | `{id, start?, end?, cfiRange?, color}` | 渲染高亮 |
| ↓ | removeAnnotation | `{id}` | 移除高亮 |
| ↓ | exportAnnotations | `{}` | 触发回传当前注解 |
| ↑ | onReady | — | 桥握手完成 |
| ↑ | onMeta | `{title, author}` | 元信息 |
| ↑ | onToc | `{items:[{title, offset?, cfi?}]}` | 目录 |
| ↑ | onPageChanged | `{percent, cfi?, start?, chapter?, index, total}` | 翻页完成（触发 Dart 存进度 + 全刷） |
| ↑ | onLongPress | `{text, start?, end?, cfiRange?}` | 选区上报 → Flutter 弹划线菜单 |
| ↑ | onToggleChrome | — | 点中央 → Flutter 显隐顶/底栏 |
| ↑ | onNeedRefresh | `{type: 'full'\|'partial'}` | 请求 EPD 刷新 |

**关键时序（不可反）**：TS 渲染完成 → `onPageChanged` → Dart `EpdChannel.full()` → 原生全刷。

## 四、墨水屏适配实现清单

| 项 | 实现 |
|---|---|
| 灰阶主题 | `AppTheme`：全黑白灰、`elevation=0`、`NoSplash.splashFactory`、无过渡动画 |
| 页面转场 | `instantRoute`：`PageRouteBuilder(transitionDuration: Duration.zero)` |
| 翻页全刷 | `onPageChanged` → `EpdChannel.full()`；目录/设置关闭 → full；划线/菜单 → partial |
| 残影规避 | 引擎 CSS 全局 `transition/animation: none`、无渐变/模糊/阴影；翻页硬切（transform 瞬移） |
| Chrome 显隐 | 平时隐藏，点中央弹出，出现/消失各一次局刷 |
| 字体 | `assets/fonts/` 投放思源宋/黑体 → FontManager 拷沙盒 → @font-face 注入 |
| WebView | 关动画选项、透明背景、禁缩放/滚动、开 file 访问（同沙盒读取书籍/字体） |
| 刷新模式 | 设置面板可调「每 N 页一次全刷」，适配对闪屏敏感的机型 |

## 五、EPD 刷新插件说明（EpdRefreshPlugin.kt）

厂商无统一公开 API，插件采用「候选类 + 反射 + 逐个尝试」策略：

- **Boox/Onyx**：`com.onyx.android.sdk.device.EpdController` / `EpdDeviceManager` / `DeviceInfoSingleton`
- **海信 Hisense**：`com.hisense.epd.Epd` / `com.hisense.android.graphics.EPDManager`
- **墨案 Moaan**：走 Boox 候选（系统内核同源），失败走通用兜底
- **通用兜底**：`decorView.invalidate()`（默认局刷模式下等效局刷）
- `isEink()`：按 Build.MANUFACTURER 白名单识别，非墨水屏设备 Flutter 侧自动静默

若拿到厂商正式 AAR SDK，在 `resolveEntry()` 对应分支替换反射调用即可，Dart 协议不变。
**注**：反射适配需在真机上验证（模拟器无 EPD 控制器）。

## 六、平台差异与已知边界

1. **web（chrome）**：`flutter_inappwebview` v6 的 web 实现（iframe）。
   - TXT 引擎可用（内容直传 payload）；EPUB 引擎在 web 上不可用（file:// 不可达）。
   - sqflite 在 web 不可用：`Repositories` 工厂自动切换 SharedPreferences+内存实现。
   - 联调入口：`flutter run -d chrome`。
2. **EPUB 引擎**：foliate-js 无官方 TS 类型，`loader.ts` 对关键调用做了 try/catch
   隔离，引擎异常不会拖垮壳层，错误经 `onError` 事件上浮日志。
3. **TXT 进度**：按字符偏移+百分比双轨存储，重排后按百分比近似恢复（误差 ≤1 页）。
4. **未随包交付的二进制**：gradle-wrapper.jar（`flutter create .` 补齐）、
   字体文件（自行投放 assets/fonts/）、厂商 EPD AAR（按需）。
5. 本仓库未做实机编译验证（按约定交付源码）；`web_engine` 需先 `pnpm install`。

## 七、验证清单建议（供你编译后自测）

- [ ] 书架：预置示例书出现、导入 TXT/EPUB、长按删除
- [ ] 阅读：翻页无动画硬切、点中央呼出/收起菜单（各触发一次刷新）
- [ ] 目录：TXT 章节识别跳转；EPUB 目录（foliate）
- [ ] 划线：选区 → 划线/笔记 → 高亮渲染 → 重启恢复
- [ ] 设置：字号/行距/三档灰阶主题/字体即时生效
- [ ] 进度：退出重进精确恢复（TXT 百分比、EPUB CFI）
- [ ] 真机墨水屏：翻页全刷可见、无残影累积、无彩色涟漪/滚动发光
