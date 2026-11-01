import re
import time

from PIL import Image

QUIET = {"idle": {"lock": 0, "blank": 0, "suspend": 0}}
# What Hyprland draws at the top of the screen for a shader that did not compile.
ERROR_BAR = (15, 15, 15)
BATTERY = "/sys/class/power_supply/test_battery"
JOB_OUT = "/run/user/1000/job.out"
JOB_IN = "/run/user/1000/job.in"


def sh(command):
    return machine.execute(session("sh -c " + shlex.quote(command)))[1].strip()


def manager(flags, command):
    # Under the user manager, as the shell runs: what polkit counts as the session.
    return sh(
        "systemd-run --user --wait --pipe --quiet --setenv=PATH=/run/current-system/sw/bin "
        f"--setenv=WAYLAND_DISPLAY=wayland-1 {flags} {command}"
    )


def job(*words, given=None):
    machine.succeed(f"rm -f {JOB_OUT}")
    flags = f"--setenv=EVA_JOB_OUT={JOB_OUT}"
    if given:
        machine.succeed(f"cat > /tmp/job.in <<'END'\n{given}\nEND")
        machine.succeed(f"install -o alice -m 600 /tmp/job.in {JOB_IN}")
        flags += f" --setenv=EVA_JOB_IN={JOB_IN}"
    quoted = " ".join(shlex.quote(word) for word in words)
    manager(flags, f"morf app /etc/eva-test-job/app.lua -- {quoted}")
    status, text = machine.execute(f"cat {JOB_OUT}")
    lines = text.split("\n", 1)
    print(f"JOB {quoted} => {text[:400]}")
    if status != 0 or lines[0] != "0":
        return None
    return json.loads(lines[1])


def settings(values):
    path = machine.succeed("cat /home/alice/.local/state/eva/settings-path").strip()
    machine.succeed(f"cat > /tmp/settings.json <<'END'\n{json.dumps({**QUIET, **values})}\nEND")
    machine.succeed(f"cp /tmp/settings.json {path}")
    machine.succeed(f"chown alice {path}")


def reloaded(read):
    # A reload is when the shell sends the Input pages' choices again.
    for _ in range(4):
        machine.sleep(3)
        hyprctl("reload")
        if eventually(read, 15):
            return True
    return False


def option(name):
    return json.loads(hyprctl("-j", "getoption", name))


def same(got, wanted):
    if isinstance(got, float) or isinstance(wanted, float):
        return got is not None and near(got, wanted, 0.001)
    return got == wanted


def no_shader():
    return option("decoration:screen_shader")["str"] in ("", "[[EMPTY]]")


def monitor(name):
    for row in json.loads(hyprctl("-j", "monitors")):
        if row["name"] == name:
            return row
    return None


def layers_on(name):
    return hyprctl("layers").partition(f"Monitor {name}:")[2].partition("Monitor ")[0]


def grim(name, output="Virtual-1"):
    machine.succeed(session(f"grim -o {output} /tmp/{name}.png"))
    machine.copy_from_vm(f"/tmp/{name}.png", "")


def reply_of(text):
    values = json.loads(text).get("result") or [None]
    value = values[0]
    return json.loads(value) if isinstance(value, str) and value[:1] in "[{" else value


def active_session():
    return machine.succeed("loginctl list-sessions --no-legend | awk '$3 == \"alice\" { print $1; exit }'").strip()


def is_locked():
    return f'test "$(loginctl show-session {active_session()} -p LockedHint --value)" = yes'


def start_shell():
    machine.succeed(session("systemctl --user start eva.service"))
    machine.wait_until_succeeds(session("morf ipc call windows | grep -q '\"ok\":true'"), timeout=180)
    machine.sleep(5)


