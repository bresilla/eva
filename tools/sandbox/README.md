# sandbox

eva's scenarios for morf's sandbox (`tools/sandbox/nested.sh` in a morf
checkout, `MORF_REPO` below): a nested Hyprland under a headless cage, with a
private runtime dir, session bus, scratch HOME and stubbed system commands.
See morf's `tools/sandbox/README.md` for the step commands and the
environment it reads. eva runs there as a morf configuration:

    MORF_CONFIG=$PWD/shell/init.lua MORF_ENV="EVA_DRY_RUN=1" \
      $MORF_REPO/tools/sandbox/nested.sh morf gallery tools/sandbox/caelestia-phase1.steps

and caelestia-dots/shell, the shell eva is a port of, runs beside it as a
reference through the kind file here:

    $MORF_REPO/tools/sandbox/nested.sh tools/sandbox/caelestia.sh gallery \
      tools/sandbox/caelestia-gallery.steps

- `caelestia-gallery.steps` shoots rest, launcher (apps, search, actions,
  wallpapers), each dashboard tab, sidebar, utilities, session, osd, the
  bar's popouts, notifications, a toast, showall, nexus and the lock screen;
  `caelestia-films.steps` films drawers opening and closing, cropped to each.
- `caelestia-phase1.steps` and `caelestia-phase2.steps` shoot the states the
  port has, as the gallery does; `caelestia-motion.steps` films the drawer
  motion and the dashboard's hover edge for either.
- `caelestia-themes.steps` shoots every main surface, once per visual theme
  (`EVA_STYLE` in `MORF_ENV`); `caelestia-media.steps` the media tab and card
  with `fakeplayer.py` playing.
- `caelestia-a11y.steps`, with `A11Y=1`, writes what a screen reader sees.
- `caelestia-show.steps` is a short tour that then leaves the session to you
  until `TIMEOUT`:

      VISIBLE=1 TIMEOUT=3600 MORF_CONFIG=$PWD/shell/init.lua \
        MORF_ENV="EVA_WALLPAPER=/path/to/wallpaper" \
        $MORF_REPO/tools/sandbox/nested.sh morf show tools/sandbox/caelestia-show.steps

## caelestia

caelestia-dots/shell wants git Quickshell and a native QML plugin built
against the same Qt, plus libqalculate, aubio, cava, fftw, Qt ShaderTools,
qt6-imageformats (webp), the m3shapes QML module and its fonts. Arch's
Quickshell 0.3.1 and Qt 6.11 lack ShaderTools, imageformats' webp and the C
libraries, so everything comes from the clone's own flake instead, into the
nix store -- nothing system-wide:

    git clone https://github.com/caelestia-dots/shell caelestia
    nix build ./caelestia#caelestia-shell --out-link caelestia-pkg

That builds Quickshell from its git flake input (with `qtimageformats` and
m3shapes), the plugin and the helper library against nixpkgs' Qt, and a
launcher. The launcher is never run: it puts the real `ddcutil`,
`brightnessctl`, `nmcli`, ... first on PATH. `caelestia-env.sh` reads its
environment back out of the two nix wrappers (QML import path for the plugin
and m3shapes via `NIXPKGS_QT6_QML_IMPORT_PATH`, Qt plugin path, fonts.conf
with Material Symbols, Rubik and CaskaydiaCove, `CAELESTIA_LIB_DIR`, xkb
rules), drops PATH, and the sandbox starts Quickshell's own `qs` under it,
under `nixGLIntel` (`NIXGL`) for nix's GL driver, with `-p` the clone.

The scratch HOME gets `~/.config/caelestia/shell.json` (`CAEL_CONFIG`, else
one naming a fixed weather place so it never geolocates the machine),
optionally `~/.local/state/caelestia/scheme.json` (`CAEL_SCHEME`; without
it the built-in palette), `~/Pictures/Wallpapers`, and
`~/.local/state/caelestia/wallpaper/path.txt` (`WALLPAPER`, else its own
`assets/wallpaper.webp`). caelestia paints its own wallpaper; no `awww`.

- `open NAME` dispatches `hl.dsp.global("caelestia:NAME")` -- dashboard,
  sidebar, utilities, session, showall, lock, nexus, ... -- except launcher,
  which toggles on the key's release (a dispatched global only presses) and
  so goes through its IPC. `close [D]` toggles drawer D, or every open one,
  over IPC (the dashboard does not close on Escape).
- `ipc ARGS` is `qs ipc call ARGS`: `ipc drawers toggle osd`,
  `ipc toaster info T M ICON`, `ipc nexus open`.
- `notify ARGS` is a real `notify-send`: the shell is the notification
  server on the private bus.
- Stubbed besides the common set: its `caelestia` CLI (which still records
  `wallpaper -f P`), swappy, gpu-screen-recorder, nvidia-smi, lspci,
  glxinfo, warp-cli, tailscale, netbird, wg-quick, ping, asdbctl,
  fprintd-list (answers "nothing enrolled"), logout, hibernate, suspend,
  app2unit.

Not there in the sandbox: audio (no PipeWire, so the osd and media show
nothing), Bluetooth, UPower and power profiles (no system bus), networks
(nmcli is a stub), and unlocking (PAM from nix finds no modules; nothing is
typed). The weather comes from the network.

## The phone bench

`phone.sh` opens a phone-sized nested session (a Fairphone 6's 868 x 1932
logical pixels) as a window on your desktop, running this checkout, and
takes commands through a FIFO (`phone.steps`):

    tools/sandbox/phone.sh &
    tools/sandbox/phone.sh ctl greet
    tools/sandbox/phone.sh ctl 'shot greet-rest'
    tools/sandbox/phone.sh ctl quit

It needs a morf checkout with a release build (`MORF_REPO`, default
`../morf` beside this one).
