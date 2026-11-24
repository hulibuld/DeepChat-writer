#!/bin/bash
# 一条命令出两个 .ipa：通用未签名版 + TrollStore 版（ad-hoc 签名 + platform-application）。
# 依赖：Xcode（提供 iOS SDK）、xcodegen（brew install xcodegen）。
# 用法：./build-ipa.sh [版本号]，默认取 Info.plist 里的 CFBundleShortVersionString。
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d /Applications/Xcode.app ]; then
  echo "没找到 /Applications/Xcode.app，先装 Xcode（免费）" >&2
  exit 1
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

command -v xcodegen >/dev/null || { echo "缺 xcodegen：brew install xcodegen" >&2; exit 1; }

echo "==> 生成工程"
xcodegen generate

echo "==> 编译 Release（arm64，不签名）"
rm -rf build
xcodebuild -project DeepChat.xcodeproj -target DeepChat -sdk iphoneos -configuration Release \
  SYMROOT="$PWD/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build | grep -E "error:|warning: .*deprecated|BUILD" || true

APP="build/Release-iphoneos/DeepChat.app"
[ -d "$APP" ] || { echo "编译没产出 $APP" >&2; exit 1; }

VER="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")}"
OUT="dist"
rm -rf "$OUT" && mkdir -p "$OUT"

echo "==> 通用未签名 ipa"
rm -rf "$OUT/Payload" && mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && COPYFILE_DISABLE=1 zip -qry "DeepChat-${VER}-unsigned.ipa" Payload)
rm -rf "$OUT/Payload"

echo "==> TrollStore 版（ad-hoc 签名 + platform-application）"
WORK="$(mktemp -d)"
cp -R "$APP" "$WORK/DeepChat.app"
xattr -cr "$WORK/DeepChat.app"
cat > "$WORK/ent.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>platform-application</key><true/>
    <key>com.apple.private.security.no-container</key><true/>
    <key>get-task-allow</key><true/>
</dict>
</plist>
PLIST
for fw in "$WORK/DeepChat.app/Frameworks"/*.framework; do
  codesign -f -s - --entitlements "$WORK/ent.plist" --timestamp=none "$fw"
done
codesign -f -s - --entitlements "$WORK/ent.plist" --timestamp=none "$WORK/DeepChat.app"
mkdir -p "$WORK/Payload" && cp -R "$WORK/DeepChat.app" "$WORK/Payload/"
(cd "$WORK" && COPYFILE_DISABLE=1 zip -qry "DeepChat-${VER}-trollstore.ipa" Payload)
mv "$WORK/DeepChat-${VER}-trollstore.ipa" "$OUT/"
rm -rf "$WORK"

echo
echo "==> 完成"
for f in "$OUT"/*.ipa; do
  printf '%s\t%s 字节\n' "$(basename "$f")" "$(stat -f%z "$f")"
  shasum -a 256 "$f"
done