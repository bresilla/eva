# A real alarm on a real user systemd in a VM, with no shell and no window
# running: eva-clock's job makes the timer unit, the unit fires, eva-clock rings.
# notify-send is a stand-in that logs and answers Stop; there is no compositor,
# so the job runs through `morf check`.
#
#   nix build .#clock-test
{ eva, morf }:
{
  name = "eva-clock";

  nodes.machine =
    { pkgs, ... }:
    let
      job = pkgs.writeShellScriptBin "clock-job" ''
        exec ${morf}/bin/morf check ${eva}/share/eva/apps/common/job/app.lua \
          --no-dbus --after 3000 --wait 3000 -- clock "$@"
      '';
      notify = pkgs.writeShellScriptBin "notify-send" ''
        printf '%s\n' "$*" >> /tmp/rang
        printf stop
      '';
    in
    {
      users.users.alice = {
        isNormalUser = true;
        linger = true;
      };
      environment.systemPackages = [
        eva
        job
        notify
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")


    def alice(command):
        return machine.succeed(
            f"su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 {command}'"
        )


    def timers():
        return alice("systemctl --user list-units --all --type=timer --plain --no-legend")


    with subtest("a timer becomes a unit and rings with nothing else running"):
        alice("clock-job add timer 20 s egg")
        assert "eva-alarm-" in timers(), timers()
        machine.wait_until_succeeds("grep -q egg /tmp/rang", timeout=60)
        print(machine.succeed("cat /tmp/rang"))

    with subtest("a repeating alarm keeps its unit, on the calendar it was given"):
        alice("clock-job add every weekday 7:30 gym")
        listed = alice("systemctl --user cat \"eva-alarm-*.timer\"")
        assert "OnCalendar=Mon,Tue,Wed,Thu,Fri *-*-* 07:30:00" in listed, listed

    with subtest("sync puts back a unit a logout took away"):
        alice("systemctl --user stop \"eva-alarm-*.timer\"")
        assert "eva-alarm-" not in timers().replace("inactive", ""), timers()
        alice("clock-job sync")
        machine.wait_until_succeeds(
            "su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active \"eva-alarm-*.timer\"'",
            timeout=30,
        )

    with subtest("cancelling takes the unit away"):
        alice("clock-job cancel all")
        machine.wait_until_fails(
            "su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active \"eva-alarm-*.timer\"'",
            timeout=30,
        )
  '';
}
