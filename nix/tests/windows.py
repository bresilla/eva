import json
import shlex


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
    out = machine.execute(session(f"morf ipc call {quoted}"))[1].strip()
    print(f"IPC {quoted} => {out[:700]}")
    return out


def clients():
    return json.loads(hyprctl("-j", "clients"))


def client(title):
    for row in clients():
        if row["title"] == title:
            return row
    raise AssertionError(f"no window titled {title}")


def login(password):
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


def open_window(title):
    hyprctl("eval", f'hl.dispatch(hl.dsp.exec_cmd("foot -T {title} sleep 3600"))')
    machine.wait_until_succeeds(session(f"hyprctl --instance 0 clients | grep -q 'title: {title}'"), timeout=30)


def run(password):
    login(password)
    for title in ("one", "two", "three"):
        open_window(title)
    machine.sleep(2)
    print("LIST", ipc("windows"))

    with subtest("the overview opens over real windows"):
        ipc("overview", "open")
        machine.sleep(4)
        machine.screenshot("overview")
        print("SHOTS", ipc("windows", "shots"))
        ipc("overview", "close")
        machine.sleep(2)

    with subtest("a window on a hidden workspace is captured"):
        address = client("three")["address"]
        hyprctl("eval", f'hl.dispatch(hl.dsp.window.move({{ workspace = "2", follow = false, window = "address:{address}" }}))')
        machine.sleep(1)
        ipc("overview", "open")
        machine.sleep(4)
        print("SHOTS", ipc("windows", "shots"))
        ipc("overview", "close")
        machine.sleep(2)
