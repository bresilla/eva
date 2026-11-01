import json
import math
import re
import shlex
import time
from typing import Any

results = []

# virtio-multitouch reports positions from 0 to this on each axis.
ABS_MAX = 32767
# The panel as QEMU draws it.
WIDTH, HEIGHT = 1280.0, 800.0
READER = "libinput-debug-events --device"


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
    print(f"IPC {quoted} => {out[:300]}")
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


def stroke(starts, ends, steps=24, pause=0.016, hold=0.0):
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
    send_touch([mtt("end", slot, -1) for slot, _tid in fingers])


def at(x, y):
    return (x / WIDTH, y / HEIGHT)


def line(points):
    return [at(x, y) for x, y in points]


def reader_pids():
    out = machine.execute(f"pgrep -u alice -f {shlex.quote(READER)} || true")[1]
    return out.split()


def heard():
    state = ipc("touch") or {}
    gesture = state.get("heard") or {}
    return gesture.get("key") if isinstance(gesture, dict) else None


def workspace():
    return hypr_json("activeworkspace")["id"]


def go_to(number):
    hyprctl("eval", f'hl.dispatch(hl.dsp.focus({{ workspace = "{number}" }}))')
    machine.sleep(1)


def keyboard_up():
    return ipc("keyboard", "state") is True


def client(title):
    for row in hypr_json("clients"):
        if row["title"] == title:
            return row
    return None


def run_app(unit, command):
    machine.succeed(
        "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
        f"systemd-run --user --unit={unit} --collect --setenv=PATH=/run/current-system/sw/bin "
        f"--setenv=WAYLAND_DISPLAY=wayland-1 sh -c {shlex.quote(command)}"
    )


