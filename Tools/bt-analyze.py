#!/usr/bin/env python3
# bt-analyze.py
# 分析 bt-capture.sh 的记录：重组 L2CAP，按 ATT 句柄统计每个时间段收到的通知，
# 只在「挥动」段出现或明显增多的句柄就是可能的运动数据。
# 运行：python3 Tools/bt-analyze.py /tmp/remote-bt.pklg

import collections
import struct
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/remote-bt.pklg"
data = open(path, "rb").read()

phases = []
try:
    for line in open(path + ".phases"):
        stamp, name = line.split(maxsplit=1)
        phases.append((float(stamp), name.strip()))
except FileNotFoundError:
    pass


def phase_of(t):
    current = "开始前"
    for stamp, name in phases:
        if t >= stamp:
            current = name
    return current


# .pklg 记录（大端）：[长度 u32][秒 u32][微秒 u32][类型 u8][负载]，类型 0x03 为收到的 ACL，
# 0xFC、0xFD 是 PacketLogger 自己的信息记录，时间戳不可用于对齐
records = []
offset = 0
while offset + 13 <= len(data):
    length, secs, usecs = struct.unpack_from(">III", data, offset)
    if length < 9:
        break
    records.append((secs + usecs / 1e6, data[offset + 12], data[offset + 13:offset + 4 + length]))
    offset += 4 + length
packets = [r for r in records if r[1] < 0xF0]
# PacketLogger 的时间戳与系统时钟可能差一个时区偏移，按整半小时对齐到第一个时间段
shift = 0.0
if phases and packets:
    gap = phases[0][0] - packets[0][0]
    if abs(gap) > 1800:
        shift = round(gap / 1800) * 1800
first = packets[0][0] + shift if packets else None
last = packets[-1][0] + shift if packets else None

assembling = {}
stats = collections.defaultdict(lambda: collections.Counter())
lengths = collections.defaultdict(collections.Counter)
samples = {}
for stamp, kind, payload in packets:
    t = stamp + shift
    if kind != 0x03 or len(payload) < 4:
        continue
    header, _ = struct.unpack_from("<HH", payload, 0)
    acl, pb = header & 0x0FFF, (header >> 12) & 0x3
    body = payload[4:]
    if pb in (0b10, 0b00):
        if len(body) < 4:
            continue
        need = struct.unpack_from("<H", body, 0)[0] + 4
        assembling[acl] = (need, bytearray(body))
    elif acl in assembling:
        assembling[acl][1].extend(body)
    else:
        continue
    need, buffer = assembling[acl]
    if len(buffer) < need:
        continue
    del assembling[acl]
    cid = struct.unpack_from("<H", buffer, 2)[0]
    att = bytes(buffer[4:need])
    if cid != 0x0004 or len(att) < 3 or att[0] not in (0x1B, 0x1D):
        continue
    handle = struct.unpack_from("<H", att, 1)[0]
    key = (acl, handle)
    stats[key][phase_of(t)] += 1
    lengths[key][len(att) - 3] += 1
    samples.setdefault(key, att[3:19].hex())

names = [name for _, name in phases if name != "结束"] or ["开始前"]
print(f"记录时长 {((last or 0) - (first or 0)):.1f} 秒；时间段：{'、'.join(names)}"
      + (f"；时间戳已按 {shift / 3600:+.1f} 小时对齐" if shift else ""))
print(f"\n{'ACL':>5} {'ATT句柄':>8}  " + "  ".join(f"{n:>6}" for n in names) + "   常见长度          首条数据")
for key in sorted(stats, key=lambda k: -sum(stats[k].values())):
    counts = "  ".join(f"{stats[key][n]:>6}" for n in names)
    common = ", ".join(f"{size}B×{count}" for size, count in lengths[key].most_common(2))
    print(f"0x{key[0]:03x}   0x{key[1]:04x}  {counts}   {common:16s}  {samples[key]}")
if not stats:
    print("没有解析到任何 ATT 通知：确认遥控器已连接，并且 PacketLogger 正常记录")
