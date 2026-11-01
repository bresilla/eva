import json
import shlex

results = []


def session(command):
    return (
        "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/$(id -u alice) "
        f"HOME=/home/alice WAYLAND_DISPLAY=wayland-1 {command} 2>&1"
    )


def hyprctl(*words):
    quoted = " ".join(shlex.quote(word) for word in words)
    return machine.execute(session(f"hyprctl --instance 0 {quoted}"))[1].strip()


def ipc(*words):
    quoted = " ".join(shlex.quote(word) for word in words)
    # A software GPU on a busy machine can hold the shell for seconds at a time.
    for _ in range(6):
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


def clients():
    return json.loads(hyprctl("-j", "clients"))


def client(title):
    for row in clients():
        if row["title"] == title:
            return row
    return None


def workspaces():
    return json.loads(hyprctl("-j", "workspaces"))


def check(label, ok, detail=""):
    results.append((label, bool(ok)))
    print(f"RESULT {'ok  ' if ok else 'FAIL'} {label} {detail if not ok else ''}")


def near(a, b, tolerance=6):
    return abs(a - b) <= tolerance


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


def open_window(title):
    hyprctl("eval", f'hl.dispatch(hl.dsp.exec_cmd("foot -T {title} sleep 3600"))')
    machine.wait_until_succeeds(session(f"hyprctl --instance 0 clients | grep -q 'title: {title}'"), timeout=30)


def focus(title):
    row = client(title)
    hyprctl("eval", f'hl.dispatch(hl.dsp.focus({{ window = "address:{row["address"]}" }}))')
    machine.sleep(1)


def pointer(x, y):
    machine.succeed(f"YDOTOOL_SOCKET=/tmp/ydotool ydotool mousemove --absolute -x {x} -y {y}")


