# inkreader-web-engine

墨水屏阅读器的 WebView 阅读引擎（L3 层）。EPUB 与 TXT 均为自研引擎，共用一套排版与定位模型。

## 模块

- `src/epub_engine.ts` — 自研 EPUB 引擎（按章分页 + 全局字符偏移定位 + 偏移高亮）
- `src/epub/epub_book.ts` — EPUB 解析：zip 用 JSZip，OPF / NCX / NAV 用浏览器原生 DOMParser
- `src/txt_engine.ts` — 自研 TXT 引擎（纯文本段落化 + 字符偏移定位 + 偏移高亮）
- `src/pager.ts` — 通用多栏分页器（两引擎共用：分栏、翻页、页数统计、比例回位）
- `src/text.ts` — 纯文本 ↔ DOM 位置换算（选区与高亮共用）
- `src/renderer.ts` — 灰阶主题 / 字体 / 中文避头尾注入 + EPUB 排版兜底
- `src/gesture.ts` — 点击分区翻页、横滑翻页、选区上报
- `src/bridge.ts` — 与 Flutter 壳的双向桥（统一 JSON 信封）
- `src/main.ts` — 消息分发与引擎路由

## 依赖

运行时只有 `jszip`（npm 官方，MIT / GPL-3.0 双许可，此处按 MIT 使用）。
无 GitHub 或自托管 git 依赖，无 iframe 黑盒引擎。

## 开发

```bash
pnpm install
pnpm dev      # 浏览器调试（桥未注入时仅控制台可见上行事件）
pnpm build    # 产物输出 dist/
```

## 构建进 Flutter 壳

```bash
pnpm build && cp -r dist/* ../assets/web/
```

或在仓库根执行 `./build_web.sh`（Windows 用 `build_web.ps1`）。

## 注意

- **定位模型不用 CFI。** 两个引擎统一用「全局字符偏移」：进度落在 `startOffset`，
  划线落在 `start` / `end`，Flutter 侧与数据库无需按格式分支。
  EPUB 的目录项与跳转复用了 `cfi` 字段，内容格式为 `<spineIndex>#<anchor>`。
- **进度换算需要全书长度。** 打开 EPUB 时会预扫描各章纯文本长度（只解析不渲染），
  这是全局进度的分母，不能省略。
- **产物入口固定为 `main.js`**（见 `vite.config.ts`）：Dart 侧按 `assets/web/main.js`
  硬编码读取，带 hash 的文件名会让 web 平台读不到，也会在 assets 里堆积历史版本。
- 打开 EPUB 时会把各章自带的 CSS 内联进 body —— 引擎只取 `body.innerHTML`，
  留在 `head` 里的样式会丢失。
- 产物 base 为 `./`，允许直接 file:// 加载。
- Web 平台（chrome）下引擎取不到本地文件：TXT 由 Dart 直传 `text`，
  EPUB 由 Dart 读好以 `dataBase64` 内嵌下发（`epub_engine.open` 优先用它，
  否则 `loadBinary(filePath)` 走 XHR；web 侧缓存只在内存，刷新页面即失效）。
- 全局禁动画/渐变/模糊 —— 这是墨水屏引擎的硬约束，别加回来。