def input_settings():
    settings({
        "input": {
            "chosen": [{"key": key, "value": value} for key, value in {
                "repeat_rate": 37, "repeat_delay": 450, "numlock": True, "sensitivity": 0.35, "accel_profile": "flat",
                "left_handed": True, "natural_scroll": True, "scroll_factor": 1.5, "tap_to_click": False,
                "touchpad_natural": True, "disable_while_typing": False, "clickfinger": True, "drag_lock": True,
                "touchpad_scroll": 0.5, "cursor_timeout": 7, "caps": "caps:escape", "compose": "compose:ralt",
            }.items()],
            "layouts": [{"layout": "us", "variant": ""}, {"layout": "de", "variant": "nodeadkeys"}],
            "switch": "grp:win_space_toggle",
            "devices": [
                {"key": "qemu-qemu-usb-tablet", "value": {"scroll_factor": 2, "sensitivity": 0.2}},
                {"key": "virtualps/2-vmware-vmmouse", "value": {"scroll_factor": 3}},
            ],
        },
        "accessibility": {"zoom": 1.5, "sticky_keys": True, "mouse_keys": True},
    })
    check("the Input pages' plan reaches Hyprland", reloaded(lambda: option("input:repeat_rate")["int"] == 37),
          str(option("input:repeat_rate")))
    for name, kind, value in (
        ("input:repeat_delay", "int", 450), ("input:numlock_by_default", "bool", True),
        ("input:sensitivity", "float", 0.35), ("input:accel_profile", "str", "flat"),
        ("input:left_handed", "bool", True), ("input:natural_scroll", "bool", True),
        ("input:scroll_factor", "float", 1.5), ("input:touchpad:tap-to-click", "bool", False),
        ("input:touchpad:natural_scroll", "bool", True), ("input:touchpad:disable_while_typing", "bool", False),
        ("input:touchpad:clickfinger_behavior", "bool", True), ("input:touchpad:drag_lock", "int", 1),
        ("input:touchpad:scroll_factor", "float", 0.5), ("cursor:inactive_timeout", "float", 7),
        ("cursor:zoom_factor", "float", 1.5), ("input:kb_layout", "str", "us,de"),
        ("input:kb_variant", "str", ",nodeadkeys"),
        ("input:kb_options", "str", "grp:win_space_toggle,caps:escape,compose:ralt"),
    ):
        reply = option(name)
        check(f"{name} reads back", same(reply.get(kind), value), str(reply))
    check("nothing was refused", hyprctl("configerrors").strip() == "", hyprctl("configerrors"))
    mice = {row["name"]: row for row in json.loads(hyprctl("-j", "devices"))["mice"]}
    check("a device takes its own option", near(mice["qemu-qemu-usb-tablet"]["scrollFactor"], 2, 0.01), str(mice))
    check("so does a device with a slash in its name", near(mice["virtualps/2-vmware-vmmouse"]["scrollFactor"], 3, 0.01), str(mice))
    read = job("readings") or {}
    check("the pages read a toggle that is off", read.get("tap_to_click") is False, str(read))
    check("the pages read a toggle that is on", read.get("numlock") is True, str(read))
    check("the pages read a word", read.get("accel_profile") == "flat", str(read))

    with subtest("layouts, the cursor, sticky keys and mouse keys"):
        def keymap():
            return json.loads(hyprctl("-j", "devices"))["keyboards"][-1]["active_keymap"]

        hyprctl("switchxkblayout", "all", "next")
        check("the next layout", "German" in keymap(), keymap())
        hyprctl("switchxkblayout", "all", "next")
        check("the cursor plan is taken", hyprctl("setcursor", "Adwaita", "32") == "ok")
        path = option("input:kb_file")["str"]
        check("sticky keys load a keymap", path.endswith("/eva/keymaps/sticky.xkb"), path)
        check("its modifiers latch", int(machine.succeed(f"grep -c LatchMods {path}").strip()) > 0)
        keys = [bind.get("key") for bind in json.loads(hyprctl("-j", "binds"))]
        check("mouse keys are bound", {"KP_Left", "KP_Next", "KP_Begin"} <= set(keys), str(keys)[:300])
        before = hyprctl("cursorpos")
        sh("wlrctl pointer move 7 7")
        check("what they run moves the pointer", eventually(lambda: hyprctl("cursorpos") != before, 12), before)

    settings({})
    check("a reload with nothing chosen clears them", reloaded(lambda: option("input:repeat_rate")["int"] == 25))
    read = job("readings") or {}
    check("the pages read Hyprland's own default", read.get("tap_to_click") is True and read.get("accel_profile") == "", str(read))
    hyprctl("eval", 'hl.config({ input = { kb_file = "" } })')


def blocks(name):
    machine.screenshot(name)
    with Image.open(machine.out_dir / f"{name}.png") as picture:
        rgb = picture.convert("RGB")
        return [rgb.getpixel((48 + 30 * index, 42)) for index in range(6)]


def shown(values, fragment):
    settings(values)
    eventually(lambda: fragment in option("decoration:screen_shader")["str"], 20)
    machine.sleep(3)
    return option("decoration:screen_shader")["str"]