def run(password):
    login(password)
    machine.succeed("ydotoold --socket-path=/tmp/ydotool --socket-perm=0666 >/tmp/ydotoold.log 2>&1 &")
    machine.sleep(1)
    print("EVA", machine.execute("systemctl --user --machine=alice@.host is-active eva.service")[1].strip())
    machine.wait_until_succeeds(session("morf ipc call windows | grep -q '\"ok\":true'"), timeout=240)
    print("BINDS", hyprctl("binds")[:300])
    binds = json.loads(hyprctl("-j", "binds"))
    keys = {(bind.get("modmask"), bind.get("key")) for bind in binds}
    check("default keys are bound", (64, "Tab") in keys and (8, "Tab") in keys, str(sorted(k for k in keys if k[0] in (8, 64)))[:300])
    for title in ("one", "two", "three"):
        open_window(title)
    machine.sleep(2)
    listed = ipc("windows")
    check("the shell lists the real windows", listed and len([w for w in listed if w.get("class") == "foot"]) == 3)

    with subtest("overview"):
        machine.send_key("meta_l-tab")
        machine.sleep(4)
        check("Super+Tab opens the overview", ipc("overview", "state") is True)
        machine.screenshot("overview")
        shots = ipc("windows", "shots") or {}
        print("SHOTS", shots)
        check("window pictures arrive on Hyprland", any(v for k, v in shots.items() if k != "refused"), str(shots)[:300])
        check("the eva process survived the captures", ipc("overview", "state") is True)
        machine.send_chars("two")
        machine.sleep(2)
        machine.screenshot("overview-filtered")
        machine.send_key("esc")
        machine.sleep(2)
        check("escape closes it", ipc("overview", "state") is False)

    with subtest("a window on a hidden workspace"):
        three = client("three")
        hyprctl("eval", f'hl.dispatch(hl.dsp.window.move({{ workspace = "2", follow = false, window = "address:{three["address"]}" }}))')
        machine.sleep(1)
        ipc("overview", "open")
        machine.sleep(4)
        shots = ipc("windows", "shots") or {}
        check("a hidden window has a picture", shots.get(three["address"]), str(shots)[:300])
        machine.screenshot("overview-hidden")
        ipc("overview", "close")
        machine.sleep(2)
        hyprctl("eval", f'hl.dispatch(hl.dsp.window.move({{ workspace = "1", follow = false, window = "address:{three["address"]}" }}))')
        machine.sleep(1)

    with subtest("switcher"):
        focus("one")
        focus("two")
        machine.send_key("alt-tab")
        machine.sleep(2)
        active = json.loads(hyprctl("-j", "activewindow"))
        check("a quick Alt+Tab goes to the last window", active.get("title") == "one", str(active.get("title")))
        print("AFTER TAP", ipc("switcher", "state"))
        ipc("switcher", "cancel")
        machine.sleep(1)
        focus("two")
        focus("one")
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 56:1 15:1 15:0")
        machine.sleep(2)
        held = ipc("switcher", "state") or {}
        print("HELD", held)
        machine.screenshot("switcher-held")
        check("held, Alt+Tab shows the switcher", held.get("shown") is True)
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 56:0")
        machine.sleep(3)
        active = json.loads(hyprctl("-j", "activewindow"))
        check("letting Alt go goes to the window chosen", active.get("title") == held.get("title"),
              f'{active.get("title")} for {held.get("title")}')
        print("AFTER RELEASE", ipc("switcher", "state"))
        ipc("switcher", "cancel")
        ipc("switcher", "next", "free")
        machine.sleep(2)
        machine.screenshot("switcher")
        check("the switcher shows held", (ipc("switcher", "state") or {}).get("shown") is True)
        ipc("switcher", "commit")
        machine.sleep(1)

    with subtest("snap"):
        focus("one")
        ipc("snap", "left")
        machine.sleep(2)
        one = client("one")
        check("snap left floats and places", one["floating"] and near(one["at"][0], 18) and near(one["size"][0], 618), str(one["at"] + one["size"]))
        machine.screenshot("snap-assist")
        machine.send_key("esc")
        machine.sleep(1)
        ipc("snap", "picker")
        machine.sleep(2)
        machine.screenshot("snap-picker")
        machine.send_key("esc")
        machine.sleep(1)
        ipc("snap", "layout", "thirds")
        machine.sleep(2)
        check("a layout places the workspace", client("two")["floating"], str(client("two")))
        machine.screenshot("snap-thirds")

    with subtest("a drag lands"):
        two = client("two")
        focus("two")
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 125:1")
        pointer(two["at"][0] + 60, two["at"][1] + 60)
        machine.sleep(1)
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x40")
        machine.sleep(1)
        print("DRAGGING", ipc("snap", "state"))
        pointer(1270, 400)
        machine.sleep(2)
        machine.screenshot("snap-drag")
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x80")
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 125:0")
        machine.sleep(2)
        two = client("two")
        check("a window dragged to the right edge lands on the right half", near(two["at"][0], 644, 10), str(two["at"] + two["size"]))
        machine.send_key("esc")
        machine.sleep(1)

    with subtest("window state"):
        focus("three")
        ipc("keep_above")
        machine.sleep(1)
        check("keep above floats it", client("three")["floating"])
        ipc("opacity", "0.7")
        machine.sleep(1)
        print("OPACITY", ipc("windows")[0] if ipc("windows") else None)
        machine.screenshot("opacity")
        ipc("pip")
        machine.sleep(2)
        three = client("three")
        check("picture in picture pins it small", three["pinned"] and three["size"][0] < 500, str(three))
        machine.screenshot("pip")
        before = client("three")["at"]
        pointer(before[0] + 40, before[1] + 40)
        machine.sleep(1)
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x40")
        machine.sleep(1)
        pointer(before[0] - 160, before[1] - 120)
        machine.sleep(2)
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x80")
        machine.sleep(2)
        after = client("three")["at"]
        check("a real pointer drags the picture", near(after[0], before[0] - 200, 30), f"{before} to {after}")
        ipc("pip")
        machine.sleep(2)
        check("leaving picture in picture unpins it", not client("three")["pinned"])
        print("AFTER PIP", client("three")["floating"], json.loads(hyprctl("-j", "activewindow")).get("title"))
        focus("three")
        ipc("float")
        machine.sleep(2)
        print("AFTER FLOAT", client("three")["floating"], json.loads(hyprctl("-j", "activewindow")).get("title"))
        check("float", client("three")["floating"])
        ipc("float")
        machine.sleep(2)
        print("AFTER TILE", client("three")["floating"], json.loads(hyprctl("-j", "activewindow")).get("title"))
        print("SENT", (ipc("windows", "sent") or [])[:4])
        check("float again tiles", not client("three")["floating"])

    with subtest("split"):
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ workspace = "4" }))')
        machine.sleep(1)
        open_window("left")
        open_window("right")
        machine.sleep(1)
        print("PAIR", ipc("split_pair"))
        width = client("right")["size"][0]
        ipc("split_nudge", "-0.1")
        machine.sleep(2)
        check("the divider moves a signed share of the screen", abs(client("right")["size"][0] - width) > 60,
              f'{width} to {client("right")["size"][0]}')
        machine.screenshot("split")
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ workspace = "1" }))')
        machine.sleep(1)

    with subtest("workspaces"):
        ipc("workspace_name", "code")
        machine.sleep(1)
        check("rename reaches the compositor", any(w["name"] == "code" for w in workspaces()), str(workspaces()))
        ipc("workspace_layout", "master")
        machine.sleep(1)
        check("a workspace's layout changes live", any(w.get("tiledLayout") == "master" for w in workspaces()), str(workspaces()))
        machine.screenshot("layout-master")
        ipc("workspace_layout", "next")
        machine.sleep(1)
        check("the next layout", any(w.get("tiledLayout") == "scrolling" for w in workspaces()), str(workspaces()))
        ipc("workspace_layout", "dwindle")
        focus("three")
        ipc("scratchpad", "send", "scratch")
        machine.sleep(1)
        check("a window goes to a scratchpad", client("three")["workspace"]["name"] == "special:scratch", str(client("three")))
        ipc("scratchpad", "scratch")
        machine.sleep(2)
        machine.screenshot("scratchpad")
        monitors = json.loads(hyprctl("-j", "monitors"))
        check("a scratchpad shows", monitors[0]["specialWorkspace"]["name"] == "special:scratch", str(monitors[0]["specialWorkspace"]))
        ipc("scratchpad", "scratch")
        machine.sleep(1)
        hyprctl("eval", f'hl.dispatch(hl.dsp.window.move({{ workspace = "1", follow = false, window = "address:{client("three")["address"]}" }}))')
        machine.sleep(1)
        ipc("show_desktop")
        machine.sleep(1)
        check("show desktop clears the workspace", client("one")["workspace"]["name"] == "special:desktop", str(client("one")))
        ipc("show_desktop")
        machine.sleep(1)
        check("and brings them back", client("one")["workspace"]["name"] != "special:desktop", str(client("one")))
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ workspace = "2" }))')
        machine.sleep(1)
        machine.screenshot("workspace-osd")
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ workspace = "1" }))')
        machine.sleep(2)

    with subtest("dock"):
        ipc("dock", "hide", "off")
        print("DOCK", ipc("dock", "on"))
        machine.sleep(10)
        machine.screenshot("dock")
        state = ipc("dock", "state") or ipc("dock", "state") or {}
        print("DOCK STATE", state)
        check("the dock takes the windows", state.get("rows", 0) >= 1, str(state))
        check("a dock that stays out keeps windows clear of it", json.loads(hyprctl("-j", "monitors"))[0]["reserved"][3] > 10,
              str(json.loads(hyprctl("-j", "monitors"))[0]["reserved"]))
        print("FRAMES", machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host --no-pager | grep -E 'took [0-9]{4,}' | tail -5")[1][-500:])

    with subtest("hot corner"):
        ipc("corner", "top_left", "overview", "")
        machine.sleep(1)
        pointer(640, 400)
        machine.sleep(1)
        pointer(1, 1)
        machine.sleep(2)
        check("a corner runs its action under a real pointer", ipc("overview", "state") is True)
        machine.screenshot("hot-corner")
        ipc("overview", "close")
        ipc("corner", "top_left", "none", "")

    with subtest("kill mode"):
        focus("one")
        one = client("one")
        pointer(one["at"][0] + 40, one["at"][1] + 200)
        machine.sleep(1)
        ipc("kill_mode")
        machine.sleep(3)
        pointer(one["at"][0] + 44, one["at"][1] + 204)
        machine.sleep(2)
        machine.screenshot("kill-mode")
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0xC0")
        machine.sleep(3)
        print("SENT", (ipc("windows", "sent") or [])[:2])
        check("kill mode force-quits the window pressed", client("one") is None, str(client("one")))

    print("SHELL ALIVE", ipc("overview", "state"))
    print("JOURNAL", machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host -n 12 --no-pager")[1][-1200:])
    failed = [label for label, ok in results if not ok]
    print(f"SUMMARY {len(results) - len(failed)} of {len(results)} passed")
    print("FAILED", failed)
