# assets/web

- 内容：`web_engine` 的 Vite 构建产物（根目录 `.\build_web.ps1` 一键构建并同步到本目录）。
- 产物约定：
  - 入口固定为 `main.js`，目录必须扁平（不加 `assets/` 子目录）。
  - 必须是经典脚本（IIFE），不能是 ES module：Android 与本地浏览器都按 `file://` 加载，
    `type="module"` 会被 CORS 拦截导致引擎不执行、阅读页白屏。

## 两个平台的加载方式

- Android：`WebAssetCopier` 把本目录拷到 `<documents>/webview_root`，WebView 直接 load `index.html`
  （与书籍同盘，引擎用 **XHR** 读 `file://` 书籍/字体/epub）。
  注意不能用 `fetch`：Blink 的 Fetch 不支持 `file:` scheme，会报
  `URL scheme "file" is not supported`（与 `allowFileAccessFromFileURLs` 无关），
  读取统一走 `web_engine/src/io.ts` 的 `loadBinary` / `loadText`。
- Web（chrome/edge 联调）：阅读页自建同源 iframe 直接加载本目录的 `index.html`
  （`lib/bridge/engine_host_web.dart`），引擎作为真实文档执行，不需要 Dart 注入源码。
  下行 Dart → 引擎走 `iframe.contentWindow.postMessage`（报文带 `__ink: 'down'`），
  上行引擎 → Dart 走 `window.parent.postMessage`（报文 `source: 'ink-reader'`）。
  该平台读不到本地文件：txt 正文由 Dart 通过 openBook 的 `text` 直传，epub 二进制由 Dart 读好
  以 `dataBase64` 内嵌下发（内存缓存，刷新页面后需重新导入）。
- Web 平台的资源 URL 是「`assets/` + asset key」，key 本身就带 `assets/` 前缀，
  所以 iframe 用 `ui_web.assetManager.getAssetUrl('assets/web/index.html')` 得到的是
  `assets/assets/web/index.html`；不要硬编码单层 `assets/web/...`，否则 404、引擎不执行。
