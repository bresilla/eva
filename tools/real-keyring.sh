#!/usr/bin/env bash
# tests/real_keyring_spec.lua on a real keyring: a gnome-keyring unlocked with a
# throwaway password, in a throwaway HOME, on a session bus of its own. Nothing
# here reaches the keyring of the session it is started from.
#
#   PATH=<libsecret>/bin:<gnome-keyring>/bin:$PATH dbus-run-session -- tools/real-keyring.sh
set -eu
cd "$(dirname "$0")/.."
for tool in secret-tool gnome-keyring-daemon morf; do
  command -v "$tool" > /dev/null || { echo "real-keyring: no $tool on PATH" >&2; exit 2; }
done
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || { echo "real-keyring: run it under dbus-run-session" >&2; exit 2; }

home=$(mktemp -d /tmp/eva-keyring-XXXXXX)
run=$(mktemp -d /tmp/eva-keyrun-XXXXXX)
chmod 700 "$run"
trap 'rm -rf "$home" "$run"' EXIT
export HOME=$home XDG_RUNTIME_DIR=$run XDG_DATA_HOME=$home/.local/share EVA_REAL_KEYRING=1
mkdir -p "$XDG_DATA_HOME/keyrings"

printf 'throwaway\n' | gnome-keyring-daemon --unlock --components=secrets --daemonize > /dev/null
sleep 1
morf test tests/real_keyring_spec.lua
