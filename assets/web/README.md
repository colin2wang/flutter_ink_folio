# assets/web

- 正常交付：`web_engine` 的 Vite 构建产物（`pnpm build && cp -r dist/* .`）。
- 当前内容：**免构建回退引擎**（vanilla JS，仅支持 TXT），保证 Flutter 壳开箱即跑。
- 构建产物放入后本目录的 index.html / main.js 会被覆盖，协议兼容，Flutter 侧无需改动。

⚠️ `main.js` 内含 `INLINE_MAIN_JS` 占位符约定（index.html），不要删除该注释 ——
web 平台（flutter run -d chrome）依赖它把 main.js 内联进 iframe。