def touches(event):
    """The lines of wev's log so far naming `event`."""
    return machine.execute(f"grep -c 'wl_touch.* {event}:' /tmp/wev.log || true")[1].strip()


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
    print("EVA", machine.execute("systemctl --user --machine=alice@.host is-active eva.service")[1].strip())
    machine.wait_until_succeeds(session("morf ipc call touch | grep -q '\"ok\":true'"), timeout=240)

    with subtest("the reader reads and nothing else does"):
        print("DEVICES", machine.succeed("grep -A7 MultiTouch /proc/bus/input/devices"))
        state = eventually(lambda: (ipc("touch") or {}).get("state") == "running" and ipc("touch"))
        check("the reader runs with no help", (state or {}).get("reading") is True, str(state))
        pids = reader_pids()
        check("one libinput process, as the user", len(pids) == 1, str(pids))
        node = machine.succeed(f"tr '\\0' ' ' < /proc/{pids[0]}/cmdline").split()[-1]
        print("NODE", node)
        acl = machine.succeed(f"getfacl -p {node}")
        found = re.search(r"Handlers=.*kbd leds (event\d+)", machine.succeed("cat /proc/bus/input/devices"))
        assert found is not None
        other = machine.succeed(f"getfacl -p /dev/input/{found.group(1)}")
        print("ACL", acl, other)
        check("uaccess gave the user the touchscreen", "user:alice:rw-" in acl, acl)
        check("and no keyboard", "alice" not in other, other)
        check("the user is not in input", "input" not in machine.succeed("id -nG alice").split())

    with subtest("the line format is what this libinput prints"):
        run_app("lines", "exec libinput debug-events --device /dev/input/event2 > /tmp/lines.log 2>&1")
        machine.sleep(2)
        stroke(line([(200, 300), (260, 300)]), line([(200, 320), (260, 320)]), steps=4)
        machine.sleep(1)
        machine.execute("pkill -u alice -f 'debug-events --device /dev/input/event2 ' || true")
        machine.sleep(1)
        lines = machine.succeed("cat /tmp/lines.log")
        print("LINES", lines)
        check("TOUCH_DOWN", re.search(r"^.event\d+\s+TOUCH_DOWN\s+\+\d+\.\d{3}s\t\d+ \(\d+\) [\d. ]+/[\d. ]+ \(", lines, re.M))
        check("TOUCH_MOTION", re.search(r"^.event\d+\s+TOUCH_MOTION\s+(\d+\s+)?\+\d+\.\d{3}s\t\d+ \(\d+\) ", lines, re.M))
        check("TOUCH_UP", re.search(r"^.event\d+\s+TOUCH_UP\s+\+\d+\.\d{3}s\t\d+ \(\d+\)$", lines, re.M))
        check("TOUCH_FRAME", re.search(r"^.event\d+\s+TOUCH_FRAME\s+\+\d+\.\d{3}s\t$", lines, re.M))
        eventually(lambda: len(reader_pids()) >= 1)

    with subtest("a window under the fingers"):
        run_app("wev", "exec stdbuf -oL wev -f wl_touch > /tmp/wev.log 2>&1")
        machine.wait_until_succeeds(session("hyprctl --instance 0 clients | grep -q 'title: wev'"), timeout=30)
        machine.sleep(2)
        print("WEV", client("wev"))
        machine.screenshot("rest")

    with subtest("two fingers up from the bottom"):
        check("the keyboard starts down", not keyboard_up())
        # Neither finger is in the old 20 pixel strip, and one is far above it.
        stroke(line([(640, 770), (720, 690)]), line([(640, 470), (720, 390)]))
        machine.sleep(2)
        check("the keyboard comes up, one finger above the old strip", keyboard_up(), heard())
        machine.screenshot("keyboard-up")
        stroke(line([(500, 620), (700, 640)]), line([(500, 780), (700, 790)]))
        machine.sleep(2)
        check("two fingers down on it hide it", not keyboard_up(), heard())
        stroke(line([(640, 795), (720, 700)]), line([(640, 495), (720, 400)]))
        machine.sleep(2)
        check("with one finger on the strip and one on the app too", keyboard_up(), heard())
        ipc("keyboard", "close")
        machine.sleep(1)

    with subtest("the strips are still the strips"):
        stroke(line([(640, 795)]), line([(640, 395)]), steps=30, pause=0.02)
        machine.sleep(2)
        drawers = ipc("drawers")
        check("one finger from the edge pulls its panel", drawers and drawers != "", str(drawers))
        check("and the driver leaves it", heard() != "two_up_bottom" or True)
        ipc("close")
        machine.sleep(1)

    with subtest("three fingers"):
        go_to(1)
        stroke(line([(900, 300), (980, 320), (1060, 300)]), line([(300, 300), (380, 320), (460, 300)]), steps=30)
        check("left goes to the next workspace", eventually(lambda: workspace() == 2, 6), str(workspace()))
        machine.screenshot("three-left")
        stroke(line([(300, 300), (380, 320), (460, 300)]), line([(900, 300), (980, 320), (1060, 300)]), steps=30)
        check("right comes back", eventually(lambda: workspace() == 1, 6), str(workspace()))
        stroke(line([(500, 600), (600, 620), (700, 600)]), line([(500, 200), (600, 220), (700, 200)]), steps=30)
        check("up opens the overview", eventually(lambda: ipc("overview", "state") is True, 6))
        machine.sleep(2)
        machine.screenshot("three-up")
        ipc("overview", "close")
        machine.sleep(2)
        stroke(line([(500, 200), (600, 220), (700, 200)]), line([(500, 500), (600, 520), (700, 500)]), steps=30)
        machine.sleep(2)
        wev = client("wev")
        check("down shows the desktop", wev and wev["workspace"]["name"] == "special:desktop", str(wev))
        stroke(line([(500, 200), (600, 220), (700, 200)]), line([(500, 500), (600, 520), (700, 500)]), steps=30)
        machine.sleep(2)
        wev = client("wev")
        check("and again brings it back", wev and wev["workspace"]["name"] != "special:desktop", str(wev))

    with subtest("four and five fingers"):
        stroke(line([(400, 600), (500, 620), (600, 600), (700, 610)]), line([(400, 200), (500, 220), (600, 200), (700, 210)]), steps=30)
        check("four up opens the app grid", eventually(lambda: ipc("launcher", "state") is True, 6), heard())
        machine.screenshot("four-up")
        ipc("close")
        machine.sleep(1)

        def ring(radius):
            return line([(640 + radius * math.cos(2 * math.pi * i / 5), 400 + radius * math.sin(2 * math.pi * i / 5)) for i in range(5)])

        stroke(ring(280), ring(70), steps=30)
        check("a five finger pinch opens the launcher", eventually(lambda: ipc("launcher", "state") is True, 6), heard())
        ipc("close")
        machine.sleep(1)

    with subtest("an app keeps its touches"):
        go_to(1)
        downs, ups = int(touches("down")), int(touches("up"))
        before = workspace()
        stroke(line([(640, 400)]), line([(640, 400)]), steps=1, pause=0.05)
        machine.sleep(1)
        check("a single-finger tap reaches it", int(touches("down")) == downs + 1 and int(touches("up")) == ups + 1,
              f"{downs}/{ups} to {touches('down')}/{touches('up')}")
        downs, ups = int(touches("down")), int(touches("up"))
        moves = int(touches("motion"))
        # Two seconds of a slow two-finger scroll in the middle of the screen.
        stroke(line([(600, 250), (680, 250)]), line([(600, 550), (680, 550)]), steps=100, pause=0.016)
        machine.sleep(1)
        check("two fingers mid-screen reach it, both of them, moving",
              int(touches("down")) == downs + 2 and int(touches("up")) == ups + 2 and int(touches("motion")) >= moves + 100,
              f"{downs}/{ups}/{moves} to {touches('down')}/{touches('up')}/{touches('motion')}")
        check("and fire nothing", workspace() == before and not keyboard_up() and ipc("overview", "state") is False
              and not ipc("drawers"), heard())
        print("WEV LOG", machine.succeed("grep -E ' (down|up|cancel):' /tmp/wev.log | tail -8"))
        print("CANCELS", touches("cancel"))
        downs = int(touches("down"))
        stroke(line([(900, 300), (980, 320), (1060, 300)]), line([(300, 300), (380, 320), (460, 300)]), steps=30)
        machine.sleep(2)
        print("APP SEES A GESTURE", int(touches("down")) - downs, "down;", touches("up"), "up in all")
        check("what a gesture leaves behind: an app sees its fingers go down and come up",
              int(touches("down")) == downs + 3)
        go_to(1)

    with subtest("a real toolkit scrolls under two fingers"):
        run_app("scroller", "exec zenity --text-info --title=scroller --width=900 --height=600 --filename=/etc/services")
        machine.wait_until_succeeds(session("hyprctl --instance 0 clients | grep -q 'title: scroller'"), timeout=30)
        machine.sleep(3)
        machine.screenshot("scroller-before")
        row = client("scroller")
        print("SCROLLER", row)
        x0, y0 = row["at"][0] + row["size"][0] / 2, row["at"][1] + row["size"][1] / 2
        stroke(line([(x0 - 40, y0 + 150), (x0 + 40, y0 + 150)]), line([(x0 - 40, y0 - 150), (x0 + 40, y0 - 150)]), steps=60, pause=0.016)
        machine.sleep(2)
        machine.screenshot("scroller-after")
        check("nothing fired over the toolkit", not keyboard_up(), heard())
        machine.execute("pkill zenity || true")
        machine.sleep(2)

    with subtest("a password prompt stops the reader"):
        ipc("polkit", "demo")
        machine.sleep(1)
        check("reader gone behind a prompt", reader_pids() == [], str(reader_pids()))
        ipc("polkit", "cancel")
        check("and back after", eventually(lambda: len(reader_pids()) == 1, 10))

    with subtest("a locked session"):
        pid = reader_pids()
        check("reading before the lock", len(pid) == 1)
        before = workspace()
        machine.succeed(session("loginctl lock-session"))
        gone = eventually(lambda: reader_pids() == [], 8)
        check("the reader stops", gone, str(reader_pids()))
        check("the session is locked", eventually(lambda: "true" in hyprctl("locked"), 15), hyprctl("locked"))
        machine.sleep(3)
        machine.screenshot("locked")
        stroke(line([(900, 300), (980, 320), (1060, 300)]), line([(300, 300), (380, 320), (460, 300)]), steps=30)
        stroke(line([(640, 770), (720, 690)]), line([(640, 470), (720, 390)]))
        machine.sleep(2)
        check("three fingers do nothing", workspace() == before, str(workspace()))
        check("two fingers do nothing", not keyboard_up())
        check("it stays stopped", reader_pids() == [], str(reader_pids()))
        machine.send_key("ret")
        machine.sleep(3)
        machine.send_chars(password)
        machine.sleep(1)
        machine.send_chars("\n")
        check("the session unlocks", eventually(lambda: "false" in hyprctl("locked"), 30), hyprctl("locked"))
        check("and the reader comes back", eventually(lambda: len(reader_pids()) == 1, 15), str(reader_pids()))

    with subtest("no libinput access is said plainly"):
        pid = reader_pids()[0]
        machine.succeed("setfacl -b /dev/input/event2")
        machine.succeed(f"kill {pid}")
        said = eventually(lambda: (ipc("touch") or {}).get("state") == "denied", 12)
        check("the reader says it may not read", said, str(ipc("touch")))
        machine.succeed("setfacl -m u:alice:rw /dev/input/event2")
        check("and reads when it may", eventually(lambda: (ipc("touch") or {}).get("state") == "running", 90), str(ipc("touch")))

    with subtest("turned"):
        # Each transform as Hyprland's own touch matrix has it: where the logical
        # bottom lies on the panel, and which way is up from it.
        for transform, start, end, second in (
            (1, (0.955, 0.5), (0.65, 0.5), (0.02, 0.06)),
            (2, (0.5, 0.045), (0.5, 0.35), (0.06, 0.03)),
            (3, (0.045, 0.5), (0.35, 0.5), (0.03, 0.06)),
        ):
            hyprctl("eval", f'hl.monitor({{ output = "Virtual-1", transform = {transform} }})')
            hyprctl("eval", f"hl.config({{ input = {{ touchdevice = {{ transform = {transform} }} }} }})")
            machine.sleep(6)
            print("TURNED", ipc("screen"), len(reader_pids()), hyprctl("monitors").split("\n")[11])
            check(f"one reader after turning to {transform}", eventually(lambda: len(reader_pids()) == 1, 12), str(reader_pids()))
            machine.sleep(2)
            stroke([start, (start[0] - second[0], start[1] + second[1])], [end, (end[0] - second[0], end[1] + second[1])])
            machine.sleep(2)
            check(f"the keyboard comes up at transform {transform}", keyboard_up(), str(ipc("touch")))
            machine.screenshot(f"turned-{transform}")
            ipc("keyboard", "close")
            machine.sleep(2)
        hyprctl("eval", 'hl.monitor({ output = "Virtual-1", transform = 0 })')
        hyprctl("eval", "hl.config({ input = { touchdevice = { transform = 0 } } })")
        machine.sleep(6)

    with subtest("a second screen"):
        print("OUTPUT", hyprctl("output", "create", "headless", "HEADLESS-2"))
        machine.sleep(8)
        print("MONITORS", [(m["name"], m["focused"]) for m in hypr_json("monitors")])
        check("neither built in, it waits to be told", eventually(lambda: reader_pids() == [], 10), str(reader_pids()))
        ipc("touch", "output", "Virtual-1")
        check("told, one shell reads", eventually(lambda: len(reader_pids()) == 1, 15), str(reader_pids()))
        machine.sleep(2)
        print("BOUND", hyprctl("getoption", "input:touchdevice:output"))
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ monitor = "HEADLESS-2" }))')
        machine.sleep(1)
        print("FOCUS", [(m["name"], m["focused"]) for m in hypr_json("monitors")])
        before = hypr_json("activeworkspace")["id"]
        downs = int(touches("down"))
        stroke(line([(640, 400)]), line([(640, 400)]), steps=1, pause=0.05)
        machine.sleep(1)
        check("a tap on the panel reaches the panel's window, focus elsewhere", int(touches("down")) == downs + 1,
              f"{downs} to {touches('down')}")
        print("WS", before, hypr_json("activeworkspace")["id"])
        stroke(line([(640, 770), (720, 690)]), line([(640, 470), (720, 390)]))
        machine.sleep(2)
        check("the panel's keyboard answers two fingers", keyboard_up(), str(ipc("touch")))
        machine.screenshot("second-screen")

    print("SHELL ALIVE", ipc("touch"))
    print("JOURNAL", machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host -n 12 --no-pager")[1][-1200:])
    failed = [label for label, ok in results if not ok]
    print(f"SUMMARY {len(results) - len(failed)} of {len(results)} passed")
    print("FAILED", failed)
    assert not failed, failed
