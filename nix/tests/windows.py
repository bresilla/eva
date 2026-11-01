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


def ipc(*words, tries=1):
    quoted = " ".join(shlex.quote(word) for word in words)
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


def ask(*words):
    # Reads only: this asks again after a timeout.
    return ipc(*words, tries=6)


def panels():
    return ask("drawers") or ""


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


def eventually(read, seconds=40):
    value = read()
    for _ in range(seconds // 3):
        if value:
            return value
        machine.sleep(3)
        value = read()
    return value


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


def warp(x, y):
    hyprctl("eval", f"hl.dispatch(hl.dsp.cursor.move({{ x = {x}, y = {y} }}))")
    machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool mousemove -x 1 -y 1")
    print("CURSOR", (x, y), hyprctl("cursorpos"))


def tool_open(name, pattern):
    # A tool started by the compositor, and its own socket's instance name.
    hyprctl("eval", f'hl.dispatch(hl.dsp.exec_cmd("{name}"))')
    machine.wait_until_succeeds(f"pgrep -u alice -f '{pattern}'", timeout=60)
    machine.sleep(6)
    pid = machine.succeed(f"pgrep -n -u alice -f '{pattern}'").strip()
    return f"wayland-1-app-{pid}"


def tool(instance, *words):
    quoted = " ".join(shlex.quote(word) for word in words)
    out = machine.execute(session(f"morf -i {instance} ipc call {quoted}"))[1].strip()
    print(f"TOOL {quoted} => {out[:300]}")
    try:
        reply = json.loads(out)
        value = (reply.get("result") or [None])[0] if reply.get("ok") else None
        return json.loads(value) if isinstance(value, str) and value[:1] in "[{" else value
    except ValueError:
        return None


def tool_focus():
    # The tool's window has the keys again, as pressing a row would give it.
    row = next((c for c in clients() if c["title"] == "Keys" or "keys" in c["class"].lower()), None)
    print("TOOL WINDOW", row and (row["class"], row["title"]))
    if row:
        hyprctl("eval", f'hl.dispatch(hl.dsp.focus({{ window = "address:{row["address"]}" }}))')
        machine.sleep(1)


def bound():
    return {(b.get("modmask"), b.get("key")): b for b in json.loads(hyprctl("-j", "binds")) if not b.get("submap")}


def keys_section():
    with subtest("keybind editor"):
        keys = tool_open("eva-keys", "apps/keys")
        check("eva-keys answers", eventually(lambda: (tool(keys, "state") or {}).get("rows")), keys)
        verb = "verb:window_menu toggle"

        check("a row can listen", tool(keys, "record", verb) in (True, "true"))
        check("recording holds the compositor's keys back", hyprctl("submap").strip() == "eva-keys-record", hyprctl("submap"))
        machine.send_key("meta_l-y")
        machine.sleep(2)
        check("the real chord reaches the window, and ends the recording", (tool(keys, "state") or {}).get("recording") == "", str(tool(keys, "state")))
        check("the compositor's keys are back", hyprctl("submap").strip() == "default", hyprctl("submap"))
        moved = eventually(lambda: (64, "Y") in bound())
        check("the new chord is bound", moved, str(sorted(bound()))[:400])
        check("the old chord is gone", (64, "W") not in bound())
        check("it keeps its words", bound().get((64, "Y"), {}).get("description") == "Open the window menu")

        tool(keys, "reload")
        machine.sleep(2)
        tool(keys, "record", "verb:snap picker")
        print("SUBMAP", hyprctl("submap"))
        machine.send_key("meta_l-j")
        machine.sleep(2)
        check("a second row hears its chord too", (tool(keys, "state") or {}).get("recording") == "", str(tool(keys, "state")))
        tool(keys, "reset", "verb:snap picker")
        machine.sleep(3)
        tool(keys, "reload")
        machine.sleep(2)
        tool(keys, "record", "verb:snap picker")
        machine.send_key("meta_l-j")
        machine.sleep(2)
        check("a row still hears after a reload", (tool(keys, "state") or {}).get("recording") == "", str(tool(keys, "state")))
        tool(keys, "stop")
        print("REPLY", hyprctl("activewindow")[:120], machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host -n 4 --no-pager")[1][-300:])
        tool(keys, "reset", "verb:snap picker")
        machine.sleep(3)
        tool(keys, "reload")
        machine.sleep(2)

        machine.send_key("meta_l-w")
        machine.sleep(2)
        check("the old chord does nothing", ask("window_menu", "state") in (False, None), str(ask("window_menu", "state")))
        machine.send_key("meta_l-y")
        machine.sleep(3)
        check("the new chord does what the old did", ask("window_menu", "state") is True, str(ask("window_menu", "state")))
        ipc("window_menu", "close")
        machine.sleep(2)
        tool_focus()

        hyprctl("reload")
        machine.sleep(4)
        check("a reload keeps the new chord", (64, "Y") in bound() and (64, "W") not in bound(), str(sorted(bound()))[:300])

        foreign = next(((k, b) for k, b in bound().items() if b.get("dispatcher") == "__lua" and k == (64, "Q")), None)
        check("Hyprland's own default is there to move", foreign is not None, str(sorted(bound()))[:300])
        tool(keys, "reload")
        machine.sleep(2)
        row = tool(keys, "row", "SUPER + Q") or {}
        check("its row is editable", row.get("editable") is True, str(row))
        tool_focus()
        print("ACTIVE", hyprctl("activewindow")[:160])
        tool(keys, "record", row.get("id", ""))
        print("SUBMAP", hyprctl("submap"))
        machine.send_key("meta_l-u")
        machine.sleep(2)
        print("AFTER", tool(keys, "state"), hyprctl("submap"))
        machine.screenshot("keys-recording")
        check("a key of the configuration moves too", eventually(lambda: (64, "U") in bound() and (64, "Q") not in bound()), str(sorted(bound()))[:300])
        machine.execute("rm -f /tmp/fired")
        check("the moved key still has its action", bound().get((64, "U"), {}).get("dispatcher") == "__lua")
        hyprctl("reload")
        machine.sleep(4)
        check("and stays moved after a reload", (64, "U") in bound() and (64, "Q") not in bound(), str(sorted(bound()))[:300])

        tool(keys, "reload")
        machine.sleep(2)
        tool_focus()
        tool(keys, "record", "verb:kill_mode")
        machine.send_key("meta_l-tab")
        machine.sleep(2)
        state = tool(keys, "state") or {}
        check("a taken chord waits and names its owner", "already does" in str(state.get("pending")), str(state))
        check("Super+Tab did not open the overview while listening", ask("overview", "state") is False, str(ask("overview", "state")))

        tool(keys, "reset", verb)
        tool(keys, "reset", row.get("id", ""))
        check("reset gives the default back", eventually(lambda: (64, "W") in bound() and (64, "Y") not in bound() and (64, "Q") in bound()), str(sorted(bound()))[:300])
        machine.execute("pkill -u alice -f apps/keys")


def rules_section():
    with subtest("window rules"):
        def opened(title):
            open_window(title)
            machine.sleep(2)
            return client(title)

        one = client("one") or clients()[0]
        draft = ask("rules", "from", one["address"]) or {}
        check("a rule starts from a running window", draft.get("class") == "^foot$", str(draft))

        made = ipc("rules", "add", json.dumps({
            "class": "^foot$", "title": "^ruled$", "layout": "float", "size": "400 300", "center": True,
            "opacity": 0.8, "workspace": "4", "silent": True}))
        check("a rule is kept", isinstance(made, str) and made.startswith("r"), str(made))
        machine.sleep(2)
        window = opened("ruled") or {}
        print("RULED", window)
        check("float", window.get("floating") is True, str(window))
        check("size", window.get("size") == [400, 300], str(window.get("size")))
        check("workspace, quietly", (window.get("workspace") or {}).get("id") == 4, str(window.get("workspace")))
        check("opacity", hyprctl("getprop", "title:ruled", "opacity").strip().startswith("0.8"), hyprctl("getprop", "title:ruled", "opacity"))
        center_x = window.get("at", [0])[0] + 200
        monitor = json.loads(hyprctl("-j", "monitors"))[0]
        check("centred", abs(center_x - monitor["width"] / monitor["scale"] / 2) < 40, str(window.get("at")))

        rules = ask("rules", "list") or []
        edited = dict(rules[0], size="500 350", opacity=1)
        ipc("rules", "set", json.dumps(edited))
        machine.sleep(2)
        hyprctl("eval", 'hl.dispatch(hl.dsp.window.close({ window = "title:ruled" }))')
        machine.sleep(2)
        window = opened("ruled") or {}
        print("EDITED", window)
        check("an edit reaches the next window", window.get("size") == [500, 350], str(window.get("size")))
        check("an edit leaves nothing of the old rule", hyprctl("getprop", "title:ruled", "opacity").strip().startswith("1"), hyprctl("getprop", "title:ruled", "opacity"))

        hyprctl("reload")
        machine.sleep(4)
        hyprctl("eval", 'hl.dispatch(hl.dsp.window.close({ window = "title:ruled" }))')
        machine.sleep(2)
        window = opened("ruled") or {}
        check("a reload keeps the rule", window.get("size") == [500, 350] and window.get("floating") is True, str(window))

        ipc("rules", "off", edited["id"])
        machine.sleep(2)
        hyprctl("eval", 'hl.dispatch(hl.dsp.window.close({ window = "title:ruled" }))')
        machine.sleep(2)
        window = opened("ruled") or {}
        check("a rule switched off does nothing", window.get("floating") is False, str(window))
        ipc("rules", "on", edited["id"])
        machine.sleep(2)
        hyprctl("eval", 'hl.dispatch(hl.dsp.window.close({ window = "title:ruled" }))')
        machine.sleep(2)
        window = opened("ruled") or {}
        check("and on again does", window.get("floating") is True, str(window))

        ipc("rules", "remove", edited["id"])
        machine.sleep(2)
        hyprctl("eval", 'hl.dispatch(hl.dsp.window.close({ window = "title:ruled" }))')
        machine.sleep(2)
        window = opened("ruled") or {}
        check("a deleted rule is gone", window.get("floating") is False, str(window))
        hyprctl("eval", 'hl.dispatch(hl.dsp.window.close({ window = "title:ruled" }))')

        print("CONFIG ERRORS", hyprctl("configerrors"))
        check("no spelling was refused", hyprctl("configerrors").strip() == "", hyprctl("configerrors"))

        before = hyprctl("getoption", "decoration:dim_inactive")
        check("nothing dims by default", "false" in before or "int: 0" in before, before)
        ipc("rules", "dim", "on", "0.35")
        machine.sleep(2)
        check("dim inactive reaches the compositor", "true" in hyprctl("getoption", "decoration:dim_inactive"), hyprctl("getoption", "decoration:dim_inactive"))
        check("at its strength", "0.35" in hyprctl("getoption", "decoration:dim_strength"), hyprctl("getoption", "decoration:dim_strength"))
        hyprctl("reload")
        machine.sleep(4)
        check("and stays after a reload", "true" in hyprctl("getoption", "decoration:dim_inactive"), hyprctl("getoption", "decoration:dim_inactive"))
        ipc("rules", "dim", "off")
        machine.sleep(2)
        check("and goes when turned off", "false" in hyprctl("getoption", "decoration:dim_inactive"), hyprctl("getoption", "decoration:dim_inactive"))


def layouts_section():
    with subtest("saved layouts"):
        def close(title):
            hyprctl("eval", f'hl.dispatch(hl.dsp.window.close({{ window = "title:{title}" }}))')
            machine.sleep(1)

        def move(title, fields):
            hyprctl("eval", f'hl.dispatch(hl.dsp.window.{fields})')
            machine.sleep(1)

        def box(title):
            row = client(title) or {}
            return row.get("workspace", {}).get("id"), row.get("floating"), row.get("at"), row.get("size")

        for title in ("base", "side"):
            open_window(title)
        move("base", 'move({ workspace = "5", follow = false, window = "title:base" })')
        move("side", 'float({ action = "on", window = "title:side" })')
        move("side", 'resize({ x = 420, y = 310, window = "title:side" })')
        move("side", 'move({ x = 60, y = 70, window = "title:side" })')
        machine.sleep(1)
        saved_box = box("side")
        print("SAVED BOX", saved_box, box("base"))
        ipc("layouts", "save", "work")
        machine.sleep(2)
        saved = ask("layouts", "list") or []
        check("a layout is saved by name", len(saved) == 1 and saved[0]["name"] == "work" and len(saved[0]["windows"]) >= 2, str(saved)[:300])

        move("base", 'move({ workspace = "2", follow = false, window = "title:base" })')
        move("side", 'float({ action = "off", window = "title:side" })')
        move("side", 'move({ workspace = "3", follow = false, window = "title:side" })')
        check("the windows were moved away", box("base")[0] == 2 and box("side")[0] == 3, f"{box('base')} {box('side')}")

        check("restore answers", ipc("layouts", "restore", "work") in (True, "true"))
        check("a tiled window returns to its workspace", eventually(lambda: box("base")[0] == 5), str(box("base")))
        check("a floating window returns to its exact box", eventually(lambda: box("side") == saved_box), f"{box('side')} {saved_box}")

        # A closed window with a desktop entry starts again: foot has one. Its
        # title is the terminal's own, so it comes back as a foot, not as `side`.
        close("side")
        machine.sleep(1)
        before = len([c for c in clients() if c["class"] == "foot"])
        ipc("layouts", "restore", "work")
        check("a closed window is started again", eventually(lambda: len([c for c in clients() if c["class"] == "foot"]) == before + 1, 20),
              str([c["title"] for c in clients()]))
        check("and placed", eventually(lambda: any(c["class"] == "foot" and c["floating"] and c["size"] == list(saved_box[3]) for c in clients()), 20),
              str([(c["title"], c["floating"], c["size"]) for c in clients()]))
        report = eventually(lambda: (ask("layouts", "report") or {}).get("opened"), 20)
        check("the report counts it", report == 1, str(ask("layouts", "report")))

        # A class with no desktop entry cannot be started: said plainly.
        hyprctl("eval", 'hl.dispatch(hl.dsp.exec_cmd("foot -a nodesktopentry -T lonely sleep 3600"))')
        machine.wait_until_succeeds(session("hyprctl --instance 0 clients | grep -q 'title: lonely'"), timeout=30)
        ipc("layouts", "save", "lonely")
        machine.sleep(2)
        close("lonely")
        ipc("layouts", "restore", "lonely")
        machine.sleep(3)
        check("what cannot be started is named", "nodesktopentry" in str((ask("layouts", "report") or {}).get("missing")), str(ask("layouts", "report")))

        for title in ("base",):
            close(title)
        machine.execute("pkill -u alice -f 'foot$' || true")
        ipc("layouts", "remove", "lonely")
        ipc("layouts", "remove", "work")


def spaces_section():
    with subtest("workspaces move"):
        def space(id):
            return next((w for w in workspaces() if w["id"] == id), None)

        def on(id):
            return sorted(c["title"] for c in clients() if c["workspace"]["id"] == id and c["class"] == "foot")

        def home(title, id):
            hyprctl("eval", f'hl.dispatch(hl.dsp.window.move({{ workspace = "{id}", follow = false, window = "title:{title}" }}))')
            machine.sleep(1)

        for title in ("east", "west"):
            open_window(title)
        home("east", 7)
        home("west", 8)
        first = json.loads(hyprctl("-j", "monitors"))[0]["name"]
        print("OUTPUT", hyprctl("output", "create", "headless", "EVA-2"))
        machine.sleep(8)
        monitors = [m["name"] for m in json.loads(hyprctl("-j", "monitors"))]
        check("a second screen is up", "EVA-2" in monitors, str(monitors))

        ask("workspace_name", "north", "7")
        machine.sleep(1)
        ipc("workspace_move", "7", "EVA-2")
        check("a workspace moves to another screen", eventually(lambda: (space(7) or {}).get("monitor") == "EVA-2"), str(space(7)))
        check("its window goes with it", client("east")["monitor"] == json.loads(hyprctl("-j", "monitors"))[1]["id"], str(client("east")))
        ipc("workspace_move", "7", first)
        check("and back", eventually(lambda: (space(7) or {}).get("monitor") == first), str(space(7)))

        ipc("workspace_swap", "7", "8")
        check("two workspaces trade windows", eventually(lambda: on(7) == ["west"] and on(8) == ["east"]), f"{on(7)} {on(8)}")
        check("the name goes with its windows", eventually(lambda: (space(8) or {}).get("name") == "north"), str(space(8)))

        ipc("workspace_reorder", "8", "6")
        check("a workspace takes a new place", eventually(lambda: on(6) == ["east"]), f"{on(6)} {on(7)} {on(8)}")
        check("those between shift along", eventually(lambda: on(8) == ["west"]), f"{on(6)} {on(7)} {on(8)}")
        check("nothing was lost", on(7) == [], str(on(7)))
        check("the name still follows", eventually(lambda: (space(6) or {}).get("name") == "north"), str(space(6)))

        shown = [m["activeWorkspace"]["id"] for m in json.loads(hyprctl("-j", "monitors"))]
        ipc("workspace_screens", first, "EVA-2")
        machine.sleep(2)
        after = [m["activeWorkspace"]["id"] for m in json.loads(hyprctl("-j", "monitors"))]
        check("two screens trade what they show", after == shown[::-1], f"{shown} {after}")

        for title in ("east", "west"):
            hyprctl("eval", f'hl.dispatch(hl.dsp.window.close({{ window = "title:{title}" }}))')
        hyprctl("output", "remove", "EVA-2")
        machine.sleep(4)


def ddc_section():
    # A stand-in ddcutil: a VM has no monitor to answer on an I2C bus. What this
    # proves is the shell's side, and that the system lets the seat reach a bus.
    with subtest("external brightness, a stand-in monitor"):
        machine.succeed(session("sh -c 'echo 60 > /tmp/ddc-level; : > /tmp/ddc-calls'"))
        print("I2C", machine.execute("lsmod | grep i2c_dev; udevadm verify /etc/udev/rules.d 2>&1 | tail -2; "
                                     "cat /run/current-system/sw/lib/udev/rules.d/70-eva-ddc.rules 2>&1 | head -3")[1])
        check("i2c-dev is loaded", machine.execute("lsmod | grep -q i2c_dev")[0] == 0)
        check("the rule is in place", machine.execute("grep -rq 'SUBSYSTEMS==\"drm\", TAG+=\"uaccess\"' /etc/udev/rules.d")[0] == 0)
        check("alice joins no i2c group", "i2c" not in machine.succeed("id alice"))
        check("the session is told", "1" in machine.succeed(session("printenv EVA_DDC || true")))
        ask("reload")
        machine.sleep(15)
        check("the level comes from the monitor", eventually(lambda: ask("brightness") == 60), str(ask("brightness")))
        ipc("brightness", "35")
        check("the slider's path reaches the monitor", eventually(lambda: "35" in machine.succeed("cat /tmp/ddc-level")), machine.succeed("cat /tmp/ddc-level"))
        check("the shell's level follows", ask("brightness") == 35, str(ask("brightness")))
        ipc("brightness", "up")
        check("up steps it", eventually(lambda: "40" in machine.succeed("cat /tmp/ddc-level")), machine.succeed("cat /tmp/ddc-level"))
        print("CALLS", machine.succeed("cat /tmp/ddc-calls"))
        keys = {b.get("key"): b for b in json.loads(hyprctl("-j", "binds"))}
        check("the brightness keys are the shell's", "XF86MonBrightnessUp" in keys, str(sorted(keys))[:200])


def remap_section():
    # kanata for real, on the VM's own keyboards.
    with subtest("key remapping"):
        def active():
            return machine.execute("systemctl is-active kanata-eva.service")[1].strip()

        def fired(name):
            return machine.execute(f"ls /tmp/{name}")[0] == 0

        def press(*keys):
            machine.succeed(f"YDOTOOL_SOCKET=/tmp/ydotool ydotool key {' '.join(keys)}")

        check("nothing reads the keyboards until something is chosen", active() != "active", active())
        print("UNIT", machine.succeed("systemctl cat kanata-eva.service | grep -E 'DynamicUser|CapabilityBoundingSet|SupplementaryGroups|PrivateNetwork|ExecCondition'"))
        check("alice is in no input group", "input" not in machine.succeed("id alice"))
        check("Settings can reach the option", (ask("remap", "state") or {}).get("allowed") is True, str(ask("remap", "state")))

        hyprctl("eval", 'hl.bind("escape", hl.dsp.exec_cmd("touch /tmp/esc-fired"))')
        hyprctl("eval", 'hl.bind("CTRL + Y", hl.dsp.exec_cmd("touch /tmp/ctrl-fired"))')
        hyprctl("eval", 'hl.bind("CTRL + ALT + SHIFT + SUPER + Y", hl.dsp.exec_cmd("touch /tmp/hyper-fired"))')
        machine.sleep(1)

        ipc("remap", "set", "caps", "tap_escape_hold_control")
        check("a choice starts it", eventually(lambda: active() == "active", 30), active())
        print("RENDERED", machine.succeed("cat /run/eva-remap/kanata.kbd"))
        print("JOURNAL", machine.execute("journalctl -u kanata-eva.service -n 8 --no-pager")[1][-500:])
        check("the shell hears it run", eventually(lambda: (ask("remap", "state") or {}).get("running") is True, 15), str(ask("remap", "state")))

        press("58:1", "58:0")
        machine.sleep(1)
        check("a tap on Caps Lock is Escape", fired("esc-fired"))
        machine.succeed("rm -f /tmp/esc-fired")
        press("58:1")
        machine.sleep(1)
        press("21:1", "21:0", "58:0")
        machine.sleep(1)
        check("held, Caps Lock is Control", fired("ctrl-fired"))
        check("and no Escape", not fired("esc-fired"))

        ipc("remap", "set", "caps", "hyper")
        machine.sleep(5)
        print("RENDERED", machine.succeed("cat /run/eva-remap/kanata.kbd"))
        check("a change takes", eventually(lambda: active() == "active", 30), active())
        press("58:1", "21:1", "21:0", "58:0")
        machine.sleep(1)
        check("Caps Lock as Hyper holds all four", fired("hyper-fired"))

        # What is not on the list never reaches kanata's file.
        machine.succeed("echo '{\"caps\":\"(cmd rm -rf /)\",\"tap\":\"1); (cmd x\"}' > /tmp/bad.json")
        render = machine.succeed("systemctl cat kanata-eva.service | grep -o '/nix/store/[^ ]*eva-remap-render'").split()[0]
        code, out = machine.execute(f"{render} /tmp/bad.json /tmp/bad.kbd")
        check("an unknown word renders nothing", code != 0 and machine.execute("ls /tmp/bad.kbd")[0] != 0, f"{code} {out}")

        ipc("remap", "set", "caps", "")
        check("choosing nothing stops it", eventually(lambda: active() != "active", 30), active())
        for chord in ("escape", "CTRL + Y", "CTRL + ALT + SHIFT + SUPER + Y"):
            hyprctl("eval", f'hl.unbind("{chord}")')


def sections(names):
    table = {"keys": keys_section, "rules": rules_section, "layouts": layouts_section, "spaces": spaces_section,
             "ddc": ddc_section, "remap": remap_section}
    for name in names or table:
        table[name]()


def report():
    print("SHELL ALIVE", ask("overview", "state"))
    print("JOURNAL", machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host -n 12 --no-pager")[1][-1200:])
    failed = [label for label, ok in results if not ok]
    print(f"SUMMARY {len(results) - len(failed)} of {len(results)} passed")
    print("FAILED", failed)
    assert not failed, failed


def run(password, only=""):
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
    listed = eventually(lambda: [w for w in (ask("windows") or []) if w.get("class") == "foot"])
    check("the shell lists the real windows", len(listed or []) == 3, str(listed)[:200])

    if only:
        sections(only.split())
        report()
        return

    with subtest("overview"):
        machine.send_key("meta_l-tab")
        check("Super+Tab opens the overview", eventually(lambda: ask("overview", "state") is True))

        def pictures():
            return any(v for k, v in (ask("windows", "shots") or {}).items() if k != "refused")

        check("window pictures arrive on Hyprland", eventually(pictures), str(ask("windows", "shots"))[:300])
        machine.sleep(3)
        machine.screenshot("overview")
        check("the eva process survived the captures", ask("overview", "state") is True)
        machine.send_chars("two")
        machine.sleep(2)
        machine.screenshot("overview-filtered")
        machine.send_key("esc")
        machine.sleep(2)
        check("escape closes it", ask("overview", "state") is False)

    with subtest("a window on a hidden workspace"):
        three = client("three")
        hyprctl("eval", f'hl.dispatch(hl.dsp.window.move({{ workspace = "2", follow = false, window = "address:{three["address"]}" }}))')
        machine.sleep(1)
        ipc("overview", "open")
        machine.sleep(4)
        shots = ask("windows", "shots") or {}
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
        print("AFTER TAP", ask("switcher", "state"))
        ipc("switcher", "cancel")
        machine.sleep(1)
        focus("two")
        focus("one")
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 56:1 15:1 15:0")
        machine.sleep(2)
        held = ask("switcher", "state") or {}
        print("HELD", held)
        machine.screenshot("switcher-held")
        check("held, Alt+Tab shows the switcher", held.get("shown") is True)
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 56:0")
        machine.sleep(3)
        active = json.loads(hyprctl("-j", "activewindow"))
        check("letting Alt go goes to the window chosen", active.get("title") == held.get("title"),
              f'{active.get("title")} for {held.get("title")}')
        print("AFTER RELEASE", ask("switcher", "state"))
        ipc("switcher", "cancel")
        ipc("switcher", "next", "free")
        machine.sleep(2)
        machine.screenshot("switcher")
        check("the switcher shows held", (ask("switcher", "state") or {}).get("shown") is True)
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
        warp(two["at"][0] + 60, two["at"][1] + 60)
        machine.sleep(2)
        # Thirds with four windows stacks two of them: the top one takes the grab.
        grabbed = json.loads(hyprctl("-j", "activewindow"))["title"]
        print("DRAG 0", grabbed, panels(), hyprctl("cursorpos"))
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 125:1")
        machine.sleep(2)
        print("DRAG 1", panels())
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x40")
        machine.sleep(2)
        print("DRAG 2", panels(), ask("snap", "state"), client(grabbed)["at"])
        warp(1000, 400)
        machine.sleep(2)
        print("DRAG 3", panels(), ask("snap", "state"), client(grabbed)["at"])
        warp(1272, 400)
        machine.sleep(4)
        machine.screenshot("snap-drag")
        print("DRAG 4", panels(), ask("snap", "state"), client(grabbed)["at"])
        check("a drag to an edge leaves the panels shut", panels() == "", panels())
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x80")
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool key 125:0")
        moved = eventually(lambda: near(client(grabbed)["at"][0], 644, 12), 15)
        landed = client(grabbed)
        print("DRAG 5", panels(), (ask("windows", "sent") or [])[:1])
        check("a window dragged to the right edge lands on the right half",
              moved and near(landed["size"][0], 618, 12), str(landed["at"] + landed["size"]))
        machine.sleep(4)
        check("the pointer resting there opens no panel", panels() == "", panels())
        ipc("close")
        machine.sleep(1)
        warp(640, 400)
        machine.sleep(2)
        machine.send_key("esc")
        machine.sleep(1)

    with subtest("a panel gives the keys back"):
        focus("three")
        ipc("settings", "dock")
        machine.sleep(2)
        print("PANEL", panels(), json.loads(hyprctl("-j", "activewindow")).get("title"))
        ipc("close")
        machine.sleep(2)
        print("PANEL SHUT", panels(), json.loads(hyprctl("-j", "activewindow")).get("title"))
        check("the focused window is known after a panel", ipc("keep_above") is True)
        machine.sleep(1)
        check("keep above raises it", "alter_zorder" in (ask("windows", "sent") or [""])[0], str(ask("windows", "sent")))
        ipc("keep_above")
        machine.sleep(1)

    with subtest("window state"):
        focus("three")
        check("keep above is on", ipc("keep_above") is True)
        machine.sleep(1)
        check("keep above floats it", client("three")["floating"])
        check("an opacity is accepted", ipc("opacity", "0.7") is True)
        machine.sleep(1)
        print("OPACITY", (ask("windows") or [None])[0])
        machine.screenshot("opacity")
        check("picture in picture starts", ipc("pip") is True)
        machine.sleep(2)
        three = client("three")
        check("picture in picture pins it small", three["pinned"] and three["size"][0] < 500, str(three))
        machine.screenshot("pip")
        machine.sleep(5)
        before = client("three")["at"]
        warp(before[0] + 40, before[1] + 40)
        machine.sleep(3)
        warp(before[0] + 44, before[1] + 44)
        machine.sleep(3)
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x40")
        machine.sleep(2)
        warp(before[0] - 60, before[1] - 40)
        machine.sleep(2)
        warp(before[0] - 160, before[1] - 120)
        machine.sleep(3)
        machine.succeed("YDOTOOL_SOCKET=/tmp/ydotool ydotool click 0x80")
        moved = eventually(lambda: client("three")["at"] != before, 20)
        after = client("three")["at"]
        print("PIP SENT", (ask("windows", "sent") or [])[:3])
        check("a real pointer drags the picture", moved and near(after[0], before[0] - 200, 40), f"{before} to {after}")
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
        print("SENT", (ask("windows", "sent") or [])[:4])
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
        state = ask("dock", "state") or ask("dock", "state") or {}
        print("DOCK STATE", state)
        check("the dock takes the windows", state.get("rows", 0) >= 1, str(state))
        check("a dock that stays out keeps windows clear of it", json.loads(hyprctl("-j", "monitors"))[0]["reserved"][3] > 10,
              str(json.loads(hyprctl("-j", "monitors"))[0]["reserved"]))
        print("FRAMES", machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host --no-pager | grep -E 'took [0-9]{4,}' | tail -5")[1][-500:])

    with subtest("hot corner"):
        ipc("corner", "top_left", "overview", "")
        machine.sleep(1)
        machine.sleep(4)
        pointer(640, 400)
        machine.sleep(2)
        pointer(1, 1)
        check("a corner runs its action under a real pointer", eventually(lambda: ask("overview", "state") is True))
        machine.sleep(3)
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
        print("SENT", (ask("windows", "sent") or [])[:2])
        check("kill mode force-quits the window pressed", client("one") is None, str(client("one")))

    sections(None)
    report()
