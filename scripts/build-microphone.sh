#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/Microphone"
TEST="$ROOT/build/MicrophoneTests"
SRC="$ROOT/AudioBridge"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
OPUS_PREFIX="${REMOTEMAPPER_OPUS_PREFIX:-$(brew --prefix opus)}"
[ -f "$OPUS_PREFIX/lib/libopus.a" ] || { echo "请先安装 Opus：brew install opus" >&2; exit 1; }
mkdir -p "$OUT/RemoteMapperMic.driver/Contents/MacOS" "$TEST"
cp "$SRC/driver/Info.plist" "$OUT/RemoteMapperMic.driver/Contents/Info.plist"
clang -bundle -O2 -Wall -Wextra -Werror -isysroot "$SDK" -mmacosx-version-min=26.0 \
    -include "$SRC/driver/SiriRemoteMic.config.h" "$SRC/driver/SiriRemoteMic.c" \
    -framework CoreFoundation -framework CoreAudio -framework Accelerate \
    -o "$OUT/RemoteMapperMic.driver/Contents/MacOS/RemoteMapperMic"
clang -O2 -Wall -Wextra -Werror -fobjc-arc -isysroot "$SDK" -mmacosx-version-min=26.0 \
    "$SRC/capture.m" -framework Foundation -framework CoreAudio -o "$OUT/rm_capture"
clang -c -O2 -Wall -Wextra -Werror "$SRC/router/SiriRemoteMicRingWriter.c" -o "$TEST/writer.o"
clang -c -O2 -Wall -Wextra -Werror "$SRC/router/MonitorAudioRing.c" -o "$TEST/monitor.o"
swiftc -O -sdk "$SDK" -target "$(uname -m)-apple-macosx26.0" \
    -import-objc-header "$SRC/router/router_shim.h" -I"$OPUS_PREFIX/include" "$OPUS_PREFIX/lib/libopus.a" \
    -framework AVFoundation "$SRC/OpusVoiceDecoder.swift" "$SRC/router/VoiceFrameParser.swift" \
    "$SRC/router/PklgTailReader.swift" "$SRC/router/MonitorPlayer.swift" "$SRC/router/SiriRemoteMicRouter.swift" \
    "$TEST/writer.o" "$TEST/monitor.o" -o "$OUT/srm_router"
for tool in srm_driver_contract_test srm_io_sim; do
    clang -O2 -Wall -Wextra -Werror "$SRC/driver/$tool.c" -framework CoreFoundation -framework CoreAudio -o "$TEST/$tool"
done
clang -O2 -Wall -Wextra -Werror "$SRC/router/test_monitor_ring.c" "$SRC/router/MonitorAudioRing.c" -o "$TEST/test_monitor_ring"
swiftc "$SRC/router/VoiceFrameParser.swift" "$SRC/router/test_parser.swift" -o "$TEST/test_parser"
swiftc "$SRC/router/VoiceFrameParser.swift" "$SRC/router/PklgTailReader.swift" "$SRC/test_binary.swift" -o "$TEST/test_binary"
swiftc -import-objc-header "$SRC/opus_shim.h" -I"$OPUS_PREFIX/include" "$OPUS_PREFIX/lib/libopus.a" \
    "$SRC/OpusVoiceDecoder.swift" "$SRC/test_decoder.swift" -o "$TEST/test_decoder"
mkdir -p "$TEST/RemoteMapperMicCaptureTest.app/Contents/MacOS"
cp "$SRC/driver/CaptureTest-Info.plist" "$TEST/RemoteMapperMicCaptureTest.app/Contents/Info.plist"
clang -O2 -Wall -Wextra -Werror "$SRC/driver/srm_capture_test.c" -framework CoreFoundation -framework CoreAudio \
    -o "$TEST/RemoteMapperMicCaptureTest.app/Contents/MacOS/SiriRemoteMicCaptureTest"
cp "$SRC/install.sh" "$SRC/uninstall.sh" "$OUT/"
cp "$SRC/com.ws.RemoteMapper.Microphone.plist" "$OUT/"
cp "$SRC/COPYING" "$SRC/NOTICE.md" "$SRC/router/Opus-LICENSE.txt" "$SRC/driver/vendor/BlackHole-LICENSE.txt" "$OUT/"
codesign --force --sign - "$OUT/RemoteMapperMic.driver"
codesign --force --sign - "$OUT/rm_capture"
codesign --force --sign - "$OUT/srm_router"
codesign --force --sign - "$TEST/RemoteMapperMicCaptureTest.app"
"$TEST/srm_driver_contract_test" "$OUT/RemoteMapperMic.driver/Contents/MacOS/RemoteMapperMic"
"$TEST/srm_io_sim" "$OUT/RemoteMapperMic.driver/Contents/MacOS/RemoteMapperMic"
"$TEST/test_parser"
"$TEST/test_binary"
"$TEST/test_monitor_ring"
"$TEST/test_decoder"
echo "遥控器音频组件构建、协议与驱动验证通过：$OUT"
