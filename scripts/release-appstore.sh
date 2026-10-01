#!/bin/bash
# App Store 版发布：归档沙盒版本 → 导出可上传 App Store Connect 的安装包
# 前置条件：Xcode 已登录开发者帐户；App Store Connect 中已创建 Bundle ID 为
# com.ws.RemoteMapper.Lite 的 App；签名证书与描述文件由 Xcode 自动管理。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
OUT=build/release/appstore
ARCHIVE="$OUT/RemoteMapperLite.xcarchive"

rm -rf "$OUT"; mkdir -p "$OUT"
xcodegen generate >/dev/null

echo "==> 归档 App Store 版 $VERSION"
xcodebuild -project RemoteMapper.xcodeproj -scheme RemoteMapperLite -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive -quiet \
  -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"

echo "==> 导出安装包"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist scripts/ExportOptions-AppStore.plist -allowProvisioningUpdates -quiet

echo "完成：$(ls "$OUT"/*.pkg)。可用 Transporter 上传，或把 ExportOptions 中的 destination 改为 upload 直接上传。"
