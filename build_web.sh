#!/usr/bin/env bash
# 构建 web_engine 并同步产物到 Flutter assets
set -e
cd "$(dirname "$0")/web_engine"

if command -v pnpm >/dev/null 2>&1; then
  pnpm install
  pnpm build
else
  npm install
  npx vite build
fi

rm -rf ../assets/web
mkdir -p ../assets/web
cp -r dist/* ../assets/web/
echo "web_engine 产物已同步到 assets/web/"
echo "下一步：flutter pub get && flutter build apk（或 flutter run -d chrome）"
