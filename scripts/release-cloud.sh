#!/bin/bash
# 自用完整版：Release 编译、本地签名、DMG 与音频组件对应源码，不需要 Apple 凭据。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
ARCH=$(uname -m)
[ "$ARCH" = arm64 ] || { echo "当前发布目标为 Apple Silicon（arm64）。" >&2; exit 1; }
OUT=build/release/cloud
APP="$OUT/RemoteMapper.app"
DMG="RemoteMapper-$VERSION-macOS-arm64.dmg"
SOURCE="RemoteMapper-$VERSION-Microphone-Source.tar.gz"
mkdir -p "$OUT"

# 完整版必须先构建音频组件，不能静默发布缺少组件的 App。
scripts/build-microphone.sh
xcodegen generate
xcodebuild -project RemoteMapper.xcodeproj -scheme RemoteMapper -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/CloudDerivedData \
    CODE_SIGNING_ALLOWED=NO build -quiet
ditto build/CloudDerivedData/Build/Products/Release/RemoteMapper.app "$APP"
PAYLOAD="$APP/Contents/Resources/Microphone"
for file in RemoteMapperMic.driver/Contents/MacOS/RemoteMapperMic rm_capture srm_router install.sh; do
    [ -f "$PAYLOAD/$file" ] || { echo "完整版音频组件缺失：$file" >&2; exit 1; }
done
for binary in "$APP/Contents/MacOS/RemoteMapper" \
    "$PAYLOAD/RemoteMapperMic.driver/Contents/MacOS/RemoteMapperMic" "$PAYLOAD/rm_capture" "$PAYLOAD/srm_router"; do
    [ "$(lipo -archs "$binary")" = arm64 ] || { echo "架构异常：$binary" >&2; exit 1; }
done
codesign --force --sign - --options runtime --entitlements App/RemoteMapper.entitlements "$APP"
codesign --verify --deep --strict "$APP"

# 静态链接的 Opus 与音频组件一起提供对应源码，并记录校验和。
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1
brew info --json=v2 opus > "$OUT/opus-formula.json"
python3 - "$OUT/opus-formula.json" > "$OUT/opus-source.txt" <<'PY'
import json, sys
formula = json.load(open(sys.argv[1]))['formulae'][0]
stable = formula['urls']['stable']
print(stable['url'])
print(stable['checksum'])
print(formula['versions']['stable'])
PY
OPUS_URL=$(sed -n '1p' "$OUT/opus-source.txt")
OPUS_SHA=$(sed -n '2p' "$OUT/opus-source.txt")
OPUS_VERSION=$(sed -n '3p' "$OUT/opus-source.txt")
OPUS_PREFIX="${REMOTEMAPPER_OPUS_PREFIX:-$(brew --prefix opus)}"
LINKED_OPUS_VERSION=$(sed -n 's/^Version: //p' "$OPUS_PREFIX/lib/pkgconfig/opus.pc")
[ "$OPUS_VERSION" = "$LINKED_OPUS_VERSION" ] || { echo "Opus 源码版本与构建依赖不一致。" >&2; exit 1; }
SRC="$OUT/source/RemoteMapper-Microphone"
mkdir -p "$SRC/scripts" "$SRC/vendor"
ditto AudioBridge "$SRC/AudioBridge"
cp scripts/build-microphone.sh "$SRC/scripts/"
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 "$OPUS_URL" -o "$SRC/vendor/opus-$OPUS_VERSION.tar.gz"
printf '%s  %s\n' "$OPUS_SHA" "$SRC/vendor/opus-$OPUS_VERSION.tar.gz" | shasum -a 256 -c -
cat > "$SRC/BUILD.txt" <<EOF
RemoteMapper audio component corresponding source
Commit: $(git rev-parse HEAD)
Opus: $OPUS_VERSION
Opus archive SHA-256: $OPUS_SHA
Build requirements: macOS 26+, Xcode 26.6+, Homebrew Opus (same version).
Build: bash scripts/build-microphone.sh
To build Opus from the included source: extract vendor/opus-$OPUS_VERSION.tar.gz,
run ./configure --prefix=/your/opus/prefix --enable-static --disable-shared && make && make install,
then set REMOTEMAPPER_OPUS_PREFIX=/your/opus/prefix for the component build.
EOF
tar -czf "$OUT/$SOURCE" -C "$OUT/source" RemoteMapper-Microphone

cat > "$OUT/BUILD-INFO.txt" <<EOF
RemoteMapper $VERSION — 完整版
Commit: $(git rev-parse HEAD)
Architecture: arm64 (Apple Silicon)
Minimum macOS: 26.0
Signing: ad-hoc (本地签名), NOT Apple notarized
Opus: $OPUS_VERSION
EOF
xcodebuild -version >> "$OUT/BUILD-INFO.txt"
swift --version >> "$OUT/BUILD-INFO.txt"
cat > "$OUT/安装说明.txt" <<'EOF'
将 RemoteMapper.app 拖到「应用程序」。这是完整功能的自用构建，没有 Apple 公证。
首次打开如被拦截，请在「系统设置 › 隐私与安全性」中允许打开。
首次使用按键模拟需授权「辅助功能」；语音输入需允许麦克风并下载本机识别模型。
遥控器内置麦克风需先安装 Apple PacketLogger 到 /Applications/PacketLogger.app，
然后在「通用 › 语音输入」点击「安装并设为系统输入」，由用户授权安装音频组件。
适用 Apple Silicon、macOS 26+。
EOF
mkdir -p "$OUT/dmg"
ditto "$APP" "$OUT/dmg/RemoteMapper.app"
cp "$OUT/安装说明.txt" "$OUT/BUILD-INFO.txt" "$OUT/dmg/"
if [ ! -L "$OUT/dmg/应用程序" ]; then ln -s /Applications "$OUT/dmg/应用程序"; fi
hdiutil create -volname "RemoteMapper $VERSION" -srcfolder "$OUT/dmg" -fs HFS+ -format UDZO -ov "$OUT/$DMG" -quiet
hdiutil verify "$OUT/$DMG"
(cd "$OUT" && shasum -a 256 "$DMG" "$SOURCE" BUILD-INFO.txt > SHA256SUMS.txt)
echo "完整版下载包：$OUT/$DMG"
