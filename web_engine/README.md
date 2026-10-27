# inkreader-web-engine

墨水屏阅读器的 WebView 阅读引擎（L3 层）。

- `src/loader.ts` — foliate-js 集成（epub/mobi/fb2）
- `src/txt_engine.ts` — 自研 TXT 引擎（CSS 多栏分页 + 字符偏移定位 + 偏移高亮）
- `src/renderer.ts` — 灰阶主题/字体/中文避头尾注入
- `src/gesture.ts` — 点击分区翻页、滑动、选区上报
- `src/bridge.ts` — 与 Flutter 壳的双向桥（统一 JSON 信封）
- `src/main.ts` — 消息分发与引擎路由

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

- foliate-js 无官方类型声明（loader.ts 用 any + try/catch 包裹关键调用）。
- 产物 base 为 `./`，允许直接 file:// 加载。
- 全局禁动画/渐变/模糊 —— 这是墨水屏引擎的硬约束，别加回来。
