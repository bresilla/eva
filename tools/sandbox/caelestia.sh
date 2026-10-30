# caelestia.sh -- a kind for morf's tools/sandbox/nested.sh: caelestia-dots/shell
# on Quickshell, the shell eva is a port of, run as a reference beside it.
#
#   $MORF_REPO/tools/sandbox/nested.sh tools/sandbox/caelestia.sh NAME STEPS
#
# CAELESTIA (a clone of github.com/caelestia-dots/shell), CAELESTIA_PKG (the
# output of `nix build CAELESTIA#caelestia-shell` -- see README.md),
# CAEL_CONFIG (a shell.json to seed), CAEL_SCHEME (a scheme.json to seed;
# without one caelestia keeps its built-in palette), NIXGL (GL wrapper for the
# nix-built Quickshell, default nixGLIntel). In the steps:
#   open NAME    one of its global shortcuts (launcher dashboard sidebar
#                utilities session showall lock nexus ...)
#   close [D]    drawer D, else every open drawer
#   ipc ARGS     `qs ipc call ARGS`, e.g. `ipc drawers toggle osd`
#   notify ARGS  a real notify-send, on the private bus only
CAELESTIA=${CAELESTIA:-$WORK/caelestia}
CAELESTIA_PKG=${CAELESTIA_PKG:-$WORK/caelestia-pkg}

kind_setup() {
  [ -f "$CAELESTIA/shell.qml" ] || { echo "no caelestia clone at $CAELESTIA" >&2; exit 1; }
  [ -x "$CAELESTIA_PKG/bin/caelestia-shell" ] || { echo "no caelestia build at $CAELESTIA_PKG" >&2; exit 1; }
  # caelestia's own reach into the machine: its CLI (wallpaper, schemes,
  # recording, screenshots), GPU probes, VPN clients, fingerprint and face
  # unlock probe (it answers "nothing enrolled"), ping, the session commands.
  for c in swappy gpu-screen-recorder nvidia-smi lspci glxinfo warp-cli tailscale \
           netbird wg-quick ping asdbctl fprintd-list logout hibernate suspend app2unit; do
    code=0; [ "$c" = fprintd-list ] && code=1
    printf '#!/bin/sh\necho "%s $*" >> "%s/stubbed.log"\nexit %s\n' "$c" "$OUT" "$code" > "$H/shim/$c"
    chmod +x "$H/shim/$c"
  done
  # Only logged, except that `caelestia wallpaper -f P` records P where the
  # shell reads the current wallpaper, as the real CLI would.
  cat > "$H/shim/caelestia" <<CAEL
#!/bin/sh
echo "caelestia \$*" >> "$OUT/stubbed.log"
[ "\$1 \$2" = "wallpaper -f" ] && printf '%s' "\$3" > "$H/.local/state/caelestia/wallpaper/path.txt"
exit 0
CAEL
  chmod +x "$H/shim/caelestia"
  # Notifications stay real: the shell under test is the notification
  # server, and notify-send only reaches the private bus.
  rm "$H/shim/notify-send"
  mkdir -p "$H/.config/caelestia" "$H/.local/state/caelestia/wallpaper" "$H/Pictures/Wallpapers"
  if [ -n "${CAEL_CONFIG:-}" ]; then cp "$CAEL_CONFIG" "$H/.config/caelestia/shell.json"
  # A fixed weather place, so it never looks the machine up by its address.
  else echo '{ "services": { "weatherLocation": "Reykjavik" } }' > "$H/.config/caelestia/shell.json"; fi
  [ -n "${CAEL_SCHEME:-}" ] && cp "$CAEL_SCHEME" "$H/.local/state/caelestia/scheme.json"
  # Its own wallpaper unless WALLPAPER says otherwise; the switcher lists
  # ~/Pictures/Wallpapers.
  cp "$CAELESTIA/assets/wallpaper.webp" "$H/Pictures/Wallpapers/"
  [ -d "$H/.local/share/wallpapers" ] && cp "$H/.local/share/wallpapers/"* "$H/Pictures/Wallpapers/"
  printf '%s' "${WALLPAPER:-$H/Pictures/Wallpapers/wallpaper.webp}" > "$H/.local/state/caelestia/wallpaper/path.txt"
  # Never the flake's launcher (it puts the real ddcutil, brightnessctl,
  # nmcli first on PATH): its environment minus PATH, and qs under it.
  "$KIND_DIR/caelestia-env.sh" "$CAELESTIA_PKG" > "$H/caelestia-env"
}

kind_start() {
  cat <<INNER
  # caelestia paints its own wallpaper. Its Quickshell and Qt come from nix,
  # so it needs nix's GL driver too.
  . "$H/caelestia-env"
  \${NIXGL:-nixGLIntel} "\$QS" -p "$CAELESTIA" > \$OUT/shell.log 2>&1 &
  S=\$!
  qsipc() { timeout 10 "\$QS" -p "$CAELESTIA" ipc call "\$@" 2>> \$OUT/hc.log; }
  # Its global shortcuts, as its keybinds send them -- except the launcher,
  # which toggles on the key's release, and a dispatched global only
  # presses: that one goes through its IPC toggle instead.
  open() {
    asked open
    if [ "\$1" = launcher ]; then qsipc drawers toggle launcher >> \$OUT/hc.log
    else hc dispatch "hl.dsp.global(\\"caelestia:\$1\\")" >> \$OUT/hc.log 2>&1; fi
  }
  # Not every drawer closes on Escape (the dashboard closes on leave), so
  # drawers are toggled shut over IPC: the one named (one call, for films),
  # or every open one (found first; the request is stamped after).
  close() {
    if [ -n "\${1:-}" ]; then asked close; qsipc drawers toggle \$1 >> \$OUT/hc.log; return; fi
    open_ones=""
    for d in \$(qsipc drawers list); do
      [ "\$(qsipc drawers isOpen \$d)" = 1 ] && open_ones="\$open_ones \$d"
    done
    asked close
    for d in \$open_ones; do qsipc drawers toggle \$d >> \$OUT/hc.log; done
  }
  ipc() { asked ipc; qsipc "\$@" >> \$OUT/hc.log; }
  notify() { asked notify; timeout 10 "$NOTIFY_SEND" "\$@" >> \$OUT/hc.log 2>&1; }
INNER
}
