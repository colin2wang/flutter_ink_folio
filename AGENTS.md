# AGENTS.md — AI 编码代理项目指南（墨屏阅读 flutter_ink_folio）

## 维护规则
项目结构、构建/测试命令、架构边界、开发约定或本文件记录的其他事实发生变化时，必须在同一次改动中同步更新本文件（用当前事实替换过期表述，不追加变更历史）。事故复盘、性能对比等详细材料放带链接的独立文档，仅任务相关时读取。

## 构建与验证命令
- Android APK：`flutter build apk --release`（构建通过即主验证，17s~3min），或 `.\build_apk.ps1`（默认 release，`-Flavor debug|profile` 可切换；**不重建 web 引擎**）
- 测试：`flutter test`（根目录，当前仅 test/widget_test.dart 冒烟测试）
- 静态分析：`flutter analyze`
- Web 引擎（独立 TS 工程，不在 Flutter 构建内）：`cd web_engine && npm run build`（含 tsc --noEmit）；一键构建并同步进 `assets/web/` 用根目录 `.\build_web.ps1`（`build_web.sh` 为 Linux/macOS 版）
- 一键引导：`.\init.ps1`（生成缺失的 android/web 平台目录 + pub get + analyze + test；重建 android 前会检查墨水屏定制文件并要求确认）

## 架构（L1-L5，见 README.zh-CN.md）
- `lib/` Flutter 应用：features/{shelf,reader,settings,annotation}、data/（sqflite 双平台仓库）、services/、bridge/
- `web_engine/` L3：TS 阅读引擎，产物进 WebView；含自研 EPUB 引擎（`epub_engine.ts` + `epub/epub_book.ts`）与自研 TXT 引擎（`txt_engine.ts`），两者共用 `pager.ts` 排版与「全局字符偏移」定位模型；L2 桥接层 MethodChannel(`ebook_reader/epd`) + JS Handler JSON 信封
- `android/app/src/main/kotlin/com/inkscreen/reader/EpdRefreshPlugin.kt` L4：Boox/海信/墨案反射适配（候选类 + test/full/partial 接口），**是原生定制文件，flutter create 重建 android/ 会覆盖它**
- 数据层：`Repositories` 工厂按 kIsWeb 切换 sqflite / SharedPreferences+内存实现

## 关键约定（项目特有）
- 包名是 `ebook_reader`，与目录名 flutter_ink_folio 不同——import 一律 `package:ebook_reader/...`
- 墨水屏原则：**瞬时无动画**（主题/路由 Duration.zero）、全局禁 OverscrollGlow、灰阶配色；新 UI 不得引入转场/发光动画
- web_engine **不用 CFI** 定位：TXT/EPUB 统一用「全局字符偏移」（进度 `startOffset`、划线 `start`/`end`），EPUB 的 `cfi` 字段内容格式为 `<spineIndex>#<anchor>`；产物必须扁平且入口固定为 `main.js`（`reader_page.dart` 按 `assets/web/main.js` 硬编码读取，带 hash 的名字会让 web 平台崩溃）
- widget 测试环境无平台插件：用 `Repositories.overrideForTest()` 注入内存实现（见 test/widget_test.dart）
- `.gitattributes`：仓库统一 LF；根目录 .ps1（init.ps1、build_web.ps1）显式 CRLF——**PowerShell 5.1 读 UTF-8 无 BOM 的 .ps1 会按 GBK 乱码**，含中文注释的 .ps1 必须带 BOM
- .gitignore 已存在且经人工整理，勿随意改动；COMMIT.md 为本地提交草稿不入库
