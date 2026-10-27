import { defineConfig } from 'vite';

export default defineConfig({
  // 相对路径：产物会被拷入 assets/web 并通过 file:// 加载
  base: './',
  plugins: [
    {
      /**
       * web 平台（flutter run -d chrome）走 iframe，没有 base URL，
       * 相对引用的 <script src> 会 404；因此 Flutter 壳会读 assets/web/main.js
       * 并把它内联进这个占位符（见 reader_page._resolveEntry）。
       *
       * 放在构建末尾注入，避免 Vite 把这个内联脚本卷进打包流程。
       */
      name: 'ink-inline-main-js-slot',
      transformIndexHtml: {
        order: 'post',
        handler: html =>
          html.replace('</body>', '    <script>/*INLINE_MAIN_JS*/</script>\n  </body>'),
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
      },
    },
  },
  server: {
    port: 5173,
  },
});