def shaders():
    hyprctl("eval", 'hl.dispatch(hl.dsp.exec_cmd("foot -T colours /etc/eva-test-colours"))')
    machine.wait_until_succeeds(session("hyprctl --instance 0 clients | grep -q 'title: colours'"), timeout=30)
    machine.sleep(3)
    plain = blocks("filter-none")
    print("PLAIN", plain)

    def compiled(name, picture):
        check(f"{name} compiled", ERROR_BAR not in picture and picture != plain, str(picture))

    # Accessibility's choices and the quick filters, each through the shell's own settings.
    for name, values, fragment in (
        ("grayscale", {"accessibility": {"filter": "grayscale"}}, "screen-grayscale"),
        ("invert", {"accessibility": {"filter": "invert"}}, "screen-invert"),
        ("protanopia", {"accessibility": {"filter": "protanopia"}}, "correction-protanopia"),
        ("deuteranopia", {"accessibility": {"filter": "deuteranopia"}}, "correction-deuteranopia"),
        ("tritanopia", {"accessibility": {"filter": "tritanopia"}}, "correction-tritanopia"),
        ("reading", {"filters": {"reading": True}}, "screen-reading"),
        ("extradim", {"filters": {"extradim": True, "dim": 0.5}}, "screen-extradim-50"),
        ("everything", {"filters": {"correction": True, "correction_kind": "tritanopia", "reading": True,
                                    "extradim": True, "dim": 0.6}}, "reading-extradim"),
    ):
        path = shown(values, fragment)
        check(f"{name} is the screen's shader", fragment in path, path)
        picture = blocks(f"filter-{name}")
        print("FILTER", name, picture)
        compiled(name, picture)
        if name == "grayscale":
            check("grayscale takes the colour out", all(r == g == b for r, g, b in picture), str(picture))
        if name == "invert":
            check("invert turns it over", all(near(a, 255 - b, 3) for one, two in zip(picture, plain) for a, b in zip(one, two)), str(picture))
        if name in ("protanopia", "deuteranopia"):
            check(f"{name} corrects: red stays apart from green", picture[0][0] - picture[0][1] > 60, str(picture))
        if name == "extradim":
            check("extra dim halves the light", all(near(a, b / 2, 3) for one, two in zip(picture, plain) for a, b in zip(one, two)), str(picture))

    with subtest("the page's filter and a quick one share the screen"):
        both = {"accessibility": {"filter": "grayscale"}, "filters": {"extradim": True, "dim": 0.5}}
        path = shown(both, "grayscale-extradim-50")
        check("one shader holds both", "grayscale-extradim-50" in path, path)
        hyprctl("reload")
        check("and it stands after a reload",
              eventually(lambda: "grayscale-extradim-50" in option("decoration:screen_shader")["str"], 20),
              option("decoration:screen_shader")["str"])
        machine.sleep(3)
        picture = blocks("filter-both")
        check("both show", all(r == g == b for r, g, b in picture) and picture[3][0] < plain[3][0] / 1.5, str(picture))

    settings({})
    check("off clears it", eventually(no_shader, 20))
    machine.sleep(3)
    check("and the colours come back", blocks("filter-cleared") == plain)

    with subtest("a shader that does not compile would have shown"):
        machine.succeed("printf '#version 300 es\\nthis is not glsl\\n' > /tmp/broken.frag; chmod 644 /tmp/broken.frag")
        hyprctl("eval", 'hl.config({ decoration = { screen_shader = "/tmp/broken.frag" } })')
        machine.sleep(3)
        picture = blocks("filter-broken")
        check("Hyprland's bar covers the blocks", set(picture) == {ERROR_BAR}, str(picture))
        hyprctl("eval", 'hl.config({ decoration = { screen_shader = "" } })')
        hyprctl("seterror", "disable")
        machine.sleep(3)
    check("the bar is gone", blocks("filter-after-broken") == plain)
    close = client("colours")
    hyprctl("eval", f'hl.dispatch(hl.dsp.window.close({{ window = "address:{close["address"]}" }}))')
    machine.sleep(2)


def displays(*words):
    pid = machine.succeed("cat /run/user/1000/eva/displays.window").strip()
    quoted = " ".join(shlex.quote(word) for word in words)
    return reply_of(machine.execute(session(f"timeout 30 morf -i wayland-1-app-{pid} ipc call {quoted}"))[1].strip())


