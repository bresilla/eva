set -euo pipefail

action=${1:?expected off, wake, toggle, blank or unblank}
case "$action" in off|wake|toggle|blank|unblank) ;; *) exit 2 ;; esac
state="${XDG_RUNTIME_DIR:?}/phone-screen-${HYPRLAND_INSTANCE_SIGNATURE:?}"
exec 9>"$state.lock"
flock 9

now=$(awk '{printf "%.0f", $1 * 1000}' /proc/uptime)
last_wake=0
if [[ -r "$state.wake" ]]; then read -r last_wake < "$state.wake"; fi
powered=$(hyprctl -j monitors | jq -er 'if length == 0 then error("no outputs") else any(.[]; .dpmsStatus != false) end | tostring')
status=on
if [[ -r "$state.status" ]]; then read -r status < "$state.status"; fi

wake() {
  if [[ "$powered" == false ]]; then
    phone-dpms on
    printf '%s\n' "$now" > "$state.wake"
  fi
  # Lit dark and dim: the backlight goes back to where it stood.
  if [[ "$status" == ambient ]]; then
    brightnessctl -q -r || true
    printf '%s\n' "$now" > "$state.wake"
  fi
  publish on
}

publish() {
  printf '%s\n' "$1" > "$state.status.tmp"
  mv -f "$state.status.tmp" "$state.status"
}

if [[ "$action" == wake || "$action" == unblank ]]; then wake; exit; fi
# A call against the ear: dark and deaf to touch, the session left as it is.
if [[ "$action" == blank ]]; then
  publish off
  phone-dpms off || publish on
  exit
fi
if [[ "$action" == toggle ]]; then
  if [[ "$powered" == false || "$status" == ambient ]]; then wake; exit; fi
  # Ignore a duplicate power signal immediately after waking the display.
  if (( now - last_wake < 1000 )); then exit; fi
  sleep 0.25
fi

if [[ "${EVA_PHONE_GREETER:-0}" != 1 ]]; then
  locked() { hyprctl -j locked | jq -e '.locked == true' >/dev/null; }
  if ! locked; then
    systemctl --user start eva-idle-lock.service
    # A started process is not proof of a lock. Wait for the compositor to
    # confirm it before blanking; a failed locker leaves the display visible.
    for ((attempt = 0; attempt < 150; attempt++)); do
      locked && break
      systemctl --user is-active --quiet eva-idle-lock.service || exit 1
      sleep 0.2
    done
    locked || { echo 'eva did not acquire the session lock' >&2; exit 1; }
  fi
fi
# A panel the system says can stay lit, with a lock that chose to: the lock's
# ambient face stands instead of a blank, the backlight at its lowest. This keeps
# the panel and the GPU awake, so it spends power a blank does not.
if [[ "${EVA_PHONE_GREETER:-0}" != 1 && -e "$state.ambient" ]]; then
  if [[ "$status" != ambient ]]; then
    brightnessctl -q -s set 1% || true
    publish ambient
  fi
  exit
fi
# eva shields the sleeping authentication surface before the panel blanks.
# Its file watch also works while Wayland frame callbacks are stopped.
publish off
if ! phone-dpms off; then
  publish on
  exit 1
fi
