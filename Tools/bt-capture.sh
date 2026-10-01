#!/bin/bash
# bt-capture.sh
# 抓取 Siri Remote 的蓝牙空口数据，按时间段提示操作，用于确认挥动遥控器时是否有运动数据包。
# 做法与音频组件相同：临时打开 HCI 实时跟踪，用 PacketLogger 记录，结束后恢复原设置。
# 运行：sudo Tools/bt-capture.sh [输出文件] [motion|touch]   需要 /Applications/PacketLogger.app
#   motion（默认）：静止 / 挥动 / 静止 / 按键触控，确认有没有运动数据
#   touch：只轻触而不按下各个按键，确认触控板以外的按键有没有触摸感应
# 分析：python3 Tools/bt-analyze.py 输出文件

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "请用 sudo 运行：sudo $0"; exit 1; }

OUT=${1:-/tmp/remote-bt.pklg}
PLAN=${2:-motion}
LOGGER=/Applications/PacketLogger.app/Contents/Resources/packetlogger
DEBUG=/Library/Preferences/com.apple.MobileBluetooth.debug.plist
[[ -x $LOGGER ]] || { echo "缺少 PacketLogger：$LOGGER"; exit 1; }

BACKUP=$(mktemp)
if [[ -f $DEBUG ]]; then cp "$DEBUG" "$BACKUP"; HAD_DEBUG=1; else HAD_DEBUG=0; fi
LOGGER_PID=
restore() {
    [[ -n $LOGGER_PID ]] && kill "$LOGGER_PID" 2>/dev/null || true
    if [[ $HAD_DEBUG == 1 ]]; then cp "$BACKUP" "$DEBUG"; else rm -f "$DEBUG"; fi
    killall -USR1 bluetoothd 2>/dev/null || true
    rm -f "$BACKUP"
    echo "已恢复蓝牙调试设置"
}
trap restore EXIT

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
PB=/usr/libexec/PlistBuddy
$PB -c "Delete :HCITraces" "$DEBUG" >/dev/null 2>&1 || true
$PB -c "Add :HCITraces dict" \
    -c "Add :HCITraces:StackDebugEnabled bool true" \
    -c "Add :HCITraces:HCILiveTraces bool true" \
    -c "Add :HCITraces:HIDTrace bool true" \
    -c "Add :HCITraces:HCISkipAuth bool true" \
    -c "Add :HCITraces:HCIFileTraces bool false" "$DEBUG" >/dev/null
chmod 644 "$DEBUG"
killall -USR1 bluetoothd
sleep 2

rm -f "$OUT" "$OUT.phases"
"$LOGGER" convert -o "$OUT" >/dev/null 2>&1 &
LOGGER_PID=$!
sleep 1

phase() {
    local name=$1 seconds=$2 hint=$3
    echo "$(now) $name" >> "$OUT.phases"
    printf '\n▶ %s（%d 秒）：%s\n' "$name" "$seconds" "$hint"
    for ((i = seconds; i > 0; i--)); do printf '\r  剩余 %2d 秒' "$i"; sleep 1; done
    printf '\r  完成        \n'
}

echo "开始记录。请按提示操作遥控器，每段开始时会提示。"
if [[ $PLAN == touch ]]; then
    # 每段轻触前后都摸一下触控板做对照：对照段有触摸数据、中间段没有，才能说明那些键没有触控；
    # 最后闲置一会儿再直接摸触控板，看触摸能不能唤醒休眠的遥控器
    phase 唤醒 3 "按一下返回键唤醒遥控器（期间不要用键盘和鼠标）"
    phase 对照1 5 "马上用手指在触控板上来回滑，不要按下去"
    phase 轻触按键 8 "轻轻摸返回、TV、播放、静音、音量、电源键，不要按下去"
    phase 对照2 5 "再在触控板上来回滑，不要按下去"
    phase 轻触侧键 5 "轻轻摸侧面的 Siri 键，不要按下去"
    phase 对照3 5 "再在触控板上来回滑，不要按下去"
    phase 闲置 20 "把遥控器放下，完全不要碰"
    phase 闲置后触控板 6 "直接在触控板上来回滑，不要按任何键"
else
    phase 静止1 6 "把遥控器平放在桌上，不要碰"
    phase 挥动 15 "拿起遥控器挥动、倾斜、翻转、甩动；不要碰任何按键和触控面"
    phase 静止2 6 "再放回桌上，不要碰"
    phase 按键触控 10 "在触控面上滑几下，再按几下按键（不要按住 Siri 键说话）"
fi
echo "$(now) 结束" >> "$OUT.phases"

kill "$LOGGER_PID" 2>/dev/null || true
wait "$LOGGER_PID" 2>/dev/null || true
LOGGER_PID=
[[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER" "$OUT" "$OUT.phases"
echo "记录已保存：${OUT}（时间段：${OUT}.phases）"