def tool_up():
    status, text = machine.execute(session(
        "morf -i wayland-1-app-$(cat /run/user/1000/eva/displays.window) ipc call state"))
    return status == 0 and '"ok":true' in text


def rotation():
    sh("systemd-run --user --unit=displays --setenv=PATH=/run/current-system/sw/bin --setenv=WAYLAND_DISPLAY=wayland-1 eva-displays")
    machine.wait_until_succeeds("test -s /run/user/1000/eva/displays.window", timeout=60)
    check("eva-displays answers", eventually(tool_up, 120))
    machine.sleep(3)
    state = displays("state") or {}
    check("eva-displays reads the outputs as it opens", any(o.get("name") == "Virtual-1" for o in state.get("outputs", [])), str(state)[:300])
    wide = monitor("Virtual-1")
    displays("set", "Virtual-1", "transform", "1")
    check("it applies", displays("apply") is True, str(displays("state"))[:300])
    check("the output turns", eventually(lambda: monitor("Virtual-1")["transform"] == 1, 30), str(monitor("Virtual-1")))
    # Before the tool's countdown takes it back.
    displays("keep")
    machine.sleep(2)
    kept = machine.succeed("cat /home/alice/.local/state/eva/displays/monitors.lua")
    check("what is kept is the rotation", "transform = 1" in kept and "desc:" in kept, kept)
    check("the shell has the new shape", eventually(lambda: (ask("screen") or {}).get("height") == 1280, 60), str(ask("screen")))
    check("the frame covers it", eventually(lambda: re.search(r"0 0 800 1280, namespace: eva-drawers", layers_on("Virtual-1")), 60),
          layers_on("Virtual-1"))
    check("upright, the status bar stands", eventually(lambda: monitor("Virtual-1")["reserved"][1] > 30, 60), str(monitor("Virtual-1")["reserved"]))
    grim("rotated")
    ipc("sidebar", "open")
    check("the panel comes down as a sheet", eventually(lambda: "sidebar" in panels(), 30), panels())
    machine.sleep(4)
    grim("rotated-sheet")
    ipc("close")
    machine.sleep(2)

    with subtest("auto-rotate's calls"):
        for orientation, transform in (("bottom-up", 2), ("right-up", 3), ("normal", 0)):
            check(f"{orientation} is taken", (job("rotate", orientation, "Virtual-1") or {}).get("ok") is True)
            row = monitor("Virtual-1")
            check(f"{orientation} turns it", eventually(lambda: monitor("Virtual-1")["transform"] == transform, 30), str(row))
            row = monitor("Virtual-1")
            check(f"{orientation} keeps the mode and place",
                  (row["width"], row["height"], row["x"], row["y"]) == (wide["width"], wide["height"], wide["x"], wide["y"]), str(row))
            check("the touchscreen turns with it", option("input:touchdevice:transform")["int"] == transform)
            check("and the tablet", option("input:tablet:transform")["int"] == transform)
        check("back at the desk", eventually(lambda: (ask("screen") or {}).get("height") == 800, 60), str(ask("screen")))
        check("nothing was refused", hyprctl("configerrors").strip() == "", hyprctl("configerrors"))
    grim("rotated-back")
    displays("refresh")
    machine.sleep(2)
    displays("keep")
    machine.sleep(2)
    check("what is kept is upright", "transform = 0" in machine.succeed("cat /home/alice/.local/state/eva/displays/monitors.lua"))
    sh("systemctl --user stop displays")


