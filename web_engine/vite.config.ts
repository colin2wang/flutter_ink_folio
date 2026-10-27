import { defineConfig } from 'vite';

export default defineConfig({
  // 相对路径：产物会被拷入 assets/web 并通过 file:// 加载
  base: './',
  plugins: [
    {
      /**
       * 产物是经典脚本（format: 'iife'），index.html 不能再用 <script type="module">。
       *
       * Android/WebView 与直接用浏览器打开 index.html 都是 file:// 加载，该 origin 为
       * 'null'，module 脚本强制走 CORS → "Access to script ... blocked by CORS policy"，
       * 引擎整个不执行 → 阅读页白屏。经典脚本 + defer 无此限制。
       *
       * 放在构建末尾做，避免 Vite 把改写过的脚本标签卷进打包流程。
       */
      name: 'ink-file-protocol-html',
      transformIndexHtml: {
        order: 'post',
        handler: html =>
          html.replace(/<script([^>]*)\stype="module"([^>]*)>/g, (_m, before, after) => {
            const attrs = `${before}${after}`.replace(/\s*crossorigin(?:="[^"]*")?/g, '');
            return `<script${attrs} defer>`;
          }),
      },
    },
  ],
  build: {
    target: 'es2020',
    outDir: 'dist',
    // 不加 assets/ 子目录：产物必须扁平，Dart 侧按固定路径读取
    assetsDir: '',
    assetsInlineLimit: 0,
    rollupOptions: {
      output: {
        // 固定产物名：rootBundle.loadString('assets/web/main.js') 与 build_web 脚本都依赖它，
        // 带 hash 的文件名会让 Flutter 侧读不到，也会在 assets/web 里堆积历史版本。
        entryFileNames: 'main.js',
        chunkFileNames: '[name].js',
        assetFileNames: '[name][extname]',
        manualChunks: undefined,
        // 必须是 IIFE 经典脚本：产物通过 file:// 加载（Android WebView / 本地浏览器打开），
        // ES module 在该协议下会被 CORS 拦截导致引擎不执行。单入口 + inlineDynamicImports
        // （Vite 对 iife 自动开启），故不会出现多 chunk 的 import/export。
        format: 'iife',
        name: 'InkReaderEngine',
      },
    },
  },
  server: {
    port: 5173,
  },
});
