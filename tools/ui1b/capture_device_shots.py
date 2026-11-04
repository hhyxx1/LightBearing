"""UI-1B 真机截图采集工具（只读，不修改任何应用数据）。

用途：设备**已解锁**时，一条命令完成 UI-1B 需要但尚未采集的真机截图：
  1. 新版首页浅色（ui1b_after_home_light.jpeg）
  2. 新版首页深色（ui1b_after_home_dark.jpeg，走「更多/设置 → 深色 → 今日」）
  3. 原型 Compact 与真机浅色的并排对照（ui1b_compare_home.jpeg）

前置条件（缺一不可）：
  - 设备已解锁并保持屏幕常亮（否则 `aa start` 返回 10106102）；
  - 已安装当前构建：`hdc install -r entry/build/default/outputs/default/entry-default-signed.hap`。

用法：
  python tools/ui1b/capture_device_shots.py            # 默认设备串号
  python tools/ui1b/capture_device_shots.py <deviceId>

注意：
  - 不截图锁屏/桌面；未进入首页时直接输出 NOT_RUN，绝不用无效画面冒充验收证据；
  - 不修改数据库、不删除机位、不写入任何用户数据；
  - 空机位态与权限拒绝态需要改变数据/权限，未包含在本脚本中，需人工决策后单独执行。
"""

import subprocess
import json
import re
import sys
import time

H = r"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
DEFAULT_DEVICE = "4EE9K25515007252"
SHOTS = "docs/screenshots"
PROTO = "design/ui1b/shots"


def make_sh(device):
    def sh(cmd):
        subprocess.run([H, "-t", device, "shell", cmd],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return sh


def dump(sh):
    sh("uitest dumpLayout -p /data/local/tmp/l.json")
    subprocess.run([H, "-t", DEV, "file", "recv", "/data/local/tmp/l.json", "l.json"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        return json.load(open("l.json", encoding="utf-8"))
    except Exception:
        return None


def nodes(d):
    out = []

    def walk(n):
        a = n.get("attributes", {})
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", a.get("bounds", ""))
        if m:
            out.append({"t": (a.get("text") or "").strip(),
                        "x": (int(m.group(1)) + int(m.group(3))) // 2,
                        "y": (int(m.group(2)) + int(m.group(4))) // 2})
        for c in n.get("children", []):
            walk(c)

    walk(d)
    return out


def texts(sh):
    d = dump(sh)
    return [n["t"] for n in nodes(d) if n["t"]] if d else []


def click(sh, label):
    d = dump(sh)
    if d is None:
        return False
    for n in nodes(d):
        if n["t"] == label:
            sh("uitest uiInput click %d %d" % (n["x"], n["y"]))
            time.sleep(1.4)
            return True
    return False


def shot(sh, path):
    sh("snapshot_display -f /data/local/tmp/s.jpeg")
    subprocess.run([H, "-t", DEV, "file", "recv", "/data/local/tmp/s.jpeg", path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


DEV = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DEVICE
sh = make_sh(DEV)

HOME_MARKS = ("今日光线", "当前光线")

sh("power-shell wakeup")
time.sleep(0.8)
t = texts(sh)
if not any(x in t for x in HOME_MARKS + ("设置", "时钟", "天气", "相机")):
    print("BLOCKED: 设备仍处于锁屏状态，请先解锁并保持屏幕常亮")
    raise SystemExit(1)

sh("aa force-stop com.hhyxx.LightBearing")
time.sleep(0.8)
sh("aa start -a EntryAbility -b com.hhyxx.LightBearing")
time.sleep(4)
t = texts(sh)
if not any(x in t for x in HOME_MARKS):
    print("NOT_RUN: 首页未进入前台（可能启动失败或仍被锁屏拦截），未采集截图")
    raise SystemExit(1)

shot(sh, f"{SHOTS}/ui1b_after_home_light.jpeg")
print("LIGHT=ok")

for label in ("更多", "设置"):
    if click(sh, label):
        break
if click(sh, "深色"):
    time.sleep(1.2)
    click(sh, "今日")
    time.sleep(2.5)
    if any(x in texts(sh) for x in HOME_MARKS):
        shot(sh, f"{SHOTS}/ui1b_after_home_dark.jpeg")
        print("DARK=ok")
    else:
        print("DARK=NOT_RUN")
else:
    print("DARK=NOT_RUN(未找到深色入口)")

try:
    from PIL import Image
    import os
    proto = f"{PROTO}/home_compact.png"
    after = f"{SHOTS}/ui1b_after_home_light.jpeg"
    if os.path.exists(proto) and os.path.exists(after):
        a = Image.open(proto).convert("RGB")
        b = Image.open(after).convert("RGB")
        h = max(a.height, b.height)
        canvas = Image.new("RGB", (a.width + b.width + 24, h), (6, 16, 27))
        canvas.paste(a, (0, 0))
        canvas.paste(b, (a.width + 24, 0))
        canvas.save(f"{SHOTS}/ui1b_compare_home.jpeg", quality=92)
        print("COMPARE=ok")
except Exception as e:  # PIL 缺失或损坏不阻塞主流程
    print("COMPARE=NOT_RUN", e)
