#!/usr/bin/env bash
# tools/see.sh SCENARIO: one scenario of tools/see/ on a private headless sway,
# with real Wayland input, its screenshots left in .see/.
#
#   tools/see.sh quick
#   SCREEN=868x1932 TOUCH=1 STYLE=material MODE=light tools/see.sh quick
#
# SCREEN is the output, STYLE the visual theme, MODE dark or light, TOUCH=1 a
# machine with a touchscreen and no keyboard. OUT overrides the output folder,
# TIMEOUT the seconds it may take.
#
# The session is sealed: an empty environment, its own runtime dir, HOME and
# session bus, no system bus, and a fixed wallpaper and palette. Nothing here
# asks PAM or greetd, and EVA_DRY_RUN holds back every action on the machine.
set -eu
cd "$(dirname "$0")/.."
EVA=$PWD
NAME=${1:?usage: tools/see.sh SCENARIO}
STEPS=$EVA/tools/see/$NAME.steps
[ -f "$STEPS" ] || { echo "no scenario $STEPS" >&2; exit 1; }
SCREEN=${SCREEN:-1920x1080}
STYLE=${STYLE:-tsugumori}
MODE=${MODE:-dark}
OUT=${OUT:-$EVA/.see/$NAME-$STYLE-$MODE-$SCREEN}
rm -rf "$OUT"; mkdir -p "$OUT"

# Always /tmp: a long TMPDIR (nix develop's) pushes sockets past sun_path.
RUN=$(mktemp -d /tmp/evaXXXX)
HOME_DIR=$(mktemp -d /tmp/eva-homeXXXX)
chmod 700 "$RUN"
trap 'rm -rf "$RUN" "$HOME_DIR"' EXIT
mkdir -p "$HOME_DIR/.config" "$HOME_DIR/.local/share" "$HOME_DIR/.local/state" "$HOME_DIR/.cache/lule"
sed -e "s|@WALLPAPER@|$EVA/tests/fixtures/wallpaper.png|" -e "s|@MODE@|$MODE|" \
  tests/fixtures/lule-colors.json > "$HOME_DIR/.cache/lule/colors.json"
printf '{ "theme": "%s", "font": "" }\n' "$STYLE" > "$HOME_DIR/.config/appearance.json"

DEVICES=$EVA/tests/fixtures/input-devices
[ -n "${TOUCH:-}" ] && DEVICES=$EVA/tests/fixtures/input-devices-touch

setsid env -i \
  PATH="$PATH" USER="${USER:-eva}" LC_ALL=C.UTF-8 TERM=dumb \
  HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" XDG_DATA_HOME="$HOME_DIR/.local/share" \
  XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" \
  XDG_RUNTIME_DIR="$RUN" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$RUN/no-system-bus" \
  LULE_A="$HOME_DIR/.cache/lule" EVA_APPEARANCE="$HOME_DIR/.config/appearance.json" \
  EVA_WALLPAPER_CONFIG=/nonexistent EVA_DRY_RUN=1 EVA_INPUT_DEVICES="$DEVICES" \
  EVA_THEME_MODE="$MODE" MORF_FONT_PATH="$EVA/shell/fonts:${MORF_FONT_PATH:-}" \
  SEE_EVA="$EVA" SEE_OUT="$OUT" SEE_SCREEN="$SCREEN" SEE_STEPS="$STEPS" \
  timeout "${TIMEOUT:-90}" dbus-run-session -- bash "$EVA/tools/see/inner.sh" \
  || echo "tools/see: the session ended with $?" >&2
echo "$OUT"
