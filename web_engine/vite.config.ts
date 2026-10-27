import { defineConfig } from 'vite';

export default defineConfig({
  // 相对路径：产物会被拷入 assets/web 并通过 file:// 加载
  base: './',
  build: {
    target: 'es2020',
    outDir: 'dist',
    assetsInlineLimit: 0,
    // 单页应用，无需 code splitting 的动态路由
    rollupOptions: {
      output: {
        manualChunks: undefined,
      },
    },
  },
  server: {
    port: 5173,
  },
});