def two_outputs():
    hyprctl("output", "create", "headless", "SECOND")
    check("a second output joins", eventually(lambda: monitor("SECOND"), 240), hyprctl("monitors"))
    check("the shell comes up on it", eventually(lambda: "eva-drawers" in layers_on("SECOND"), 240), layers_on("SECOND"))
    machine.sleep(10)
    ipc("bar", "show", "on")
    check("a bar on each", eventually(lambda: monitor("Virtual-1")["reserved"][1] > 30 and monitor("SECOND")["reserved"][1] > 30, 60),
          str([monitor("Virtual-1")["reserved"], monitor("SECOND")["reserved"]]))

    with subtest("panels and workspaces are each output's own"):
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ monitor = "SECOND" }))')
        machine.sleep(3)
        ipc("workspace", "4")
        check("a workspace on the second", eventually(lambda: monitor("SECOND")["activeWorkspace"]["id"] == 4, 30), str(monitor("SECOND")))
        check("the first stays where it was", monitor("Virtual-1")["activeWorkspace"]["id"] == 1, str(monitor("Virtual-1")))
        ipc("sidebar", "open")
        check("a panel opens on the output with the focus", eventually(lambda: panels() == "sidebar", 30), panels())
        machine.sleep(5)
        grim("two-second-panel", "SECOND")
        grim("two-first", "Virtual-1")
        ipc("close")
        machine.sleep(3)
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ monitor = "Virtual-1" }))')
        machine.sleep(3)
        ipc("sidebar", "open")
        check("the verb reports a panel on either output", eventually(lambda: panels() == "sidebar", 30), panels())
        ipc("close")
        machine.sleep(3)

    with subtest("a notification on the focused output"):
        hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ monitor = "SECOND" }))')
        machine.sleep(2)
        sh("notify-send -a vmtest 'On the second' 'a body'")
        check("the shell has it", eventually(lambda: any(row.get("summary") == "On the second" for row in ask("notifications", "list") or []), 30))
        check("a verb only the primary output answers is heard with the focus elsewhere",
              (ask("notifications", "status") or {}).get("count", 0) >= 1, str(ask("notifications", "status")))
        machine.sleep(3)
        grim("two-notified", "SECOND")

    with subtest("an output unplugged and back"):
        open_window("onsecond")
        machine.sleep(2)
        check("the window is on the second", client("onsecond")["monitor"] == monitor("SECOND")["id"], str(client("onsecond")))
        hyprctl("output", "remove", "SECOND")
        check("it leaves", eventually(lambda: monitor("SECOND") is None, 60))
        machine.sleep(8)
        check("the shell stays up", machine.execute(session("systemctl --user is-active eva.service"))[0] == 0)
        check("and answers", (ask("screen") or {}).get("width") == 1280, str(ask("screen")))
        check("the window comes to the first", client("onsecond")["monitor"] == monitor("Virtual-1")["id"], str(client("onsecond")))
        grim("two-unplugged")
        hyprctl("output", "create", "headless", "SECOND")
        check("it returns", eventually(lambda: monitor("SECOND"), 120))
        check("the shell comes back on it", eventually(lambda: "eva-drawers" in layers_on("SECOND"), 120), layers_on("SECOND"))
        check("the workspace goes home", eventually(lambda: monitor("SECOND")["activeWorkspace"]["id"] == 4, 60), str(monitor("SECOND")))
        machine.sleep(10)
        check("the bar stands on it again", eventually(lambda: monitor("SECOND")["reserved"][1] > 30, 60), str(monitor("SECOND")["reserved"]))
        grim("two-returned", "SECOND")
    row = client("onsecond")
    hyprctl("eval", f'hl.dispatch(hl.dsp.window.close({{ window = "address:{row["address"]}" }}))')
    hyprctl("output", "remove", "SECOND")
    eventually(lambda: monitor("SECOND") is None, 60)
    hyprctl("eval", 'hl.dispatch(hl.dsp.focus({ workspace = "1" }))')
    ipc("bar", "show", "auto")
    machine.sleep(5)
    print("CLIENT DROPPED", machine.execute("journalctl -b --no-pager | grep -a -E 'Data too big|error in client communication' | cut -c1-120")[1])


