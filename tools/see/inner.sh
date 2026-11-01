#!/usr/bin/env bash
# Inside the sealed session of tools/see.sh: sway on a virtual output, then the
# scenario, which has these at hand:
#
#   start shell | lock | greet     the role, in preview where it has one
#   start app NAME [ARGS]          a tool of apps/, as its launcher runs it
#   stop                           ends the role
#   shot NAME                      a screenshot, $SEE_OUT/NAME.png
#   ipc VERB ARGS                  `morf ipc call` on the role
#   appipc VERB ARGS               the same, on the running tool's own socket
#   key NAME                       a key press, by its keysym name
#   text WORDS                     typed, character by character
#   click X Y, point X Y           sway's cursor, at output pixels; the sealed
#                                  seat has no pointer device, so no client
#                                  hears these: specs press with test.click
#   note COMMAND                   its output, added to $SEE_OUT/notes.txt
#   appearance THEME               the shell's appearance file changes
#   pause SECONDS                  waits
#
# tests/fixtures/bin-see is first on PATH: stand-ins for what must not reach a
# real session.
set -u
trap 'kill $(jobs -p) 2> /dev/null' EXIT
cd "$SEE_EVA"

export PATH="$SEE_EVA/tests/fixtures/bin-see:$PATH"
CONFIG=$XDG_RUNTIME_DIR/sway.conf
mkdir -p "$XDG_STATE_HOME/eva/displays"
touch "$XDG_STATE_HOME/eva/displays/outputs.sway"
cat > "$CONFIG" <<CONF
output * bg $SEE_EVA/tests/fixtures/wallpaper.png fill
output * render_bit_depth 8
xwayland disable
default_border none
include $XDG_STATE_HOME/eva/displays/outputs.sway
CONF
RENDER=$(ls /dev/dri/renderD* 2>/dev/null | head -1)
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDER_DRM_DEVICE=$RENDER \
  sway --unsupported-gpu -c "$CONFIG" > "$SEE_OUT/sway.log" 2>&1 &
for _ in $(seq 100); do ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock > /dev/null 2>&1 && break; sleep 0.1; done
SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock | head -1)
WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls -d wayland-[0-9] | head -1)
export SWAYSOCK WAYLAND_DISPLAY
swaymsg output HEADLESS-1 mode "$SEE_SCREEN@60Hz" > /dev/null

ROLE=""
start() {
  stop
  if [ "$1" = app ]; then
    shift
    sh "$SEE_EVA/apps/launch" "$@" > "$SEE_OUT/app-$1.log" 2>&1 &
    ROLE=$!
    sleep "${BOOT:-3}"
    return
  fi
  local args=()
  case "$1" in
    lock) args=(-- window preview) ;;
    greet) args=(-- preview) ;;
  esac
  morf "$1/init.lua" "${args[@]}" > "$SEE_OUT/$1.log" 2>&1 &
  ROLE=$!
  sleep "${BOOT:-3}"
}
stop() {
  [ -n "$ROLE" ] && kill "$ROLE" 2>/dev/null
  [ -n "$ROLE" ] && wait "$ROLE" 2>/dev/null
  ROLE=""
}
shot() { grim "$SEE_OUT/$1.png"; }
appearance() { printf '{ "theme": "%s", "font": "" }\n' "$1" > "$EVA_APPEARANCE"; }
ipc() { timeout 10 morf ipc call "$@"; }
key() { wtype -s 200 -k "$1"; }
text() { wtype -s 200 "$1"; }
pause() { sleep "$1"; }
point() { swaymsg seat seat0 cursor set "$1" "$2" > /dev/null; }
click() {
  point "$1" "$2"
  sleep 0.05
  swaymsg seat seat0 cursor press button1 > /dev/null
  sleep 0.05
  swaymsg seat seat0 cursor release button1 > /dev/null
}
appipc() { timeout 10 morf -i "$(basename "$WAYLAND_DISPLAY")-app-$ROLE" ipc call "$@"; }
note() { "$@" >> "$SEE_OUT/notes.txt" 2>&1; }

. "$SEE_STEPS"
stop
