#!/usr/bin/env bash
# Inside the sealed session of tools/see.sh: sway on a virtual output, then the
# scenario, which has these at hand:
#
#   start shell | lock | greet     the role, in preview where it has one
#   start held                     the lock under ext-session-lock; skipped
#                                  when the host has a reader stack, and it
#                                  takes no keys: a held lock asks real PAM
#   start app NAME [ARGS]          a tool of apps/, as its launcher runs it
#   stop                           ends the role
#   shot NAME                      a screenshot, $SEE_OUT/NAME.png
#   ipc VERB ARGS                  `morf ipc call` on the role
#   appipc VERB ARGS               the same, on the running tool's own socket
#   toolipc VERB ARGS              the same, on the capture tool's socket
#   drawn                          waits for the role to answer and arrive
#   toolup                         waits for the capture tool to answer
#   key NAME                       a key press, by its keysym name
#   text WORDS                     typed, character by character
#   click X Y, point X Y           sway's cursor, at output pixels; the sealed
#                                  seat has no pointer device, so no client
#                                  hears these: specs press with test.click
#   note COMMAND                   its output, added to $SEE_OUT/notes.txt
#   appearance THEME               the shell's appearance file changes
#   pause SECONDS                  waits
#   window TITLE [APP_ID [COLOUR]] a real window of the sealed compositor
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
HELD=""
start() {
  stop
  PAGE=""
  if [ "$1" = app ] && [ "$#" -eq 2 ] && [ -z "${EVA_ZOOM_LENS:-}" ] && has_page "$2"; then
    # A tool that is a page: the shell, on that page.
    start shell
    page "$2"
    return
  fi
  if [ "$1" = app ]; then
    shift
    sh "$SEE_EVA/apps/launch" "$@" > "$SEE_OUT/app-$1.log" 2>&1 &
    ROLE=$!
    sleep "${BOOT:-3}"
    return
  fi
  local args=() file=$1
  case "$1" in
    lock) args=(-- window preview) ;;
    greet) args=(-- preview) ;;
    held)
      file=lock HELD=1
      for stack in eva-lock-finger eva-lock-face eva-lock-reader; do
        if [ -e "/etc/pam.d/$stack" ]; then
          echo "tools/see: /etc/pam.d/$stack exists, no held lock here" >&2
          exit 0
        fi
      done
      ;;
  esac
  morf "$file/init.lua" "${args[@]}" > "$SEE_OUT/$1.log" 2>&1 &
  ROLE=$!
  sleep "${BOOT:-3}"
}
stop() {
  [ -n "$ROLE" ] && kill "$ROLE" 2>/dev/null
  [ -n "$ROLE" ] && wait "$ROLE" 2>/dev/null
  ROLE="" HELD=""
}
unheld() {
  [ -z "$HELD" ] && return
  echo "tools/see: a held lock takes no keys" >&2
  exit 1
}
shot() { grim "$SEE_OUT/$1.png"; }
appearance() { printf '{ "theme": "%s", "font": "" }\n' "$1" > "$EVA_APPEARANCE"; }
ipc() { timeout 10 morf ipc call "$@"; }
key() { unheld; wtype -s 200 -k "$1"; }
text() { unheld; wtype -s 200 "$1"; }
pause() { sleep "$1"; }
point() { swaymsg seat seat0 cursor set "$1" "$2" > /dev/null; }
click() {
  point "$1" "$2"
  sleep 0.05
  swaymsg seat seat0 cursor press button1 > /dev/null
  sleep 0.05
  swaymsg seat seat0 cursor release button1 > /dev/null
}
# Whether tool $1 is a page, in Tools or Settings, rather than a program of its own.
has_page() {
  case "$1" in draw | find | kill | large | ruler | screenshot) return 1 ;; esac
  [ -f "$SEE_EVA/apps/$1/page.lua" ]
}
# The page of tool $1, in the Tools window or the Settings page it became.
page() {
  PAGE=$1
  case "$1" in
    keys) ipc settings input/shortcuts > /dev/null ;;
    breaks) ipc settings breaks > /dev/null ;;
    *) ipc tools "$1" > /dev/null ;;
  esac
  sleep "${BOOT:-2}"
}
# A verb of the tool on show: its page's, else its own program's.
appipc() {
  if [ -n "${PAGE:-}" ]; then ipc tool "$PAGE" "$@"; return; fi
  timeout 10 morf -i "$(basename "$WAYLAND_DISPLAY")-app-$ROLE" ipc call "$@"
}
toolipc() { timeout 10 morf -i "$(basename "$WAYLAND_DISPLAY")-screenshot" ipc call "$@"; }
drawn() {
  for _ in $(seq 300); do morf ipc verbs > /dev/null 2>&1 && break; sleep 0.1; done
  sleep "${ARRIVAL:-6}"
}
toolup() {
  for _ in $(seq 300); do toolipc state 2> /dev/null | grep -q '"ok":true' && break; sleep 0.1; done
  sleep "${SETTLE:-1}"
}
note() { "$@" >> "$SEE_OUT/notes.txt" 2>&1; }
window() { morf app "$SEE_EVA/tools/see/window_app.lua" -- "$@" > "$SEE_OUT/window-$1.log" 2>&1 & }

. "$SEE_STEPS"
stop
