#!/bin/bash
# 安装可撤回的系统音频组件。仅安装本应用的 HAL 插件和按需服务。
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "请使用 sudo 运行，或在 RemoteMapper 中点击安装。" >&2; exit 1; }
cd "$(dirname "$0")"
PAYLOAD="$PWD"
SUPPORT="/Library/Application Support/RemoteMapperMicrophone"
HAL="/Library/Audio/Plug-Ins/HAL/RemoteMapperMic.driver"
PLIST="/Library/LaunchDaemons/com.ws.RemoteMapper.Microphone.plist"
LABEL="com.ws.RemoteMapper.Microphone"
[ -x /Applications/PacketLogger.app/Contents/Resources/packetlogger ] || { echo "请先将 Apple PacketLogger 安装到 /Applications。" >&2; exit 1; }
for target in RemoteMapperMic.driver rm_capture srm_router; do codesign --verify --strict "$PAYLOAD/$target"; done
[ ! -L "$SUPPORT" ] && [ ! -L "$HAL" ] && [ ! -L "$PLIST" ] || { echo "安装路径包含符号链接，已停止。" >&2; exit 1; }
cpu() { ps -Ao %cpu,comm | awk '/coreaudiod$/{sum+=$1} END{printf "%d",sum+0}'; }
[ "$(cpu)" -lt 85 ] || { echo "系统音频服务负载过高，请稍后安装。" >&2; exit 1; }
BACKUP="$(mktemp -d /private/tmp/remotemapper-mic.XXXXXX)"
had_support=0; had_hal=0; had_plist=0
if [ -d "$SUPPORT" ]; then ditto "$SUPPORT" "$BACKUP/support"; had_support=1; fi
if [ -d "$HAL" ]; then ditto "$HAL" "$BACKUP/driver"; had_hal=1; fi
if [ -f "$PLIST" ]; then cp "$PLIST" "$BACKUP/daemon.plist"; had_plist=1; fi
committed=0
rollback() {
    if [ "$committed" -eq 0 ]; then
        launchctl bootout "system/$LABEL" 2>/dev/null || true
        if [ -x "$SUPPORT/rm_capture" ]; then "$SUPPORT/rm_capture" --restore-traces || true; fi
        rm -rf "$HAL" "$SUPPORT"; rm -f "$PLIST"
        if [ "$had_support" -eq 1 ]; then ditto "$BACKUP/support" "$SUPPORT"; fi
        if [ "$had_hal" -eq 1 ]; then ditto "$BACKUP/driver" "$HAL"; fi
        if [ "$had_plist" -eq 1 ]; then cp "$BACKUP/daemon.plist" "$PLIST"; launchctl bootstrap system "$PLIST" || true; fi
        killall coreaudiod 2>/dev/null || true
        echo "安装未完成，已恢复原有音频组件。" >&2
    fi
    rm -rf "$BACKUP"
}
trap rollback EXIT
trap 'exit 130' INT TERM
launchctl bootout "system/$LABEL" 2>/dev/null || true
mkdir -p "$SUPPORT" "$(dirname "$HAL")"
chmod 755 "$SUPPORT"
# 重新安装前恢复上次采集状态。
if [ -x "$SUPPORT/rm_capture" ]; then "$SUPPORT/rm_capture" --restore-traces; fi
ditto "$PAYLOAD/RemoteMapperMic.driver" "$HAL"
for file in rm_capture srm_router uninstall.sh COPYING NOTICE.md Opus-LICENSE.txt BlackHole-LICENSE.txt; do cp "$PAYLOAD/$file" "$SUPPORT/"; done
chown -R root:wheel "$HAL" "$SUPPORT"
chmod 755 "$SUPPORT/rm_capture" "$SUPPORT/srm_router" "$SUPPORT/uninstall.sh"
"$SUPPORT/rm_capture" --save-traces
cp "$PAYLOAD/com.ws.RemoteMapper.Microphone.plist" "$PLIST"
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
killall coreaudiod 2>/dev/null || true
launchctl bootstrap system "$PLIST"
high=0
for ((second=1; second<=25; second++)); do
    sleep 1
    value="$(cpu)"
    if [ "$value" -ge 85 ]; then high=$((high+1)); else high=0; fi
    [ "$high" -lt 3 ] || { echo "系统音频服务异常，将自动撤回安装。" >&2; exit 2; }
done
if ! system_profiler SPAudioDataType | /usr/bin/grep -q 'Siri Remote Mic'; then
    echo "macOS 未加载遥控器麦克风，将撤回安装。" >&2; exit 3
fi
launchctl print "system/$LABEL" >/dev/null
committed=1
echo "Siri Remote Mic 已安装；25 秒系统音频服务观察通过。"
echo "卸载：sudo /bin/bash '$SUPPORT/uninstall.sh'"
