#!/bin/bash
# 正式发布：Developer ID 签名 → Apple 公证 → 装订票据 → 打包 DMG
# 前置条件：钥匙串中有「Developer ID Application」证书；已用
#   xcrun notarytool store-credentials RemoteMapper --apple-id <Apple ID> --team-id VVB976RN4W
# 保存公证凭据（可用环境变量 NOTARY_PROFILE 指定其它名称）。
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-RemoteMapper}"
IDENTITY="Developer ID Application"
VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
OUT=build/release/direct
ARCHIVE="$OUT/RemoteMapper.xcarchive"
APP="$OUT/RemoteMapper.app"
DMG="$OUT/RemoteMapper-$VERSION.dmg"

step() { printf '\n==> %s\n' "$*"; }

security find-identity -v -p codesigning | grep -q "$IDENTITY" || {
  echo "缺少「$IDENTITY」证书：请在 Xcode › 设置 › 帐户 › 管理证书 中创建（需要帐户持有人权限）。"; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || {
  echo "未找到公证凭据「$PROFILE」：请先运行 xcrun notarytool store-credentials $PROFILE --apple-id <Apple ID> --team-id VVB976RN4W"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"

step "归档 Release 版本 $VERSION"
xcodegen generate >/dev/null
xcodebuild -project RemoteMapper.xcodeproj -scheme RemoteMapper -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp"
ditto "$ARCHIVE/Products/Applications/RemoteMapper.app" "$APP"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow" && { echo "签名中含调试权限 get-task-allow，无法公证"; exit 1; }

step "公证 App"
ditto -c -k --keepParent "$APP" "$OUT/RemoteMapper.zip"
xcrun notarytool submit "$OUT/RemoteMapper.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

step "打包并公证 DMG"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/RemoteMapper.app"
ln -s /Applications "$STAGE/应用程序"
hdiutil create -volname "RemoteMapper $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

step "Gatekeeper 校验"
spctl -a -t open --context context:primary-signature -v "$DMG"
spctl -a -t exec -v "$APP"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "完成：$DMG"
