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

  testScript = ''
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
