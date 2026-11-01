import json
import shlex
import time
from typing import Any

results = []

# virtio-multitouch reports positions from 0 to this on each axis.
ABS_MAX = 32767


def session(command):
    return (
        "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/$(id -u alice) "
        f"HOME=/home/alice WAYLAND_DISPLAY=wayland-1 {command} 2>&1"
    )


def hyprctl(*words):
    quoted = " ".join(shlex.quote(word) for word in words)
    return machine.execute(session(f"hyprctl --instance 0 {quoted}"))[1].strip()


def hypr_json(*words):
    return json.loads(hyprctl("-j", *words))


def ipc(*words, tries=6):
    quoted = " ".join(shlex.quote(word) for word in words)
    out = ""
    for _ in range(tries):
        out = machine.execute(session(f"morf ipc call {quoted}"))[1].strip()
        if "timed out" not in out:
            break
        machine.sleep(2)
    print(f"IPC {quoted} => {out[:400]}")
    try:
        reply = json.loads(out)
        if not reply.get("ok"):
            return None
        values = reply.get("result") or [None]
        value = values[0]
        if isinstance(value, str) and value[:1] in "[{":
            return json.loads(value)
        return value
    except ValueError:
        return None


def check(label, ok, detail=""):
    results.append((label, bool(ok)))
    print(f"RESULT {'ok  ' if ok else 'FAIL'} {label} {detail if not ok else ''}")


def eventually(read, seconds=30):
    value = read()
    for _ in range(seconds):
        if value:
            return value
        machine.sleep(1)
        value = read()
    return value


def mtt(kind: str, slot: int, tracking: int, axis: str = "x", value: int = 0) -> dict:
    return {
        "type": "mtt",
        "data": {"type": kind, "slot": slot, "tracking-id": tracking, "axis": axis, "value": value},
    }


def place(kind: str, slot: int, tracking: int, x: float, y: float) -> list:
    return [
        mtt(kind, slot, tracking),
        mtt("data", slot, tracking, "x", max(0, min(ABS_MAX, round(x * ABS_MAX)))),
        mtt("data", slot, tracking, "y", max(0, min(ABS_MAX, round(y * ABS_MAX)))),
    ]


def send_touch(events: list) -> None:
    qmp = machine.qmp_client
    assert qmp is not None
    arguments: Any = {"events": events}
    qmp.send("input-send-event", arguments)


tracking_ids = [100]


def stroke(starts, ends, steps=24, pause=0.016, hold=0.0, lift=True):
    """Lands a finger at each of `starts`, moves all to `ends` together, lifts.
    Positions are 0..1 along the panel's own axes, as the kernel sees them."""
    fingers = []
    for slot in range(len(starts)):
        tracking_ids[0] += 1
        fingers.append((slot, tracking_ids[0]))
    landed = []
    for (slot, tid), (x, y) in zip(fingers, starts):
        landed += place("begin", slot, tid, x, y)
    send_touch(landed)
    if hold:
        time.sleep(hold)
    for step in range(1, steps + 1):
        t = step / steps
        moved = []
        for (slot, tid), (x0, y0), (x1, y1) in zip(fingers, starts, ends):
            moved += place("update", slot, tid, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
        send_touch(moved)
        time.sleep(pause)
    if lift:
        send_touch([mtt("end", slot, -1) for slot, _tid in fingers])


def login(password):
    machine.start()
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("pgrep -u greeter -f 'morf.*greet'", timeout=180)
    machine.sleep(20)
    for _ in range(4):
        machine.send_key("ret")
        machine.sleep(4)
        machine.send_chars(password)
        machine.sleep(1)
        machine.send_chars("\n")
        status, _out = machine.execute("timeout 60 sh -c 'until pgrep -u alice Hyprland; do sleep 1; done'")
        if status == 0:
            break
    machine.wait_until_succeeds("pgrep -u alice Hyprland", timeout=120)
    machine.sleep(20)


def run(password):
    login(password)
    print("DEVICES", machine.succeed("cat /proc/bus/input/devices"))
    print("ACL", machine.execute("getfacl /dev/input/event* 2>&1 | head -40")[1])
    print("MONITORS", hyprctl("monitors"))
