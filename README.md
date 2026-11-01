# eva

A desktop shell, lock screen and greeter for
[morf](https://github.com/paneworks/morf). It is a clean-room
reimplementation of [caelestia-dots/shell](https://github.com/caelestia-dots/shell)'s
look and behaviour, written from watching the original run rather than from
its source, with two visual themes: Material and Tsugumori.

## Install on NixOS

```nix
{
  inputs.eva.url = "github:bresilla/eva";

  outputs = { nixpkgs, eva, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        eva.nixosModules.default
        {
          programs.eva = {
            enable = true;
            user = "you";
            lulePackage = lule; # the colour tool behind the wallpaper
          };
        }
      ];
    };
  };
}
```

The module runs the shell as the `eva` user service, the greeter under
greetd on a Hyprland of its own and the lock screen from Hyprland's idle
daemon. It also handles the UI scale shared with the greeter, the wallpaper
bridge, PAM, and, optionally, phone gestures. Its options live under
`programs.eva`: `uiScale`, `idle.*`, `phone.*`, `hyprland.extraConfig`,
`greeter.*`, `seamless.*`, `wallpaperLogo` and `usePackagedShell`.

`seamless.enable`, on by default, hides the way from boot to the desktop. Two
compositors cannot share a frame, so greetd's switch between them always has a
gap; this makes the gap the wallpaper's colour rather than black and text. One
moment stays black: each Hyprland shows a cleared buffer from its first commit
until its first rendered frame, and no configuration reaches that.

- The kernel and systemd stay quiet, tty1 has no getty and no cursor, and
  greetd stays on tty1. Other VTs get their cursor back at the login prompt.
- The session's own output goes to the journal (`journalctl -t eva-session`),
  through `EVA_SESSION_WRAPPER`, which the greeter puts in front of every
  session it starts.
- The wallpaper bridge writes the picture's dominant colour beside it. Both
  Hyprlands use it as `background_color`, and tty1 uses it as its background.
- The session records each output's mode, position, scale and transform in
  `outputs` beside the scale file, and the greeter sets the same, so both ask
  the display for one mode.
- A right password clears its dots, fades the form, frame and clock off the
  wallpaper in 170 ms, and draws nothing but the picture before asking greetd
  for the session. The compositor ends with that bare wallpaper as its last
  frame.

The first shell of a session then brings the frame, the rail and the bar in from
the edges; a lock lifting does the same, and `morf reload` and a theme switch do
not. `seamless.plymouth = true` adds Plymouth, which hands its last frame to the
greeter and ends under the greeter's first frame.

On a phone, `phone.enable` adds continuous touch gestures, a hidden pointer and
deliberate double-tap or power-button wake. `phone.idleTimeout = 0` disables
automatic locking in the user session; the phone greeter still blanks after
one minute. A blanked lock screen stops its fingerprint reader, and waking
the display starts it again. Panels follow the finger and carry release
speed into their settling animation. An inward pull from the left edge opens Apps and from the
right edge opens Web. A short, fast fling works too, while cancelled pulls and
authentication prompts suppress launcher gestures. Bottom gestures remain
available for workspaces and the keyboard. Lists use Android's
[OverScroller spline physics](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/widget/OverScroller.java):
faster releases coast farther, touching stops the coast, and slow frames do not
change the travel distance. `phone.gestureDriver = "lisgd"` selects the
completed-swipe fallback; the default is `"native"`.

eva pins the morf release it is written against in `flake.nix`, and the engine
comes prebuilt from the binary cache. The engine and its Lua library always
come from that same release. The packaged shell is installed as
`/etc/xdg/morf/eva`. A checkout linked as `~/.config/eva` runs in its place,
so edits need no rebuild; each start runs `morf check` on it first and falls
back to the packaged one when it fails. `programs.eva.usePackagedShell` always
runs the packaged one.

### From the binary cache

Each push to `main` publishes `.#eva` to `cache.bresilla.com/bresilla` under
the pins `eva-x86_64-linux` and `eva-aarch64-linux`, beside morf's
`morf-<system>` pins. That one output holds everything eva installs: the shell,
lock screen and greeter in `share/eva`, their fonts in `share/fonts`,
`eva-keyring` in `bin`, and the NixOS module in `nixos`. A configuration that takes both as cached store paths, without eva's
flake, imports the module from the output and hands it the two packages:

```nix
imports = [
  (import "${eva}/nixos" { packages = _: { inherit eva morf; }; })
];
```

`nix/detached.nix` evaluates the test machine that way, from a downloaded
output; the cache workflow runs it after each publish.

## Tools

Quick controls stay in the shell; heavier work has a tool of its own, in
`apps/`. A tool is a real window that draws with the shell's theme, kit and
palette, follows lule's colours and the chosen appearance live, and works when
the shell is not running. On NixOS they are on `PATH`, each with a desktop entry.

| Command | What it does |
|---------|--------------|
| `eva VERB`, `eva open settings/power`, `eva commands --json` | the shell from a command line, the front door for keybindings |
| `eva-displays` | a canvas to arrange monitors with edge snapping; mode, scale, rotation, VRR and mirroring; a countdown that reverts; profiles matched on make, model and serial that apply on hotplug |
| `eva-screenshot region\|window\|screen [--edit\|--copy\|--save] [--delay N] [--last]` | through the shell's editor, alone when it is down; `ocr` and `qr` copy what they read |
| `eva-record region\|window\|monitor [--audio KIND]`, `eva-record stop` | `gpu-screen-recorder` with a stop indicator |
| `eva-colorpick [--pick]` | a frozen screen with a magnifier; hex, rgb, hsl and oklch; recent colours |
| `eva-keys` | a searchable sheet of the live bindings and the shell's own |
| `eva-nightlight on\|off\|toggle\|auto\|daemon\|times` | warmer light over `hyprsunset`, by the sun at `services.weather_location` |
| `eva-clipboard [--watch]` | a history of text and pictures with pins, skipping what a password manager marks; on NixOS `--watch` runs as a user service |
| `eva-battery status`, `eva-battery limit on\|off` | the charge limit, through UPower's `EnableChargeThreshold` |

`make app displays` runs one from a checkout.

`eva-displays` writes what you keep to `$XDG_STATE_HOME/eva/displays/`. eva's
Hyprland session loads `monitors.lua` from there; on sway, add
`include $XDG_STATE_HOME/eva/displays/outputs.sway` to your configuration.

A tool's folder holds `app.lua` and three links: `lua -> ../../shell`, which is
how it reaches `theme`, `kit`, `palette` and `config`, `common -> ../common`, and
`fonts -> ../../shell/fonts`. `apps/launch` finds the shell's appearance and
settings files, which the shell names in `$XDG_STATE_HOME/eva/settings-path`.

## Helpers

The native pieces the shell talks to live in `helpers/`, and `.#eva` builds
them in:

- `helpers/keyring`: the GNOME Keyring prompt bridge, `eva-keyring`
  ([build and tests](helpers/keyring/README.md)).
- `helpers/pam`: `eva-auth-step`, the PAM markers that tell the shell which
  step sudo is on (face, finger, password, done), and installers for the
  markers and the lock's finger and face stacks on non-NixOS systems.

## Which morf

`morf.lua` says which engine eva is written for (`morf = ">=0.6.0"`) and the
release line it was last tested on (`tested = "0.6"`). An engine that reads it
(morf 0.4 and later) refuses eva when it is too old, with a plain
`eva 0.1.0 needs morf >=0.4.0; this is morf 0.3.0`, and `morf check` fails, so
the NixOS launcher falls back. An engine past the tested line runs eva and
logs a warning. A theme's manifest can ask for more than eva does
(`morf = ">=0.4"` beside its `api`): on an engine that cannot meet it, eva
starts in Material with a notification saying why, and the switcher refuses
the theme with the same reason.

## Run and develop

```sh
nix develop                          # morf, at the pinned release, on PATH
morf shell/init.lua                  # the shell
morf lock/init.lua -- window preview # the lock screen, without authenticating
make test                            # every spec (tools/test.sh)
make check                           # the shell, lock and greeter load cleanly
make build                           # the Nix package, into ./result
```

## Using it

The optional typed Prek controller receiver is documented in
[Prek](https://github.com/paneworks/morf/blob/main/docs/PREK.md); broker binding and recognizer
handoff remain pending.
The top, bottom, left and right panel triggers wait for a 600 ms hover
before opening, including at the outermost pixel. Leaving early cancels
the pending opening. IPC also opens them:

```sh
morf ipc call capture toggle
morf ipc call bottom open
morf ipc call assistant open
morf ipc call tasks open
morf ipc call calendar open
morf ipc call close
```

The bottom edge opens a large workspace with **Assistant** and **Drop**
tabs. Material's maximum size is 1696 × 751, with the same proportional
reduction on smaller screens (20% narrower and 40% shorter than the previous
panel). Tsugumori keeps that desktop footprint and uses the available width
on compact screens, with vertically scrollable pages.
Assistant awaits a provider; Drop is a placeholder for the future
[termworks/drop](https://github.com/termworks/drop) messaging and file-sharing
integration. Open it directly with `morf ipc call bottom open drop`.
Click outside the workspace to close it from either tab. When opened by
hovering the bottom edge, it also closes after the pointer leaves it.
Add future pages in `shell/bottom_model.lua` and register their builders in
each visual theme. Assistant, Drop and the workspace container have separate
Material and Tsugumori layouts.

**Lule** lives in Settings, under Theme. The wallpaper
gets 60% of the top row, with a narrower color pane beside it and a control
strip below; all color swatches and Apply stay visible. **Wallpaper folder**
shows the collection used by Images, Shuffle, the arrows, and Random & apply.
Edit that field and press **Use folder** (or Enter) to save a different folder;
`~/` paths work. This remembers `lule.folder` in the shell's `eva.json`
settings across restarts and monitors. Invalid folders leave the collection
unchanged. Initially it uses `LULE_W`, then the current wallpaper's folder.
This is the panel's collection setting; standalone Lule still uses its own
`lule.wallpaper` config / `LULE_W` environment setting.
Use Images, Shuffle or the arrows to preview an image.
The folder is rescanned when opening the tab or Images, shuffling, using the
arrows, or choosing Random & apply, so added and removed images are picked up
automatically. Use folder is only needed to change the collection's directory.
Choose dark/light and a palette method, then press
**Apply wallpaper & colors**. **Random & apply** chooses another image and
applies it immediately using the selected appearance and palette method.
Images and Shuffle remain preview actions.
The swatches show the currently applied ANSI palette and special colors;
click a swatch to copy its hex value. Open directly with `morf ipc call lule open`.
With no arguments, `morf ipc call lule`
still reports the terminal/accent diagnostics.

The tab runs `lule create --image=… --theme=… --palette=… -- set` through
`lib.integrations.lule.generate`, preserving Lule's config, templates and desktop hooks.
Current Lule uses `~/.config/lule/init.lua` (or `LULE_C`); a separate legacy
`lule_colors` script is not run a second time. The bundled tab icon is Lule's
original SVG geometry: outlined when inactive, filled with the accent when
selected. Its license is in `shell/assets/`.

Previews resize on an image worker only while the Lule page is visible.
They overwrite one small scratch JPEG per output and clear on closing;
opening the shell does not decode an entire wallpaper collection.

Quick settings opens with who is signed in. Lock acts at once; Log out, Suspend,
Restart and Power off count only once held, and letting go cancels. They run
`session.commands`; the full session drawer stays where it is.

A lit tile is something switched on, nothing else. Pressing a tile acts on it and
its chevron opens its page; a small tile has no chevron, so a long press does.
The pencil in the page's head edits the tiles: drag to rearrange, by mouse or
finger (Alt with the arrows from the keyboard), the minus badge hides a tile,
**Available** adds one back, the corner badge makes it a small icon-only tile,
two to a slot, and **Reset** restores the machine's defaults. Order and sizes are
kept per kind of machine, in `quick.tiles` and `quick.small` for `desk`, `tablet`
and `phone`. `morf ipc call quick edit` and `quick done` do the same.

A tile is offered only where the machine can back it. **Hotspot** needs a Wi-Fi
radio that can be an access point; NetworkManager keeps its password, and turning
Wi-Fi off stops it. **Rotation lock** needs an accelerometer through
iio-sensor-proxy: unlocked, the built-in screen follows it through Hyprland.
**Night light** needs `hyprsunset`, **Power saver** power-profiles-daemon and
**Flashlight** an LED under `/sys/class/leds` named `*:torch` or `*:flash`.
`EVA_FAKE_HARDWARE=1` stands in for all of them.

**Focus** groups Keep Awake, Ring Mode and Do Not Disturb, and each can also be a
tile of its own. Opening Focus leaves all three settings independent. **Tunnel** includes Tor's
Start/Stop control, bootstrap progress and SOCKS proxy address alongside VPNs;
its overview status includes Tor when running. The old `settings tor` IPC
shortcut opens Tunnel.

PrintScreen, the **Screenshot / Record** button in quick settings, or
`morf ipc call capture open` opens the compact bottom capture panel. Choose
region, window or screen, an optional delay, then Screenshot or Record.
The panel closes before capture. Recording uses its existing commands.
Screenshots freeze the desktop at its normal size: drag a region, click a
window, or press `S` (or Enter) for the current monitor. The screen target
already selects that monitor.

After selection, a compact floating editing menu appears beside the capture,
with Copy, Save, undo/redo, Draw and More. Draw expands the tool palette;
More includes Select again, Upload, Settings and Cancel. The toolbar can be
dragged. Handles appear after selection for resizing. Window snapping uses
Hyprland or Sway geometry, or the floating window geometry available from Niri.

The editor supplies select, rectangle, ellipse, line, arrow, pen, highlight,
text, numbered steps, blur, pixelate and zoom. Select moves annotations;
Delete removes the selected one. `F` switches rectangle/ellipse fill, the
wheel changes stroke/text size while drawing, and each tool remembers its
colour, width and fill across launches. `Ctrl+Z`/`Ctrl+Shift+Z` undo/redo;
`Ctrl+C`, `Ctrl+S` and `Ctrl+U` copy, save and request upload. Escape or
Cancel dismisses immediately; clicking outside the selected region also
closes the editor. The tool palette wraps on small screens. Both themes use their own controls and title animations.

Settings expose blur strength, pixel size, zoom factor, a custom hex colour,
save folder, an internal save/folder chooser, copy-on-save, save-on-copy,
pointer inclusion and key rebinding. Preferences live in `eva.json`;
defaults belong to `shell/config.lua`. Hyprland shortcut changes apply
immediately and are restored after reload. Set `capture.keybind_file` to a
dedicated include file if you want to write the generated binding there too.
The default compositor binding remains:

```lua
bind_exec("Print", "/usr/bin/morf ipc call capture open")
```

Upload requires a separate confirmation. It sends only the rendered image,
with metadata removed by re-encoding, to `capture.upload_endpoint` (default
Litterbox); the default link is public and expires after 72 hours. The URL
is copied to the clipboard. Nothing is uploaded automatically.

Acquisition uses Morf's native Wayland screencopy; KDE uses Spectacle.
Image composition/effects run on workers without ImageMagick. `wl-copy`
keeps the image clipboard alive after the shell exits; uploads use `curl`.
Live drawing uses native Path geometry; committed previews keep a decoded
monitor image and publish pixels directly, without a PNG round trip for each
edit. Lua owns tool selection, undo history and themed controls; Rust builds
and rasterizes the annotation geometry. Save/Copy still encode an export.
Temporary captures/previews are cleaned when editing ends, with bounded
undo and preview caches. There is no screenshot history or gallery.
`morf ipc call capture-editor cancel` closes editing across outputs;
`morf ipc call screenshot screen quick` retains the old command-based
capture. Set `capture.editor = false` to use that path by default.

Recording still uses the configured commands; custom recorders must stay in
the foreground (use `exec` in a wrapper) so Morf can track and stop them.
Quick capture/recording commands may use `grim`, `slurp`, `hyprctl`, `jq`
and `gpu-screen-recorder`. Reopen the popup to stop the recorder it started
or cancel a pending countdown.

Run `morf shell`, `morf lock`, or `morf greet`. Preview without authenticating
with `morf lock -- window preview` or `morf greet -- preview`.
See [system installation](https://github.com/paneworks/morf/blob/main/docs/INSTALL.md) for the full workflow.

The left panel has **Tasks** and **Calendar** tabs. Tasks uses the installed
`task` executable and the user's normal Taskwarrior configuration, including
`TASKRC` and `TASKDATA`. Its client is eva's `lib.integrations.taskwarrior`.
No second task database or sync service is created. Tasks refresh when the
panel opens, every ten seconds while open, and after a successful change.

Click a task to edit its description, project, priority, scheduled date and
time, deadline, waiting date, tags, recurrence, recurrence end, or dependencies.
Dates accept Taskwarrior expressions such as `tomorrow`, or an ISO date/time
such as `2026-10-01T09:00`. A repeating task needs a due date. Editing one
occurrence does not propagate changes to its siblings. The editor also
offers start/stop, completion, and deletion with a second click to confirm.

Calendar shows a month and tasks scheduled or due on the selected day, in
local time. “Plan a task” preselects that day. Work-mail meetings are not
connected yet; the calendar explicitly shows that state.

Performance and battery graphs collect the latest 60 samples while their
tabs are closed, except while a phone display is blanked. Old samples are
overwritten in memory; restarting the shell resets them. No history files
are written.
Reloading the configuration also starts a new history. CPU history spans
two minutes; memory and battery span three minutes. After a restart or
reload, the graphs fill from the right as samples arrive.

`morf ipc call dashboard-history` reports sampling counters and errors without
waking idle sources. Pass an output name (for example `dashboard-history DP-6`)
to inspect that monitor. The counters should increase with the drawer closed.

## The launcher

`Ctrl+Space`, or `eva launcher`. One box finds apps, Settings pages and the
controls inside them, quick tiles, open windows, files, recent files, bookmarks,
snippets, your scripts and the shell's own actions, ranked together, with no prefix.
Answers come inline as you type: `2^10`, `10ft in m`, `16px in rem`, `20% off 80`,
`255 in hex`, `100 usd in eur`, `time in tokyo`, `10am utc in oslo`, `days until
2027-01-01`. Files land when they land; the list and the highlight stay put.

| Prefix | Mode |
|---|---|
| `=` | the calculator |
| `$` | run a command, or a program from your PATH; `sudo` goes to a terminal |
| `/` `~` | files by name, or a path to browse: `/etc/`, `~/Doc` |
| `?` | the web; a bang picks the engine: `?gh`, `?yt`, `?aur`, `?nix` |
| `@` | open windows |
| `!` | the system, and the shell's panels |
| `:` | emoji, the last ones first |
| `;` | the clipboard, from eva-clipboard's store: `; img`, `; link`, `; pinned` |
| `#` | a colour in every notation |
| `>` | the shell's actions and every mode below |

A mode also answers to its word at the start of a plain search, next to whatever
else that search finds: `timer 12m pasta` starts from the same box as `> timer 12m
pasta`.

| Word | What it does |
|---|---|
| `task` | adds to and finds in Taskwarrior: `task buy milk due:friday +home` |
| `timer` `alarm` | `timer 12m pasta`, `alarm tomorrow 7:30 standup` |
| `note` | adds a line to `launcher.notes_file` |
| `agenda` | what is planned for a day |
| `tr` | translates: `tr es hello`, `tr french good morning`; `trans` if it is installed, else MyMemory |
| `define` `spell` `wiki` | a dictionary (`dict`, else dictionaryapi.dev), spelling (`aspell`, `hunspell`), a Wikipedia summary |
| `pw` | a password or a passphrase: `pw 24`, `pw 16 nosym`, `pw words 6`; shown as dots, copied with a password manager's mark |
| `uuid` `hash` `b64` `url` `case` `json` `jwt` `char` | encoders, digests and naming styles; `hash` takes a file's path too |
| `date` `time` `week` `duration` | `date next friday`, `date 1700000000`, `time 10am utc in jst`, `duration 55h` |
| `qr` | a QR code of any text, up to 400 bytes |
| `lorem` `roll` `rand` `kao` `gitmoji` `font` | placeholder text, dice, kaomoji, gitmoji, the installed fonts |
| `kill` `port` | ends a process of yours, or whatever listens on a port |
| `man` `unit` `keys` | manual pages, systemd units (start, stop, enable, logs), key bindings |
| `ssh` `tmux` | hosts from `~/.ssh/config` and `known_hosts`, terminal sessions |
| `nix` | searches nixpkgs; Return is `nix run` |
| `vault` | names from `pass` or `rbw`; the tool does the copying |
| `wifi` `bt` `vpn` `audio` `mic` | joins, connects, switches, through the Settings pages' own models |
| `vol` `bright` `media` | the volume, the brightness, what is playing |
| `window` `ws` | float, pin or move the window you are in, go to a workspace |
| `recent` `dir` `grep` `places` `project` `usb` | recent files, folders, words inside files, named folders, repositories, removable drives |
| `snip` | snippets: `snip add sig ;sig: Kind regards, {date}` |
| `mark` `link` | bookmarks from Firefox, Chromium and `launcher.bookmarks`; `launcher.quicklinks` |
| `game` | your Steam library |

`> ` lists them all, `> plugins` says what loaded, `> history` searches what you
picked, `> hidden` brings an app back, and `> alias add ff firefox` gives anything a
short word.

Keys: `Ctrl+1`..`9` and `Alt+1`..`9` pick a result. `Tab` completes what can be
completed (a mode from its first letters, a path, a bang) and otherwise lists the
result's actions, as do `Ctrl+K`, `F10`, a right click and a long press. `Up` in the
empty box walks back through past searches. `Space` once you have walked the list,
or `F1` any time, is quick look: a pane beside the list where there is room, over it
where there is not. `Ctrl+J` and `Ctrl+P` walk the list, `Ctrl+Tab` the modes,
`Ctrl+U` clears, `Ctrl+G` turns the grid on and off.

Every result has an action panel. An app's lists what its desktop file offers, then
pin to favourites, run as root through polkit, open containing folder, file it in a
folder, hide it, and uninstall for a Flatpak.

On a phone or a tablet the launcher opens as a grid: favourites, what you use most,
your folders, then every app, with chips for the categories and an alphabet down the
side. A long press lists a tile's actions. The on-screen keyboard waits until you
press the field. `launcher.layout` is `auto`, `grid` or `list`.

Settings live under `launcher` in the settings file, `launcher.sources` choosing what
a plain search reaches. Pages and tiles register themselves: anything added to
`settings_model.DETAILS` or `TOGGLES` is found as it stands, and
`lib/shell/launcher/search_index.lua` takes an entry from anywhere else.

`launcher apps` lists Flatpaks and the AppImages in `launcher.menus.appimages`.
`launcher web` lists browser history, bookmarks and search, and shows the pages of
the `bookmark` tool's files when they are in `launcher.menus.bookmarks`. A person
with their AppImages elsewhere and their own player sets, in the settings file:

```json
{ "launcher": { "menus": { "appimages": ["/env/app"], "player": ["~/.local/sbin/play"] } } }
```

`eva open launcher/timer` opens on a mode and `eva launcher query TEXT` with text
typed, for a key to bind. `eva launcher selection` opens on what is selected.
`printf 'a\nb\n' | eva dmenu -p Pick` is a menu for scripts: the choice on stdout,
exit 1 with none.

### Script commands

Every executable in `~/.config/eva/scripts` is a command that plain search finds.
Comments at its head describe it:

```sh
#!/bin/sh
# @eva.title Restart the audio
# @eva.description Brings PipeWire back
# @eva.icon restart_alt
# @eva.mode silent
systemctl --user restart pipewire
```

`@eva.mode` is `silent`, `terminal`, `copy` (what it prints goes to the clipboard) or
`notify`. `@eva.argument a name` asks for an argument first, `@eva.confirm true` wants
Return twice. The folder is watched.

### Plugins

A plugin is a Lua file that registers with the launcher and returns nothing. It runs
in the shell, as you, with everything the shell can do: put there only what you would
run yourself. Roots are searched in order, the folders of `EVA_PLUGIN_PATH` and then
`~/.config/eva`, and each is laid out the same way:

```
plugin/*.lua         run at start, by name
lua/*.lua            for require, never run by themselves
pack/*/start/*/      a package: a root of its own
after/plugin/*.lua   run last, to override the rest
```

```lua
-- ~/.config/eva/plugin/ip.lua
local launcher = require("eva.launcher")

launcher.mode {
  id = "ip", name = "Address", material = "public", words = { "ip" },
  hint = "ip  ·  this machine's addresses",
  search = function(term)
    local answer = launcher.ask("ip", "all", { "hostname", "-I" }, function(stdout) return stdout end)
    if not answer then return { launcher.note("ip", "Looking…", "", "public") } end
    local rows = {}
    for address in answer:gmatch("%S+") do
      rows[#rows + 1] = launcher.copy("ip:" .. address, address, "Return copies it", "public")
    end
    return rows
  end,
}
```

A mode's `search(term, query)` gives rows. A row is `{ name, description, material,
run, actions }`; `run` returns `"close"`, `"keep"`, or a new query for the box.

| Call | |
|---|---|
| `launcher.mode { id, name, material, shape, prefix, words, hint, search, bare, hidden }` | adds a mode, or replaces the one with that `id` |
| `launcher.entry { id, name, keywords, description, material, tag, run, actions }` | adds something plain search finds |
| `launcher.on.chosen(fn)` | `fn(row, query)` runs after a result is chosen |
| `launcher.row(t)`, `launcher.copy(id, name, description, material, value)`, `launcher.note(id, name, description, material)`, `launcher.file(path, folder)` | build rows |
| `launcher.fuzzy(list, term, key)` | filters a list as the box does |
| `launcher.ask(slot, question, argv, parse, options)` | runs a program without holding the search: nil until it answers, and the search runs again when it does |
| `launcher.start(argv)`, `launcher.open(target)`, `launcher.browse(url)`, `launcher.terminal(argv)`, `launcher.clip(text)`, `launcher.paste()` | do things; each that ends a row returns `"close"` |

One plugin raising is reported in `> plugins` and the rest still load. `EVA_NO_PLUGINS=1`
or `launcher.plugins` off starts without them, which answers whether a problem is a
plugin's.

## Phone, tablet and desk

Each output is classed from its logical size: compact below 600 wide, medium to
839, expanded from 840, with a height class to match. A touchscreen is the main
input while no real keyboard is attached and the output is the machine's own
panel, so a docked phone is a desk on its monitor and a phone on its panel.
Turning the screen or docking a keyboard rebuilds that output in place, and
what was open stays open.

A phone and a tablet have a status bar with the clock at the left and mobile,
Wi-Fi and battery at the right. Rare statuses, then Bluetooth, then VPN and Do
not disturb fold into a dot when the row runs out, then the percentage if the
battery is above 20%. Set `edgebar.corner` and `edgebar.cutout` for a screen's
rounded corners and cutout. Quick settings comes down from the top, under the
status on a tablet, and the dashboard rises from the bottom.

A desk's bar has the system tray, and optionally the wheel over the status for
volume and over the clock for the workspace (Eva, Bar). The tray serves a
StatusNotifier watcher only while the bar is up, so programs never register with
a tray nobody can see.

`EVA_FAKE_BATTERY=57,charging,saver`, `EVA_FAKE_STATUS=wifi,bluetooth,vpn,dnd`
and `EVA_FAKE_CUTOUT=400,68,34` stand in for hardware; a `tools/see/` scenario
exports them, as `tools/see/bar.steps` and `cutout.steps` do, and
`morf ipc call fake-battery 12` moves the battery while it runs.

## Visual themes (in progress)

The shell, lock and greeter select a visual package with
`EVA_STYLE=material` or `EVA_STYLE=tsugumori`. Without that override,
selection comes from `theme` in `$XDG_CONFIG_HOME/eva/appearance.json`
(or the file named by `EVA_APPEARANCE`); Material is the default.
The selection changes live. Wallpaper and Lule colors remain independent of it.

Both themes use the same content builders in `themes/layouts/`: sections,
control order, navigation and information grouping stay the same. Useful
section titles are shared additions too. Tsugumori supplies typography,
framed controls, subtle wallpaper-accent borders, title decoding, hover
feedback and covered transitions. Its approved edge pills remain a visual
override. Every tab has its icon at the right end, including Lule's custom SVG.

Shell services and authentication remain outside the visual components.
Preview mode disables task changes and real authentication actions. The
conversion and broad verification are still in progress; see
[THEMING.md](THEMING.md). Develop and review in the isolated sandbox before
installing.

## Checks

```sh
make test                                   # every spec, in parallel shards
sh tools/test.sh tests/panels_spec.lua      # some of them
MORF=path/to/morf sh tools/test.sh          # against another engine build
nix flake check                             # the package, the helpers and the NixOS module
python3 -m unittest discover -s nix/tests   # the NixOS module's screen and wallpaper helpers
lua tools/test-auth.lua                     # the greeter's login conversation
```

`tools/films/` records frame-by-frame films of the drawers and the motion,
`tools/keyring_test_ui.py` runs the keyring dialog against a real GCR
prompt, and `tools/sandbox/` holds the scenarios for morf's nested sandbox,
caelestia as a reference beside eva, and a phone-sized bench
([how to run them](tools/sandbox/README.md)); none of them runs in CI.

The specs stub external commands and never change the user's tasks or
record the desktop. eva's own library, `lib/` (Lule, Taskwarrior, the
modem, settings, capture and the rest), is tested by `tests/lib_*_spec.lua`.

Keyring prompts use morf when the optional `eva-keyring` helper is installed
on PATH. See [the bridge build and test instructions](helpers/keyring/README.md).
The bridge keeps GNOME Keyring as the secret store and displays unlock,
new-password and confirmation dialogs using the current theme. It starts on
the primary output, waits for existing GNOME prompts to finish, and leaves
GNOME's original prompter available when the shell is stopped. Inspect its
status with `morf ipc call keyring`.

The **Shell theme** controls at the bottom of Lule switch between Material and
Tsugumori without restarting the process. Open drawers use a feathered wipe while
the frame stays visible and its corners and seams morph between styles. Restored
cards start settled so their entrance animations do not compete with the reveal.
Font-only changes use a dissolve. The selected theme is saved in
`$XDG_CONFIG_HOME/eva/appearance.json` (`EVA_APPEARANCE` overrides
that path); `EVA_STYLE` remains a startup override for previews.

The switch retains open drawers, selected tabs, Taskwarrior editor drafts,
Lule selections, notification history, and bounded performance/battery samples
in memory. These snapshots are released after the switch and never written to
disk. Finish an active authentication prompt, capture, task operation, or Lule
apply before switching. IPC also supports `morf ipc call appearance material`
and `morf ipc call appearance tsugumori`; calling `appearance` alone reports the
current theme and transition status.

The adjacent **Font** picker searches installed font families and previews each
face. Choose **Theme default** to restore Material or Tsugumori's own typeface.
The shell font is saved as `font` in the same appearance file, stays selected
when changing themes, and uses the same smooth, state-preserving transition.
Icons retain their symbol font. Installed families are scanned with `fc-list`
when opening the picker, then cached until the next shell reload. IPC accepts
`morf ipc call appearance 'font:Goku'`; `font:` resets the font choice.

Lock controls follow the pointer's output. Each output uses its own logical
dimensions, including space for the on-screen keyboard;
other outputs show the clock and background. The lock has one private password
draft across all outputs. The greeter stays on its compositor's main display
with one private draft and one authentication conversation.
Both views rebuild their presentation after a resize or rotation while retaining
controller state. Small outputs keep readable controls and scroll the sheet.
Replacing a keyboard cancels held keys and
pending repeats. Short greeter outputs reserve a footer for power controls.
The lock's live monitor list drops disconnected displays, so its controls move
to a remaining output and recover when a display reconnects.

## On-screen displays

A change made anywhere (a key, another program) shows as a display on the focused
output: volume and brightness as a meter, and short pills for the microphone's
mute, caps and num lock, the keyboard layout, the power profile, Do not disturb,
keep awake, night light, the ring mode, a Bluetooth device connecting, headphones,
and the track now playing. Each fires only on a real change, stays quiet while
services report in at startup, and never appears when its service is absent.

**Settings > Eva > On-screen displays** gives each kind its own place, one of
`top_left`, `top_center`, `top_right`, `center_left`, `center`, `center_right`,
`bottom_left`, `bottom_center` and `bottom_right`, with a switch, a hold time, a
percentage switch for the levels, and a **Try** button. They are kept under
`osd.kinds` in the settings; a phone's default is the top centre.

At an edge a display swells out of the frame with its seam, lying along the top
and bottom edges and standing upright on the sides; in the centre it floats with
a shadow. Moved while on show it travels there. Displays at different places show
together, up to three, and one in another's way takes over its bud.

A level can be dragged to set it and clicked to mute, with a mouse or a finger,
and waits while the pointer rests on it. `morf ipc call osd` flashes the volume,
and `morf ipc call osd KIND` any of `volume`, `brightness`, `mic`, `caps`, `num`,
`layout`, `profile`, `dnd`, `awake`, `night`, `ring`, `bluetooth`, `headphones` and
`media`; it answers false when that display cannot appear.

A track waits a moment for its cover and shows once, whatever metadata its player
repeats. Caps and num lock are read from the kernel's LEDs, on the focused output
only, three times a second. Night light shows once a service provides it: a
`night` control in `settings_model.CONTROLS`, or `services.night`, with `on()`.

Notification popups stand at any of the six top and bottom anchors, set on the
same page as `osd.notifications`. Along an edge they move as the setting changes;
to the other edge the output's shell is built again in place, which drops the
popups on show at that moment. A card goes when swiped sideways or away from its
edge, and springs back from a short pull.

Headphones connecting show for 3.2 seconds, in the centre by default. Earbuds get a
separate icon when the name or form-factor metadata identifies them; generic analog
jacks use headphones because they cannot distinguish the physical accessory. One
`pactl subscribe` watcher reads audio-route changes, including wired jack
availability, without idle polling. Native audio metadata is the fallback when
PulseAudio compatibility is unavailable. Devices present at startup, volume changes
and brief Bluetooth profile handoffs stay quiet. Preview with
`morf ipc call headphones-demo` or `morf ipc call headphones-demo earbuds`.

The greeter uses one fullscreen surface on its Hyprland's main display. The
view uses the size that surface is configured to and never follows the pointer
or rebuilds in response to monitor metadata. Locking remains independent.

## Sound and nested settings

Sound opens **Equalizer**, which opens a deeper **Audiogram** editor. Back
returns to the parent page. Other settings can use the same hierarchy:
add a descriptor with `key`, `name`, and `parent` to `settings_model.DETAILS`
and a builder in `utilities.lua`. Breadcrumbs and presentation scopes follow
the registry. `morf ipc call settings sound/equalizer` opens the EQ directly.

The EQ provides eight tone bands, Auto/Headphones/Speakers modes, separate
per-mode strength, channel separation and output trim. Audiogram compensation
starts disabled with zero thresholds; enter existing measured dB HL values in
the editor and save them to use it. The prescription is inspired by
[omarchy-audiogram-eq](https://github.com/Fail-Safe/omarchy-audiogram-eq).
Native Rust computes gains, filter responses and estimated headroom, including
overlapping bands. Automatic attenuation is not a limiter.

PipeWire and WirePlumber 0.5+ are required for processing. One primary runtime
owns a standalone filter-chain client, managed by WirePlumber's smart-filter
policy. It follows the default output without changing that default or restarting
audio services. Controls update in one debounced batch. Disabling removes the
filter; hidden panels keep processing while enabled and do not poll. Internal
filter nodes are excluded from Sound's device and app controls. Configuration
is kept in two bounded files under Morf's state directory:
`eva-equalizer.json` and `equalizer-runtime.conf`, both overwritten.
