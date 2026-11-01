# A real login in a VM, with a throwaway user and password: greetd, the greeter,
# the password typed, the session, and a screenshot at each step. The handoff
# is sampled as fast as QEMU gives frames, and its colours printed.
#
# The times are a software GPU's, slowed by the sampling: the order is what this
# shows. The black it allows is the first commit of each Hyprland: aquamarine
# clears a new buffer to black and shows it until the first frame is rendered.
#
# The module's compositor configuration is Lua, which Hyprland reads from 0.55,
# so the nixpkgs under the test needs that Hyprland:
#
#   nix build .#login-test --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
{ module, wallpaper }:
let
  password = "correct horse battery staple";
  software = {
    LIBGL_ALWAYS_SOFTWARE = "1";
    MORF_PRESENT = "swapchain";
  };
in
{
  name = "eva-login";

  nodes.machine =
    { pkgs, ... }:
    let
      # Stands in for lule: the fixture picture and a palette made from it.
      lule = pkgs.writeShellScriptBin "lule" ''
        for argument in "$@"; do
          case "$argument" in
            --output=*) cp ${wallpaper} "''${argument#--output=}" ;;
            --cache=*)
              mkdir -p "''${argument#--cache=}"
              printf '{"wallpaper":"","theme":"dark","colors":["#10141c","#7fb4e8"]}' \
                > "''${argument#--cache=}/colors.json"
              ;;
          esac
        done
      '';
    in
    {
      imports = [ module ];
      programs.eva = {
        enable = true;
        user = "alice";
        usePackagedShell = true;
        lulePackage = lule;
        idle.lockTimeout = 0;
        idle.suspendTimeout = 0;
        greeter.environment = software;
      };
      users.users.alice = {
        isNormalUser = true;
        inherit password;
      };
      # A software GPU: morf presents through a swapchain, not dmabufs.
      environment.sessionVariables = software;
      systemd.user.services.eva.environment = software;
      hardware.graphics.enable = true;
      environment.systemPackages = [ pkgs.jq ];
      virtualisation = {
        memorySize = 4096;
        cores = 4;
        diskSize = 8192;
        qemu.options = [
          "-vga none"
          "-device virtio-gpu-pci"
        ];
      };
    };

  extraPythonPackages = python: [ python.pillow ];

  testScript =
    { nodes, ... }:
    ''
    import time

    from PIL import Image

    def corner(name):
        with Image.open(machine.out_dir / f"{name}.png") as picture:
            return picture.convert("RGB").getpixel((4, 4))

    def tty1_text():
        return machine.succeed("tr -d ' \\000' < /dev/vcs1 | wc -c").strip()

    machine.start()
    machine.wait_for_unit("greetd.service")

    with subtest("the wallpaper bridge wrote the picture's dominant colour"):
        machine.wait_until_succeeds("test -s /var/lib/eva/wallpaper/alice/dominant", timeout=120)
        machine.succeed("grep -Eq '^#[0-9a-f]{6}$' /var/lib/eva/wallpaper/alice/dominant")
        assert machine.succeed("cat /var/lib/eva/wallpaper/alice/dominant").strip() != "#10141c", (
            "the palette's fallback instead of the picture's colour"
        )

    with subtest("the greeter comes up on its own Hyprland"):
        machine.wait_until_succeeds("pgrep -u greeter Hyprland", timeout=120)
        machine.sleep(5)
        machine.screenshot("01-greeter-starting")
        machine.wait_until_succeeds("pgrep -u greeter -f 'morf.*greet'", timeout=120)
        machine.sleep(15)
        machine.screenshot("02-greeter-rest")
        machine.succeed("test $(pgrep -u greeter -c Hyprland) -eq 1")

    with subtest("the password goes in"):
        machine.send_key("ret")
        machine.sleep(3)
        machine.screenshot("03-greeter-sheet")
        machine.send_chars("${password}")
        machine.sleep(1)
        machine.screenshot("04-greeter-typed")
        machine.send_chars("\n")

    with subtest("the gap is the wallpaper's colour, with no text on the VT"):
        wallpaper = tuple(bytes.fromhex(machine.succeed("cut -c2- /var/lib/eva/wallpaper/alice/dominant").strip()))
        black = (0, 0, 0)
        frames = []
        began = time.monotonic()
        while time.monotonic() - began < 40:
            name = f"05-handoff-{len(frames):03}"
            machine.screenshot(name)
            frames.append((time.monotonic() - began, corner(name)))
            if len(frames) > 1 and frames[-2][1] == black and frames[-1][1] != black:
                break
        for seconds, colour in frames:
            print(f"handoff {seconds:6.3f}s corner {colour}")
        colours = [colour for _, colour in frames]
        assert wallpaper in colours, f"the wallpaper's colour {wallpaper} never showed"
        assert black in colours and colours.index(wallpaper) < colours.index(black), (
            "the wallpaper's colour must fill the gap until the compositor's first commit"
        )
        blackout = [seconds for seconds, colour in frames if colour == black]
        print(f"black from the compositor's first commit: {blackout[-1] - blackout[0]:.3f}s")
        assert blackout[-1] - blackout[0] < 5, "the compositor's first frame never came"
        assert tty1_text() == "0", "text on tty1 in the gap"
        machine.wait_until_succeeds("pgrep -u alice Hyprland", timeout=120)
        machine.sleep(5)
        machine.screenshot("06-session-starting")
        machine.wait_until_succeeds(
            "systemctl --user --machine=alice@.host is-active eva.service", timeout=180
        )
        machine.sleep(10)
        machine.screenshot("07-session")
        assert tty1_text() == "0", "text on tty1 in the session"

    with subtest("the session's output went to the journal"):
        machine.succeed("journalctl -b -t eva-session | grep -q 'Selected compositor ID'")

    alice = "runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

    def session():
        return machine.succeed("loginctl list-sessions --no-legend | awk '$3 == \"alice\" { print $1; exit }'").strip()

    def is_locked():
        return f"test \"$(loginctl show-session {session()} -p LockedHint --value)\" = yes"

    def settings(text):
        path = machine.succeed("cat /home/alice/.local/state/eva/settings-path").strip()
        machine.succeed(f"cat > /tmp/settings.json <<'END'\n{text}\nEND")
        machine.succeed(f"install -D -o alice -m 600 /tmp/settings.json {path}")

    def idle_mark():
        # Where hypridle runs it from: alice's user manager.
        machine.succeed(f"{alice} systemd-run --user --wait --quiet ${nodes.machine.system.build.evaIdleLock}")

    def locked_up():
        machine.wait_until_succeeds(is_locked(), timeout=90)
        machine.wait_until_succeeds("pgrep -u alice -f 'morf.*lock'", timeout=60)
        # The compositor's confirmation, and the first frame on it.
        machine.sleep(6)

    def unlock():
        machine.send_chars("${password}\n")
        machine.wait_until_fails(is_locked(), timeout=60)
        machine.wait_until_fails("pgrep -u alice -f 'morf.*lock'", timeout=60)
        machine.sleep(3)

    with subtest("the system's files are there for the shell and the lock"):
        machine.succeed("jq -e '.managed.lock == 0 and .sleep_lock == true' /etc/eva/idle.json")
        machine.succeed("jq -e 'type == \"object\"' /etc/eva/lock.json")

    with subtest("real PAM: a wrong password keeps the lock, the right one lifts it"):
        machine.succeed(f"loginctl lock-session {session()}")
        locked_up()
        machine.screenshot("09-lock-rest")
        machine.send_chars("not the password\n")
        # The verdict, then a moment for the field to take keys again.
        machine.wait_until_succeeds("journalctl -b | grep -q 'more authentication failure'", timeout=90)
        machine.sleep(3)
        machine.screenshot("10-lock-wrong")
        machine.succeed(is_locked())
        unlock()
        machine.screenshot("11-unlocked")

    with subtest("a lock asked for by the idle timer opens on a key, inside the window"):
        settings('{"lock":{"grace_seconds":60}}')
        idle_mark()
        locked_up()
        machine.screenshot("12-idle-lock")
        machine.succeed(is_locked())
        machine.send_key("shift")
        machine.wait_until_fails(is_locked(), timeout=30)
        machine.wait_until_fails("pgrep -u alice -f 'morf.*lock'", timeout=60)
        machine.sleep(3)

    with subtest("a lock nobody marked wants the password, the window set or not"):
        machine.succeed(f"loginctl lock-session {session()}")
        locked_up()
        machine.send_key("a")
        machine.sleep(5)
        machine.succeed(is_locked())
        machine.screenshot("13-manual-lock-holds")
        machine.send_key("esc")
        machine.sleep(1)
        unlock()

    with subtest("the window ends with the time, and the password is back"):
        settings('{"lock":{"grace_seconds":2}}')
        idle_mark()
        locked_up()
        machine.send_key("a")
        machine.sleep(5)
        machine.succeed(is_locked())
        machine.send_key("esc")
        machine.sleep(1)
        unlock()

    with subtest("what leaves the shell for the lock stops at the chosen level"):
        settings('{"lock":{"notifications":{"level":"count","new_only":false}}}')
        machine.sleep(2)
        machine.succeed(
            f"{alice} busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications "
            "org.freedesktop.Notifications Notify susssasa{sv}i app 0 \"\" 'Secret summary' 'secret body' 0 0 5000"
        )
        machine.wait_until_succeeds(
            "jq -e '.notifications.count == 1 and .notifications.level == \"count\"' /run/user/1000/eva/lock-view.json",
            timeout=30,
        )
        machine.fail("grep -q -i secret /run/user/1000/eva/lock-view.json")
        machine.succeed("test \"$(stat -c %a /run/user/1000/eva/lock-view.json)\" = 600")

    with subtest("the greeter keeps who came last, and nothing else"):
        machine.succeed("jq -e '.user == \"alice\" and (.sessions.alice | type) == \"string\"' /var/lib/greetd/.local/state/eva/greeter.json")
        machine.fail("grep -q 'correct horse' /var/lib/greetd/.local/state/eva/greeter.json")

    with subtest("the greeter takes the mode the session recorded"):
        machine.wait_until_succeeds("test -s /var/lib/eva/ui-scale/alice/outputs", timeout=30)
        recorded = machine.succeed("cut -f2 /var/lib/eva/ui-scale/alice/outputs").strip()
        machine.succeed("loginctl terminate-user alice")
        machine.wait_until_fails("pgrep -u alice Hyprland", timeout=60)
        machine.wait_until_succeeds("pgrep -u greeter -f 'morf.*greet'", timeout=120)
        machine.sleep(10)
        machine.screenshot("08-greeter-again")
        assert tty1_text() == "0", "text on tty1 back at the greeter"
        monitors = machine.succeed(
            "runuser -u greeter -- env XDG_RUNTIME_DIR=/run/user/$(id -u greeter) hyprctl --instance 0 monitors"
        )
        size, refresh = recorded.split("@")
        assert f"{size}@{refresh[:5]}" in monitors, f"{recorded} not in {monitors}"
  '';
}
