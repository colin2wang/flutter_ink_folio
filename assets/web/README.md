# assets/web

- 内容：`web_engine` 的 Vite 构建产物（根目录 `.\build_web.ps1` 一键构建并同步到本目录）。
- 产物约定：
  - 入口固定为 `main.js`（`reader_page.dart` 按 `assets/web/main.js` 硬编码读取，带 hash 的名字读不到），
    目录必须扁平（不加 `assets/` 子目录）。
  - 必须是经典脚本（IIFE），不能是 ES module：Android 与本地浏览器都按 `file://` 加载，
    `type="module"` 会被 CORS 拦截导致引擎不执行、阅读页白屏。

## 两个平台的加载方式

- Android：`WebAssetCopier` 把本目录拷到 `<documents>/webview_root`，WebView 直接 load `index.html`
  （与书籍同盘，JS 可 fetch `file://` 书籍/字体）。
- Web（chrome/edge 联调）：`flutter_inappwebview_web` 用 iframe 承载，只加载 `about:blank`
  后由 Dart 用 `evaluateJavascript` 注入 `main.js`（iframe 里没有 `flutter_inappwebview.callHandler`，
  上行走 `parent.postMessage`）。该平台只能读 Dart 传下来的 txt 正文，epub 需要 fetch 本地文件，不支持。
