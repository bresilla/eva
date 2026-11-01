import json
import shlex


def hyprctl(*words):
    quoted = " ".join(shlex.quote(word) for word in words)
    status, out = machine.execute(
        "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/$(id -u alice) "
        f"HOME=/home/alice hyprctl --instance 0 {quoted} 2>&1"
    )
    return out.strip()


def probe(chunk):
    print(f"PROBE {chunk}\nREPLY {hyprctl('eval', chunk)}")


def clients():
    return json.loads(hyprctl("-j", "clients"))


def show(title):
    rows = [
        (c["address"], c["title"], c["workspace"]["name"], c["at"], c["size"], c["floating"], c["pinned"], c["fullscreen"])
        for c in clients()
    ]
    print(f"STATE {title}: {rows}")


def run(password):
    machine.start()
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("pgrep -u greeter -f 'morf.*greet'", timeout=180)
    machine.sleep(15)
    machine.send_key("ret")
    machine.sleep(3)
    machine.send_chars(password)
    machine.sleep(1)
    machine.send_chars("\n")
    machine.wait_until_succeeds("pgrep -u alice Hyprland", timeout=180)
    machine.sleep(20)
    machine.screenshot("session")

    print("VERSION", hyprctl("version"))
    print("LAYOUTS", hyprctl("layouts"))
    print("EVA", machine.execute("systemctl --user --machine=alice@.host is-active eva.service")[1])
    for title in ("one", "two", "three"):
        probe(f'hl.dispatch(hl.dsp.exec_cmd("foot -T {title} sleep 3600"))')
        machine.sleep(3)
    machine.sleep(3)
    machine.screenshot("three-windows")
    show("opened")
    print("CLIENT", json.dumps(clients()[0]))
    print("WORKSPACES", hyprctl("-j", "workspaces"))
    print("MONITORS", hyprctl("-j", "monitors"))
    a = clients()[0]["address"]
    w = f'"address:{a}"'
    for chunk in (
        f"hl.dispatch(hl.dsp.window.float({{ action = \"on\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.resize({{ x = 640, y = 400, window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.resize({{ x = 700, y = 420, relative = false, window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.move({{ x = 100, y = 120, window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.move({{ x = 110, y = 130, relative = false, window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.center({{ window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.pin({{ action = \"toggle\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.pin({{ action = \"toggle\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.set_prop({{ prop = \"opacity\", value = \"0.7\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.set_prop({{ prop = \"alpha\", value = \"0.7\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.alter_zorder({{ mode = \"top\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.alter_zorder({{ action = \"top\", window = {w} }}))",
        "hl.dispatch(hl.dsp.window.alter_zorder(\"top\"))",
        f"hl.dispatch(hl.dsp.window.bring_to_top({{ window = {w} }}))",
        "hl.dispatch(hl.dsp.window.cycle_next())",
        "hl.dispatch(hl.dsp.window.cycle_next({ next = true, tiled = false }))",
        "hl.dispatch(hl.dsp.window.swap({ direction = \"left\" }))",
        "hl.dispatch(hl.dsp.layout(\"splitratio 0.2\"))",
        "hl.dispatch(hl.dsp.layout(\"splitratio exact 0.6\"))",
        "hl.dispatch(hl.dsp.layout(\"togglesplit\"))",
        "hl.dispatch(hl.dsp.layout(\"orientationleft\"))",
        "hl.dispatch(hl.dsp.workspace.rename({ id = 1, name = \"code\" }))",
        "hl.dispatch(hl.dsp.workspace.rename({ workspace = \"1\", name = \"code\" }))",
        "hl.dispatch(hl.dsp.workspace.rename(\"1\", \"code\"))",
        "hl.workspace_rule({ workspace = \"2\", layout = \"master\" })",
        "hl.workspace_rule({ workspace = \"name:code\", layout = \"master\" })",
        "hl.workspace_rule({ workspace = \"1\", layout = \"scrolling\" })",
        "hl.workspace_rule({ workspace = \"1\", layout = \"monocle\" })",
        "hl.workspace_rule({ workspace = \"1\", layout = \"dwindle\" })",
        "return hl.get_workspace(1).tiled_layout",
        "return hl.get_active_workspace().tiled_layout",
        "print(hl.get_active_workspace().tiled_layout)",
        "hl.dispatch(hl.dsp.workspace.toggle_special(\"eva\"))",
        "hl.dispatch(hl.dsp.workspace.toggle_special(\"eva\"))",
        f"hl.dispatch(hl.dsp.window.move({{ workspace = \"special:eva\", follow = false, window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.move({{ workspace = \"1\", follow = false, window = {w} }}))",
        f"hl.dispatch(hl.dsp.focus({{ window = {w} }}))",
        "hl.dispatch(hl.dsp.group.toggle({}))",
        "hl.dispatch(hl.dsp.group.toggle({}))",
        f"hl.dispatch(hl.dsp.window.fullscreen({{ mode = \"maximized\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.fullscreen({{ mode = \"maximized\", action = \"unset\", window = {w} }}))",
        f"hl.dispatch(hl.dsp.window.float({{ action = \"off\", window = {w} }}))",
        "hl.dispatch(hl.dsp.focus({ workspace = \"empty\" }))",
        "hl.dispatch(hl.dsp.focus({ workspace = \"previous\" }))",
        "hl.dispatch(hl.dsp.cursor.move({ x = 200, y = 200 }))",
        "return hl.get_cursor_pos().x",
        "hl.config({ general = { layout = \"master\" } })",
        "hl.config({ general = { layout = \"dwindle\" } })",
        "hl.bind(\"SUPER + mouse:272\", hl.dsp.exec_cmd(\"true\"), { non_consuming = true })",
        "hl.bind(\"SUPER + mouse:272\", hl.dsp.exec_cmd(\"true\"), { non_consuming = true, release = true })",
        "hl.bind(\"ALT + Tab\", hl.dsp.exec_cmd(\"true\"))",
        "hl.bind(\"ALT + ALT_L\", hl.dsp.exec_cmd(\"true\"), { release = true, non_consuming = true })",
        "hl.gesture({ fingers = 4, direction = \"up\", action = function() end })",
        "hl.gesture({ fingers = 3, direction = \"horizontal\", action = \"workspace\" })",
    ):
        probe(chunk)
        show("after")
    machine.screenshot("after-probes")
    print("BINDS", hyprctl("-j", "binds")[:600])
    print("LAYERS", hyprctl("-j", "layers")[:800])
    print("JOURNAL", machine.execute("journalctl -b --user-unit eva.service --machine=alice@.host -n 30 --no-pager")[1][-2000:])
