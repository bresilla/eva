#!/usr/bin/env bash
# Inside the sealed session of tools/see.sh: sway on a virtual output, then the
# scenario, which has these at hand:
#
#   start shell | lock | greet     the role, in preview where it has one
#   stop                           ends the role
#   shot NAME                      a screenshot, $SEE_OUT/NAME.png
#   ipc VERB ARGS                  `morf ipc call` on the role
#   key NAME                       a key press, by its keysym name
#   text WORDS                     typed, character by character
#   click X Y, point X Y           the pointer, at output pixels
#   pause SECONDS                  waits
set -u
trap 'kill $(jobs -p) 2> /dev/null' EXIT
cd "$SEE_EVA"

CONFIG=$XDG_RUNTIME_DIR/sway.conf
cat > "$CONFIG" <<CONF
output * bg $SEE_EVA/tests/fixtures/wallpaper.png fill
xwayland disable
default_border none
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

. "$SEE_STEPS"
stop
