#!/bin/bash
# 把构建好的 .app 打成可分发的 DMG + ZIP
#
# 环境变量：
#   VERSION  版本号（默认读 Info.plist 的 CFBundleShortVersionString）
#   OUT      输出目录（默认 dist）
set -euo pipefail
cd "$(dirname "$0")/.."

APP="7-Zip File Manager.app"
OUT="${OUT:-dist}"

if [ ! -d "$APP" ]; then
  echo "找不到 $APP，请先运行 ./build.sh" >&2
  exit 1
fi

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
BASE="7-Zip-File-Manager-$VERSION"

mkdir -p "$OUT"
rm -f "$OUT/$BASE.dmg" "$OUT/$BASE.zip"

echo "==> 打包 ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$BASE.zip"

echo "==> 打包 DMG"
STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "7-Zip File Manager" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$OUT/$BASE.dmg" >/dev/null

rm -rf "$STAGE"

echo "==> 签名 DMG（ad-hoc，让校验和稳定）"
codesign --force --sign "${SIGN_IDENTITY:--}" "$OUT/$BASE.dmg" 2>/dev/null || true

echo ""
echo "==> 产物："
ls -lh "$OUT" | tail -n +2
echo ""
shasum -a 256 "$OUT/$BASE.dmg" "$OUT/$BASE.zip" > "$OUT/$BASE.sha256"
cat "$OUT/$BASE.sha256" | sed 's/^/    /'