def clock():
    machine.succeed("rm -f /tmp/sound-requests")
    check("a timer is set", "Timer" in sh("eva-clock timer 20 s eggs"))
    units = sh("systemctl --user list-timers --all --no-pager")
    check("its unit exists when the command returns", "eva-alarm-" in units, units)
    machine.wait_until_succeeds("test -s /tmp/sound-requests", timeout=60)
    played = machine.succeed("head -1 /tmp/sound-requests").strip()
    check("the sound is the alarm's", played.endswith("/alarm-clock-elapsed.oga"), played)
    check("and it is there to play", machine.execute(f"test -r {shlex.quote(played)}")[0] == 0, played)
    machine.sleep(4)
    rows = [row for row in ask("notifications", "list") or [] if row.get("summary") == "eggs"]
    check("the real server shows it, critical", rows and rows[-1].get("urgency") == 2, str(rows))
    check("with Stop and Snooze", rows and [action["key"] for action in rows[-1]["actions"]] == ["stop", "snooze"], str(rows))
    machine.screenshot("clock-ring")
    ipc("notifications", "invoke", str(int(rows[-1]["id"])), "stop")
    machine.wait_until_fails("pgrep -u alice -x notify-send", timeout=30)
    check("Stop ends it", "nothing set" in sh("eva-clock list"), sh("eva-clock list"))
    machine.sleep(3)
    heard = machine.succeed("wc -l < /tmp/sound-requests")
    machine.sleep(5)
    check("and the sound stops", heard == machine.succeed("wc -l < /tmp/sound-requests"))

    with subtest("Snooze rings it again"):
        machine.succeed("rm -f /tmp/sound-requests")
        sh("eva-clock timer 5 s nap")
        machine.wait_until_succeeds("test -s /tmp/sound-requests", timeout=60)
        machine.sleep(3)
        rows = [row for row in ask("notifications", "list") or [] if row.get("summary") == "nap"]
        ipc("notifications", "invoke", str(int(rows[-1]["id"])), "snooze")
        check("a new timer, nine minutes off", eventually(lambda: "Timer 9 min" in sh("eva-clock list"), 30), sh("eva-clock list"))
        check("as a unit", eventually(lambda: "eva-alarm-" in sh("systemctl --user list-timers --all --no-pager"), 15))
        sh("eva-clock cancel all")
        check("cancelling takes it away", eventually(lambda: "eva-alarm-" not in sh("systemctl --user list-timers --all --no-pager"), 15))


def idle(password):
    written = machine.succeed("cat /etc/xdg/hypr/hypridle.conf")
    backstop = re.search(r"listener \{\s*timeout = 900\s*on-timeout = (\S*eva-idle-backstop)", written)
    check("with no lock timeout fixed, the backstop is a listener", backstop, written)
    machine.succeed("sed -e 's/timeout = 900/timeout = 15/' /etc/xdg/hypr/hypridle.conf > /tmp/short-idle.conf; chmod 644 /tmp/short-idle.conf")

    def short_idle():
        sh("systemctl --user stop hypridle; systemctl --user stop shortidle; systemctl --user reset-failed shortidle")
        sh("systemd-run --user --unit=shortidle /run/current-system/sw/bin/hypridle --config /tmp/short-idle.conf")

    def fired(count):
        return lambda: sh("journalctl --user -u shortidle --no-pager | grep -c 'Running .*eva-idle-backstop'") == str(count)

    short_idle()
    check("a shortened backstop fires", eventually(fired(1), 60), sh("journalctl --user -u shortidle --no-pager -n 12"))
    machine.sleep(6)
    check("a living shell is left alone", machine.execute(is_locked())[0] != 0)
    check("and goes on", ask("screen") is not None)

    sh("systemctl --user stop eva.service")
    machine.wait_until_fails(session("morf ipc verbs"), timeout=30)
    short_idle()
    check("with the shell dead it fires again", eventually(fired(2), 60), sh("journalctl --user -u shortidle --no-pager -n 12"))
    machine.wait_until_succeeds(is_locked(), timeout=90)
    machine.wait_until_succeeds("pgrep -u alice -f 'morf.*lock'", timeout=60)
    machine.wait_until_succeeds(session("journalctl --user -u shortidle --no-pager | grep -q 'session got locked'"), timeout=60)
    machine.sleep(6)
    machine.screenshot("idle-backstop-locked")
    machine.send_key("ret")
    machine.sleep(2)
    machine.send_chars(f"{password}\n")
    machine.wait_until_fails(is_locked(), timeout=60)
    machine.wait_until_fails("pgrep -u alice -f 'morf.*lock'", timeout=60)
    sh("systemctl --user stop shortidle; systemctl --user start hypridle")
    start_shell()


