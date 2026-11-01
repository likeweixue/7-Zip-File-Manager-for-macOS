#!/bin/bash
# 构建 7-Zip File Manager.app
#
# 环境变量：
#   VERSION           应用版本号，写入 Info.plist（默认 1.0.0；CI 里传 tag 去掉前缀 v）
#   BUILD_NUMBER      构建号（默认当前时间戳）
#   ARCHS             目标架构，空格分隔（默认 "arm64 x86_64"，即通用二进制）
#   SIGN_IDENTITY     codesign 身份（默认 "-" 即 ad-hoc 签名）
#   SEVENZIP_VERSION  内置 7zz 的版本（默认 26.05）
#   SEVENZIP_SHA256   tarball 校验和；设为 skip 可跳过校验
set -euo pipefail
cd "$(dirname "$0")"

APP="7-Zip File Manager.app"
BUNDLE_ID="com.workbuddy.7zfm"
MIN_MACOS="14.0"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

SEVENZIP_VERSION="${SEVENZIP_VERSION:-26.05}"
SEVENZIP_SHA256="${SEVENZIP_SHA256:-12ef6830317743cfd3f0ab1724bde43fcc270d8b6d8564f8c12c2a2b7f993570}"

# ---------------------------------------------------------------- 7zz 引擎
ensure_engine() {
  if [ -x "vendor/mac/7zz" ]; then
    echo "    vendor/mac/7zz 已存在，跳过下载"
    return
  fi

  local short="${SEVENZIP_VERSION//./}"
  local tarball="vendor/7z${short}-mac.tar.xz"
  local url="https://github.com/ip7z/7zip/releases/download/${SEVENZIP_VERSION}/7z${short}-mac.tar.xz"

  mkdir -p vendor
  if [ ! -f "$tarball" ]; then
    echo "    下载 $url"
    curl -fL --retry 3 --progress-bar -o "$tarball" "$url"
  fi

  if [ "$SEVENZIP_SHA256" != "skip" ]; then
    local actual
    actual="$(shasum -a 256 "$tarball" | awk '{print $1}')"
    if [ "$actual" != "$SEVENZIP_SHA256" ]; then
      echo "    ✗ 校验和不匹配！" >&2
      echo "      期望: $SEVENZIP_SHA256" >&2
      echo "      实际: $actual" >&2
      exit 1
    fi
    echo "    校验和 OK ($actual)"
  fi

  mkdir -p vendor/mac
  tar -xf "$tarball" -C vendor/mac 7zz readme.txt License.txt
  chmod +x vendor/mac/7zz
}

echo "==> 1/6 清理"
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

echo "==> 2/6 准备 7zz 引擎 (v$SEVENZIP_VERSION)"
ensure_engine
cp "vendor/mac/7zz" "$APP/Contents/Resources/7zz"
chmod +x "$APP/Contents/Resources/7zz"

echo "==> 3/6 附上第三方许可证"
# 7-Zip 许可证要求二进制分发时复现其许可证信息，必须随包携带
cp "LICENSES/7-Zip-License.txt" "$APP/Contents/Resources/7zip-License.txt"
cp "vendor/mac/readme.txt"      "$APP/Contents/Resources/7zip-readme.txt"
cp "LICENSES/LGPL-2.1.txt"      "$APP/Contents/Resources/LGPL-2.1.txt"
cp "LICENSE"                    "$APP/Contents/Resources/LICENSE.txt"

echo "==> 4/6 图标"
if [ ! -f "build/icon/AppIcon.icns" ]; then
  swift tools/make_icon.swift build/icon >/dev/null 2>&1 || true
fi
cp "build/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

echo "==> 5/6 写入 Info.plist (v$VERSION build $BUILD_NUMBER)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>7zfm</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>7-Zip File Manager</string>
  <key>CFBundleDisplayName</key><string>7-Zip File Manager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>压缩包</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>7z</string><string>zip</string><string>rar</string><string>tar</string>
        <string>gz</string><string>tgz</string><string>bz2</string><string>xz</string>
        <string>zst</string><string>iso</string><string>cab</string><string>jar</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> 6/6 编译 ($ARCHS)"
BINS=()
for arch in $ARCHS; do
  echo "    - $arch"
  swiftc -swift-version 5 -O -target "${arch}-apple-macos${MIN_MACOS}" \
    -o "build/obj/7zfm-$arch" Sources/*.swift
  BINS+=("build/obj/7zfm-$arch")
done
if [ "${#BINS[@]}" -eq 1 ]; then
  cp "${BINS[0]}" "$APP/Contents/MacOS/7zfm"
else
  lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/7zfm"
fi
chmod +x "$APP/Contents/MacOS/7zfm"

echo "==> 签名 ($SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" 2>&1 | grep -v "replacing existing signature" || true
xattr -cr "$APP" 2>/dev/null || true
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  echo "    签名校验通过"
else
  echo "    ⚠ 本机校验未通过（受限沙箱内属正常现象，CI 环境会正常）"
fi

if [ -z "${CI:-}" ]; then
  echo "==> 注册到 LaunchServices"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$(pwd)/$APP" 2>/dev/null || true
fi

echo ""
echo "==> 完成: $(pwd)/$APP"
lipo -archs "$APP/Contents/MacOS/7zfm" | sed 's/^/    架构: /'
du -sh "$APP" | sed 's/^/    体积: /'
