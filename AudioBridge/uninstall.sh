#!/bin/bash
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "请使用 sudo 卸载。" >&2; exit 1; }
SUPPORT="/Library/Application Support/RemoteMapperMicrophone"
launchctl bootout system/com.ws.RemoteMapper.Microphone 2>/dev/null || true
if [ -x "$SUPPORT/rm_capture" ]; then "$SUPPORT/rm_capture" --restore-traces; fi
rm -f /Library/LaunchDaemons/com.ws.RemoteMapper.Microphone.plist
rm -rf /Library/Audio/Plug-Ins/HAL/RemoteMapperMic.driver "$SUPPORT"
killall coreaudiod 2>/dev/null || true
echo "遥控器麦克风组件已卸载，蓝牙调试设置已恢复。"