def printers():
    def lpstat(flag):
        return machine.succeed(f"LC_ALL=C lpstat {flag} 2>&1 || true")

    fresh = job("printers") or {}
    print("LPSTAT", lpstat("-p"), lpstat("-v"), lpstat("-d"))
    rows = fresh.get("printers") or []
    check("real CUPS reads as a queue", rows and rows[0]["name"] == "pdf" and rows[0]["state"] == "idle" and rows[0]["enabled"], str(fresh))
    check("with its device", rows and rows[0]["uri"] == "cups-pdf:/pdf", str(fresh))
    check("and CUPS is available", fresh.get("available") is True, str(fresh))

    machine.succeed("cupsdisable -r 'Out of paper' pdf; lpadmin -d pdf; printf 'hello\\n' > /tmp/hello.txt; chmod 644 /tmp/hello.txt")
    sh("lp -d pdf /tmp/hello.txt; lp -d pdf /tmp/hello.txt")
    print("LPSTAT", lpstat("-p"), lpstat("-o"), lpstat("-d"))
    paused = job("printers") or {}
    rows = paused.get("printers") or []
    check("paused, with the reason", rows and rows[0]["state"] == "stopped" and not rows[0]["enabled"] and rows[0]["reason"] == "Out of paper", str(paused))
    check("the default", paused.get("default") == "pdf" and rows and rows[0]["default"], str(paused))
    jobs = paused.get("jobs") or []
    check("the jobs waiting", [row["id"] for row in jobs] == ["pdf-1", "pdf-2"] and jobs[0]["user"] == "alice" and jobs[0]["printer"] == "pdf", str(paused))
    ipc("settings", "printers")
    machine.sleep(8)
    grim("printers-paused")
    ipc("close")
    machine.sleep(2)

    denied = sh("lpadmin -d pdf; echo rc=$?")
    check("outside CUPS's groups the buttons are refused", "Forbidden" in denied, denied)
    sh("cancel pdf-2")
    machine.succeed("cupsenable pdf; seq 1 40000 > /tmp/big.txt; chmod 644 /tmp/big.txt")
    machine.wait_until_succeeds("test -z \"$(lpstat -o)\"", timeout=60)
    sh("lp -d pdf /tmp/big.txt")
    busy = machine.succeed("for i in $(seq 1 600); do LC_ALL=C lpstat -p; done | grep -m1 -A1 'now printing' || true")
    print("LPSTAT printing", busy)
    check("a printer at work reads as the parser expects", re.search(r"^printer pdf now printing pdf-\d+\.", busy), busy)

    with subtest("in the person's language"):
        german = machine.succeed("LC_ALL=de_DE.UTF-8 lpstat -p")
        check("CUPS speaks German here", "Drucker pdf" in german, german)
        sh("systemctl --user set-environment LC_ALL=de_DE.UTF-8")
        check("eva reads it all the same", ((job("printers") or {}).get("printers") or [{}])[0].get("name") == "pdf")
        sh("systemctl --user unset-environment LC_ALL")

    with subtest("the scheduler stopped"):
        machine.succeed("systemctl stop cups.socket cups.service")
        down = job("printers") or {}
        check("no printing here", down.get("available") is False, str(down))
        machine.succeed("systemctl start cups.socket")


def battery_state(**values):
    for name, value in values.items():
        machine.succeed(f"echo {value} > /sys/module/test_power/parameters/{name}")
    machine.sleep(6)


def battery():
    ipc("bar", "add", "battery", "end")
    ipc("bar", "show", "on")
    machine.sleep(4)
    for name, values, level, words in (
        ("full", {"ac_online": "on", "usb_online": "off", "battery_status": "full", "battery_capacity": 100}, 100,
         {"full": True, "plugged": True}),
        ("charging", {"ac_online": "on", "battery_status": "charging", "battery_capacity": 64,
                      "battery_current": 1600000, "battery_voltage": 12000000}, 64, {"charging": True}),
        ("on-battery", {"ac_online": "off", "battery_status": "discharging", "battery_capacity": 64,
                        "battery_current": -1600000}, 64, {"plugged": False, "low": False}),
        ("low", {"battery_capacity": 15}, 15, {"low": True, "critical": False}),
        ("critical", {"battery_capacity": 5}, 5, {"critical": True, "mark": "alert"}),
    ):
        battery_state(**values)
        read = job("battery") or {}
        check(f"{name}: the level", read.get("level") == level, str(read))
        for key, value in words.items():
            check(f"{name}: {key}", read.get(key) == value, str(read))
        check(f"{name}: eva-battery says the charge", f"charge {level}%" in manager("", "eva-battery status"))
        grim(f"battery-{name}")

    with subtest("the charge limit, through UPower"):
        battery_state(ac_online="on", battery_status="charging", battery_capacity=64)
        status = manager("", "eva-battery status")
        print("EVA-BATTERY", status)
        check("the limit is on offer", "limit false" in status, status)
        check("a battery with no numbers says none", "between" not in status, status)
        before = machine.succeed(f"cat {BATTERY}/charge_types").strip()
        check("charging normally", before.startswith("[Standard]"), before)
        check("eva-battery turns it on", manager("", "eva-battery limit on") == "limit on")
        check("the kernel's charge type moves", machine.succeed(f"cat {BATTERY}/charge_types").strip().endswith("[Long_Life]"))
        check("eva-battery reads it back", "limit true" in manager("", "eva-battery status"))
        check("eva-battery turns it off", manager("", "eva-battery limit off") == "limit off")
        check("the kernel's charge type returns", machine.succeed(f"cat {BATTERY}/charge_types").strip().startswith("[Standard]"))
        ipc("settings", "power")
        machine.sleep(8)
        grim("battery-power-page")
        ipc("close")
    ipc("bar", "remove", "battery")
    ipc("bar", "show", "auto")
    battery_state(ac_online="on", battery_status="discharging", battery_capacity=50, battery_current=-1600, battery_voltage=3300)


def hotspot():
    saved = job("hotspot_save", "evaspot", given="a good password")
    check("eva saves the profile", saved and saved.get("path"), str(saved))
    profile = machine.succeed("nmcli -t -f 802-11-wireless.mode,802-11-wireless.ssid,ipv4.method,802-11-wireless-security.key-mgmt connection show eva-hotspot")
    check("NetworkManager has it as eva asked", all(word in profile for word in ("mode:ap", "ssid:evaspot", "method:shared", "key-mgmt:wpa-psk")), profile)
    check("and the password is not on show", "a good password" not in machine.succeed("nmcli connection show eva-hotspot"))
    started = job("hotspot_start")
    check("eva starts it", started and started.get("path"), str(started))
    machine.wait_until_succeeds("nmcli -t -f NAME,STATE connection show --active | grep -q 'eva-hotspot:activated'", timeout=60)
    access = machine.succeed("nmcli -t -f NAME,DEVICE connection show --active | grep eva-hotspot | cut -d: -f2").strip()
    check("the radio is an access point", "type AP" in machine.succeed(f"iw dev {access} info"), access)
    other = "wlan1" if access == "wlan0" else "wlan0"
    keyfile = "\n".join((
        "[connection]", "id=client", "type=wifi", f"interface-name={other}", "autoconnect=false", "[wifi]", "ssid=evaspot",
        "mode=infrastructure", "[wifi-security]", "key-mgmt=wpa-psk", "psk=a good password", "[ipv4]", "method=auto",
        "[ipv6]", "method=ignore",
    ))
    machine.succeed(f"cat > /etc/NetworkManager/system-connections/client.nmconnection <<'END'\n{keyfile}\nEND")
    machine.succeed("chmod 600 /etc/NetworkManager/system-connections/client.nmconnection; nmcli connection reload")
    joined = machine.execute("timeout 70 nmcli connection up client 2>&1")[1]
    print("CLIENT", joined)
    check("a client joins it with the password", "authorized:\tyes" in machine.succeed(f"iw dev {access} station dump"), joined)
    check("and is given an address through the firewall", re.search(r"inet 10\.42\.0\.\d+", machine.succeed(f"ip -4 addr show {other}")), joined)
    ipc("settings", "hotspot")
    machine.sleep(8)
    grim("hotspot-on")
    ipc("close")
    stopped = job("hotspot_stop")
    check("eva stops it", stopped and stopped.get("ok"), str(stopped))
    check("the radio goes back", eventually(lambda: "type managed" in machine.succeed(f"iw dev {access} info"), 30))


def system(password):
    login(password)
    machine.wait_until_succeeds(session("morf ipc call windows | grep -q '\"ok\":true'"), timeout=240)
    print("HYPRLAND", hyprctl("version")[:60])
    settings({})
    machine.sleep(5)
    began = time.monotonic()
    for name, section in (
        ("input settings", input_settings),
        ("accessibility shaders", shaders),
        ("rotation", rotation),
        ("two outputs", two_outputs),
        ("a real ring", clock),
        ("the idle backstop", lambda: idle(password)),
        ("printers", printers),
        ("battery", battery),
        ("hotspot", hotspot),
    ):
        with subtest(name):
            section()
        print(f"SECTION {name} done at {time.monotonic() - began:.0f}s; load {open('/proc/loadavg').read().strip()}")
    print("JOURNAL", machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host -n 12 --no-pager")[1][-1200:])
    failed = [label for label, ok in results if not ok]
    print(f"SUMMARY {len(results) - len(failed)} of {len(results)} passed")
    print("FAILED", failed)
    assert not failed, failed
