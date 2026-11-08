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
`programs.eva`: `uiScale`, `idle.*`, `lock.settings`, `phone.*`,
`hyprland.extraConfig`, `greeter.*`, `seamless.*`, `wallpaperLogo` and
`usePackagedShell`.

Idle lives in Settings, on the Idle and sleep page under Device, and runs in the
shell. By default the screen turns off and locks after 10 minutes.
An `idle.*` timeout set in Nix wins over that page, which then shows it as set,
and stays a timer of hypridle's, which runs without the shell. With no lock timeout
set in Nix, hypridle keeps one backstop at 15 minutes: it asks the shell, and locks
only if nothing answers, so a dead shell does not leave the session open. `lock.settings`
does the same for the Lock screen page: it is written to `/etc/eva/lock.json`,
with the keys of `models/lock_defaults.lua`, and anything left out stays the
person's.

`seamless.enable`, on by default, hides the way from the greeter to the desktop.
Two compositors cannot share a frame, so greetd's switch between them always has a
gap; this makes the gap the wallpaper's colour rather than black and text. One
moment stays black: each Hyprland shows a cleared buffer from its first commit
until its first rendered frame, and no configuration reaches that.

- Boot messages stay on screen until the greeter clears tty1. tty1 has no getty
  and no cursor from then on, and greetd stays on it.
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
not.

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

### Touch gestures

On any machine with a touchscreen, whatever form it takes, gestures work
anywhere on the screen: two fingers down from the top edge open the launcher, two
up from the bottom edge bring the keyboard and leave the launcher open,
three fingers change workspace, open the overview or show the desktop, four open
the app grid or switch apps, and a five-finger pinch opens the launcher. Settings,
Touch gestures, lists them, chooses what each does per form, and has a small
screen to try them on. One finger from an edge still pulls the panels, and two
fingers in the middle of the screen stay a scroll in the app.

Wayland sends a touch to the surface under it, so a shell cannot hear the rest of
the screen. eva reads the touchscreen beside the compositor instead, by running
`libinput debug-events` on it, and apps keep every touch: nothing is grabbed, so
an app under a global gesture sees those fingers too. The reader stops, process
and all, while the session is locked and while a password prompt or the capture
editor is on screen. With no touchscreen, or no libinput, nothing runs.

On NixOS `programs.eva.touch.enable` is on by default and adds libinput and a
udev rule that gives the logged-in user the touchscreens and nothing else.
`touch.virtualPointer`, on by default except on a phone, keeps a mouse that never
moves attached: Hyprland sends a pen to the pointer's surface and has none
without a mouse, so a pen would move the cursor and reach no app.
Elsewhere, install libinput (`libinput-tools` on Debian and Ubuntu) and add the
rule as `/etc/udev/rules.d/70-eva-touch.rules`:

```
SUBSYSTEM=="input", ENV{ID_INPUT_TOUCHSCREEN}=="1", TAG+="uaccess"
```

The number matters: the tag must be set before `73-seat-late.rules` acts on it.
Then run `sudo udevadm control --reload && sudo udevadm trigger -s input` and log
in again. Do not join the `input` group instead: it can read every keystroke.
`getfacl /dev/input/eventN` on the touchscreen should list your user, and
Settings says what it found.

The gestures find the built-in panel, follow its rotation and scale, and run on
the shell of that screen alone. On a machine with no built-in panel and several
screens, Settings asks which one has the touchscreen. With a second monitor eva
also binds `input:touchdevice:output` to the panel, or Hyprland would send
touches to whichever monitor has the focus. A screen turned by hand needs
`input:touchdevice:transform` set to the monitor's transform for apps to agree,
as auto-rotate does.

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

Quick controls stay in the right panel; heavier work is a tool of `apps/`, and
every tool is a page of the **Tools** window. It is the same window as Settings,
drawn by the shell on a book of its own: on a desk it stands in the middle, seven
tenths of the screen, and every screen dims; on a phone it fills the screen. Only
one of the two is open at a time. Escape, a press on any dimmed screen and its
close control shut it. It comes and goes in the theme's own motion, lands at
once under Reduce motion, and is open again on its page after the shell is built
again in place. On a desk the left column has the search, the categories (Time,
Text, Screen, System, Calls and texts) and their tools; on a phone it is one page
at a time, Back going up to All tools.

The app menu holds two of eva's entries, **Settings** and **Tools**. Typing a
tool's name, something it holds or a word for it into the launcher finds the tool
and opens its page. `eva open tools`, `eva open tools/NAME`, `eva open NAME` and
`morf ipc call tools NAME` open the window too (`tools home` is All tools, `tools
close` shuts it and `tools state` says where it stands); `morf ipc call tool NAME
VERB` is a verb of a tool's page, and `morf ipc call tools-search WORDS` searches.
The quick tiles, the bar's modules, a text's notification and `tel:` and `sms:`
links lead to the same pages.

Each `eva-NAME` alone opens Tools on its page; with words it does what it always
did on a command line, a job or a watcher with or without the shell. A tool that
draws over the whole screen keeps a program of its own: its page holds what it
starts with and a control that starts it, which shuts the window first, and with
no shell running its command alone draws as it did. A page's tool otherwise needs
the shell, as Settings does. On NixOS the commands are on `PATH`.

| Command | Page | Words |
|---------|------|-------|
| `eva VERB`, `eva open settings/power`, `eva open tools/clock`, `eva commands --json` | | the shell from a command line, the front door for keybindings |
| `eva-clock` | Clock: alarms, timers, a stopwatch and world clocks, said in plain words | `timer 12 min pasta`, `at 6pm`, `every weekday 7:30 gym`, `list\|cancel\|snooze\|sync`; each alarm is a systemd user timer, so it rings with no shell running, through the notifications server with sound, Stop and Snooze |
| `eva-pomodoro` | Pomodoro: a focus timer whose phases ring through the clock's store and hold do not disturb | `start\|pause\|skip\|reset\|status` |
| `eva-clipboard` | Clipboard: a history of text and pictures with pins, skipping what a password manager marks | `--watch` keeps the history; on NixOS it runs as a user service |
| `eva-text` | Text: a developer's scratchpad: case, lines, encodings, JSON, hashes, UUIDs, passwords, placeholder text | `TRANSFORM < FILE`, `list` |
| `eva-translate` | Translate: free translation, offline with Argos where it is set up, else `trans` or MyMemory; text leaves the machine only on a press, and the page says when an online engine is in use | `[-s LANG] [-t LANG] [-e ENGINE] TEXT\|-\|--clipboard\|--selection` |
| `eva-qr` | QR code: from text or a Wi-Fi network, copied, saved, or alone over the page for a camera | `TEXT\|-`, `wifi SSID` open the page on them, a Wi-Fi password never reaching a command line; `--png FILE TEXT` writes a file |
| `eva-large` | Large Type: words huge across the screen, with a QR beside them | `WORDS`, stdin, `--clipboard`; from a key, with no terminal, the clipboard |
| `eva-screenshot` | Screenshot: a region, a window or the screen, then edit, copy, save or pin, at once or after a delay; Record; the capture panel | `panel`, `region\|window\|screen [--edit\|--copy\|--save\|--pin] [--delay N] [--last]`, `ocr\|qr`, `scroll`, `--edit-file FILE`, `--pin-file FILE`, `--text FILE`, with or without the shell |
| `eva-record` | Screenshot | `region\|window\|monitor [--audio KIND] [--fps N]`, `stop`, `pause\|resume`, `replay [--seconds N]`, `save`, `status`: the capture tool's recorder; with no shell a pill shows it running and stops it |
| `eva-colorpick` | Colour picker: hex, rgb, hsl and oklch, the recent colours, a pick | `--pick`: the frozen screen with a magnifier, one click copies |
| `eva-draw` | Draw on screen: the keys it takes | `start`: draw and write over the screen |
| `eva-ruler` | Screen ruler: what it measures | `spacing\|horizontal\|vertical\|bounds`: edge detection, a dragged box, a click copies |
| `eva-zoom` | Zoom: the factor on a slider for touch, Hyprland's cursor zoom or the lens's | `in\|out\|reset\|N\|get`, `lens`: a lens over the frozen screen |
| `eva-find` | Find pointer: how it shows | `--spotlight\|--crosshairs\|--ripple` |
| `eva-monitor` | Monitor: processes with search, sort and kill, per-core load, memory, GPU, disks, network and sensors | |
| `eva-logs` | Logs: the journal, live, by priority, boot, unit and words | `UNIT` opens the page on it |
| `eva-disk` | Disk usage: what takes the room under a folder, as a treemap | `FOLDER` opens the page on it |
| `eva-kill` | End a window: press one to end it, the shell's kill mode | `--pick` presses one at once, `--active` ends the focused one |
| `eva-webapp` | Web apps: a site as an app with its own desktop entry and icon | `add NAME URL [--icon FILE]\|list\|remove NAME` |
| `eva-phone` | Phone: a dial pad that finds people by their letters, recent calls and contacts; the shell shows the call | `tel:NUMBER` types it; `import\|export FILE` carries vCards |
| `eva-messages` | Messages: text threads with delivery marks; the shell receives them and notifies | `sms:NUMBER` opens the thread |
| `eva-nightlight on\|off\|toggle\|status\|temperature\|follow\|times\|auto\|daemon` | | the quick settings' night light from a command line, one implementation with one state; `follow on` has the shell turn it on and off by the sun at `services.weather_location` |
| `eva-battery status`, `eva-battery limit on\|off\|NN` | | what feeds the battery and how fast, and the charge limit: UPower's `EnableChargeThreshold`, or a level in the kernel's own threshold file |
| `eva-standby [--when-charging] [--night]` | | the shell's StandBy on demand, on any form: a second call closes it |

A tool's page is built the first time it opens and let go a second after the
window shuts, and what it reads (samples, the journal, a scan) runs only while it
is on show; nothing of a tool loads at shell start. `shell/tools_registry.lua` is
the one list of pages, a tool's page is `page.lua` in its folder, and the window is
`shell/tools_window.lua` over the theme's `page_window` view, the same host as
Settings (`shell/window_host.lua`). `make app draw` runs a tool's own program from
a checkout.

The desktop entries left beside Settings and Tools are hidden (`NoDisplay=true`)
and kept for what needs them: `tel:` for Phone, `sms:` for Messages and folders
for Disk usage. Web apps made with the Web apps page are a person's own and stay
in the menu.

Some commands are Settings pages rather than tools. Alone each opens the
Settings window on its page; its words work with or without the shell, as a job
on the page's own code (`apps/common/job`, or the tool's own program).

| Command | Page | Words |
|---------|------|-------|
| `eva-displays [--auto]` | Displays: a canvas to arrange monitors with edge snapping; mode, scale, rotation, VRR and mirroring; a countdown that reverts; profiles matched on make, model and serial | `--auto` applies the profile saved for what is connected, as hotplug does |
| `eva-audio [next [input]\|list]` | Sound and Microphone: apps, recording, routing, channels, equalizer, the server's restart | `next` makes the next output the default, `next input` the next input |
| `eva-fonts [list [--mono]\|current\|set NAME\|reset]` | Fonts, under Theme: browse and preview the installed fonts | sets the shell's font, saved for the next start with no shell |
| `eva-startup [list\|enable NAME\|disable NAME\|remove NAME\|timers]` | Startup apps: the session's autostart, a command of your own, the scheduled jobs | the same, from a command line |
| `eva-update [--check]` | Updates: flake input ages, package counts and a rebuild with its live log; `update.flake` names the flake | `--check` counts what waits |
| `eva-info [--text\|--json\|--copy]` | About: hardware, Nix generation, USB, session | every fact as words, as JSON, or on the clipboard |
| `eva-awake [30m\|on\|off\|status\|--pid N]` | Focus: keep awake for a time, on the shell's own inhibitor | for a time, until told otherwise, or while a process runs |
| `eva-keys` | Keyboard shortcuts, under Keyboard: the live bindings and the shell's own as one searchable list, a new chord for any row | |
| `eva-breaks [--watch\|status\|pause MINUTES\|resume]` | Breaks: reminders that count idle time as rest, and the day | `--watch` keeps the count; on NixOS it runs as a user service |

Alarms and timers live in `$XDG_STATE_HOME/eva/clock/alarms.json`, written by
`lib/services/alarm.lua`, which is also `services.alarm` in the shell: `armed()`
lights the bar's alarm indicator and `ongoing`, a signal, is the running timers
for its status pill. On NixOS `eva-clock-sync` puts them back on systemd after a
login, ringing what came due within the hour and reporting the rest as missed.
Without a user systemd the shell keeps the time instead. A timer does not wake a
suspended machine: a user timer cannot.

The clipboard's store is an interface other code may read,
`$XDG_STATE_HOME/eva/clipboard/history.json`: a JSON array, pinned entries first
and then newest first, mode 600, replaced atomically. An entry has `id`, `kind`
(`text` or `image`), `text`, or `path` and `mime` for a picture, `time` in unix
milliseconds, and `pinned`. Fields are only ever added. The head of
`apps/clipboard/model.lua` has the whole contract and `tests/clipboard_spec.lua`
holds it.

The Displays page writes what you keep to `$XDG_STATE_HOME/eva/displays/`. eva's
Hyprland session loads `monitors.lua` from there; on sway, add
`include $XDG_STATE_HOME/eva/displays/outputs.sway` to your configuration.

A tool's folder holds its `page.lua` (its page in Tools or Settings), its
`model.lua` and `view.lua`, its command `cli`, `app.lua` where it still runs as a
program of its own (a job, a watcher, an overlay), and three links: `lua ->
../../shell`, which is how that program reaches `theme`, `kit`, `palette` and
`config`, `common -> ../common`, and `fonts -> ../../shell/fonts`. The shell
reaches a tool's code through `shell/apps -> ../apps`, as `apps.clock.view`, and
the tool's program by the same names. `apps/launch` finds the shell's appearance
and settings files, which the shell names in `$XDG_STATE_HOME/eva/settings-path`.

`apps/common/controls.lua` is what a page is built from, `common/sys.lua` the one
door to the machine, honouring `EVA_DRY_RUN`, `common/overlay_page.lua` the page
of a tool that draws over the whole screen, and `common/freeze.lua` the screen
held still for a tool that reads its pixels. `common/frame.lua` is what a tool's
own program draws with: `frame.overlay` for the whole screen and `frame.quiet` for
no surface at all. `common/job` runs the shell's own code for a command line with
no shell running, so a tool and the shell share one module
(`lib/services/nightlight.lua`, `charge_limit.lua`, `alarm.lua`) rather than
having two.

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
Open a page directly with `morf ipc call page drop`, wherever a panel holds it.
Click outside the workspace to close it from either tab. When opened by
hovering the bottom edge, it also closes after the pointer leaves it.
Add future pages in `shell/bottom_model.lua` and register their builders in
each visual theme. Assistant, Drop and the workspace container have separate
Material and Tsugumori layouts.

**Assistant** is a chat with an OpenAI-compatible service, Anthropic or a local
Ollama, chosen under Settings, Eva, Assistant. Replies stream with markup and
code blocks; conversations are kept as JSON under the state folder (private ones
are not), and can be copied, stopped and regenerated. Attach the clipboard, a
screenshot through `eva-screenshot`, or the focused window's title. Keys live in
the Secret Service, given to `secret-tool` on stdin and to `curl` the same way:
never on a command line, in a signal, in a log or in `eva.json`. Type
`ai <question>` in the launcher, or `morf ipc call ask "<question>"`.

**Drop** is [termworks/drop](https://github.com/termworks/drop) through its
command line: this machine, people and their machines, who answers, what they
offer, what is nearby, topics, shared folders, chat, and files sent by dropping
them on the page or choosing them. Every `drop` command makes this machine's key
on its first run, listing ones included, so a machine that has never run it runs
nothing until **Set up Drop** is pressed. The page says when `drop serve` is not
running, and starts it on a press.

**Phone** is KDE Connect through `kdeconnect-cli`: battery, find, ping, clipboard,
files and the phone's notifications. **Notes** are plain files in `notes.folder`
(`~/Notes`), saved as you stop typing; `note <text>` in the launcher adds a line
to the quick notes. Neither page is in a panel by default: their tiles open them
in the Settings window, and Settings, Eva, Panels moves one into a panel.

**Calendar** adds to Taskwarrior what `calendar.files`, `calendar.folders` and
`calendar.urls` name, and what vdirsyncer and khal keep, found by themselves:
month marks, an agenda with the forecast, the next meeting and a Join button
where an event holds a meeting link. Reminders arrive as notifications at an
event's own alarm, or `calendar.lead` minutes before.

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
kept per kind of machine, in `quick.tiles` and `quick.small` for `desk` and
`phone`. `morf ipc call quick edit` and `quick done` do the same.

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

The capture tool is `eva-screenshot`, a process of its own in `apps/screenshot`,
in the way `eva-keyring` is one: the shell keeps it ready and asks it to run, and
it works the same with no shell. Its panel, frozen selection, editor and recorder
are the only ones there are. It stands on every screen as the shell does, so what
opens opens on the focused monitor, on a socket of its own
(`morf -i DISPLAY-screenshot ipc call`). The shell's `capture`, `screenshot`,
`record`, `capture-editor` and `capture-claim` verbs pass through to it, and it
publishes its state in `$XDG_RUNTIME_DIR/eva/capture-DISPLAY.json`, which is how the record
tile stays lit. Kept ready it costs a second morf process and its GPU context,
which is what opens the panel at once instead of after a second or two.

PrintScreen, the **Screenshot / Record** button in quick settings, or
`morf ipc call capture open` opens the compact bottom capture panel. Over the
shell the panel joins the screen's frame; with no shell it flares into the edge
of the screen. Choose region, window or screen, an optional delay, then
Screenshot or Record. The panel closes before capture.
Screenshots freeze the desktop at its normal size: drag a region, click a
window, or press `S` (or Enter) for the current monitor. The screen target
already selects that monitor. A region for a recording is chosen the same way.

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
The default compositor binding remains, and bind `eva-screenshot` itself for a
session with no shell:

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
undo and preview caches.
`morf ipc call capture-editor cancel` closes editing across outputs;
`morf ipc call screenshot screen quick` goes straight through the selection
and saves, the editor left out. Set `capture.editor = false` to do that by
default.

Recording runs `capture.commands.record_region`, `record_window`,
`record_portal` and `record_screen`, which default to `gpu-screen-recorder`;
`$REGION`, `$OUTPUT`, `$FPS` and `$FILE` are filled in. Custom recorders must
stay in the foreground (use `exec` in a wrapper) so Morf can track and stop
them. Reopen the popup to stop the recorder it started or cancel a pending
countdown.

After a shot is saved or copied a small thumbnail floats in the corner: press
it to edit, press its pin to keep it, or leave it to fade after
`capture.thumbnail_seconds`. `capture.thumbnail` turns it off, in Settings and in
the editor's preferences.

The clock at the panel's title opens the history: what the capture folder holds,
newest first, searched by name and by date (`today`, `2026-11-01`, `november`).
Choose a row to edit, copy, read, pin or delete it; a second press on a row opens
it, and a delete asks twice. It reads the folder each time and keeps no store of
its own. Its small pictures are scratch, gone when it shuts.

A pin keeps a picture over the windows on a surface of its own, from the editor's
More, the thumbnail, the history or `eva-screenshot --pin-file FILE`. Drag it to
move it; a press closes it. Pins come back after a reload.

Text is read with `tesseract`, on this machine, from the history's Text or
`eva-screenshot --text FILE`. Search narrows the lines and Copy text takes what
is shown. What was read is kept beside no picture, in
`$XDG_STATE_HOME/eva/capture/text`, and goes when the shot is deleted, so a search
of the history finds it; Read N more reads the rest. Where `tesseract` is missing
each of these says so.

While a recording runs, the panel's Pause holds it and Resume takes it up, by the
recorder's own `SIGUSR2`. Only `gpu-screen-recorder` is offered a pause: the
signal would end most other programs. The arrow at the panel's title keeps the
last `capture.replay_seconds` of the screen by `capture.commands.record_replay`:
Save replay writes them to the capture folder and the buffer runs on, Stop ends it
with nothing saved. `eva-record pause|resume|replay|save` do the same.

A recording opened from the history or by `--edit-file` shows its timeline: drag
the two edges, then Save trim or Save GIF. Each writes a new file and leaves the
original. They run `capture.commands.trim` and `capture.commands.gif` (`ffmpeg` by
default, with `capture.gif_fps` and `capture.gif_width`), and say so when `ffmpeg`
is missing.

The arrows at the panel's title take a long picture of the chosen target as it
scrolls. Frames are taken while you scroll, or while Auto presses Page Down until
the page ends; on a phone you scroll by hand. Done joins them into a picture in
the capture folder. Rows that stand still count as a header and a footer, and
appear once. A frame that cannot be lined up ends the capture with what is sound,
and says so; nothing is guessed. Expect it to stop on pages that move as they
scroll: video, or animation over most of the window, and on outputs scaled by a
fraction, where a row does not come back pixel for pixel. A floating button low in
the window lands in the picture at each strip.

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

Calendar shows a month with the selected day's tasks and events, in local
time. “Task” and “Event” preselect that day, and `eva event` or `morf ipc call
event` open the same form from a key. An event goes in the file it came from:
a line of a `.ics` file, or a file of its own in a vdir folder. Pressing one
opens it to change or delete, with all-day, repeat and reminder; a repeating
one asks whether that means this one or all of them. eva changes only the
fields on the form, so a server's attendees and its own properties stay in the
file. An event with no calendar to go in makes one, Personal, on this machine.

What cannot be written shows the event and says why: an ICS address, a file
without write permission, one your Nix configuration links in, and a folder
khal or vdirsyncer marks read-only. An edit to a synced folder reaches the
server at the next `vdirsyncer sync`; eva does not run it. Replying to an
invitation, moving an event between calendars and changing “this and later”
of a repeating event are not offered. A rule the form cannot say, such as every
second Monday, stays as it is unless another is picked.

An app set to “In the summary” (its page in Settings, under Notifications) makes
no sound and no popup. What it sends waits in the history until a time in
`notifications.digest_times`, 08:00 and 18:00 by default, unless it is critical.
Then one notice says how many, and a card heads the history: conversations
first, one row to a person, then each app with its last line. Pressing a row
runs the sender's own action, or opens its group. Done puts the card away and
keeps them in the history; Clear them can be undone. “Show now”, or `eva
notifications digest`, gives it early.
A time slept through comes on waking, once; a Focus holds it until it ends.
Nothing of the summary's content reaches its file, and a hidden preview stays
hidden on the card.

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

## Wallpaper

The wallpaper is a picture or Lule's: first found, `EVA_WALLPAPER`, the picture
Lule last made its colours from, `wallpaper.path`, or the path the eva tools keep
in `~/.local/state/eva/wallpaper/path.txt`. Lule's page under **Settings, Theme**
chooses it.

`wallpaper.draw` says who paints. Off, your wallpaper tool does. On, Eva paints a
background layer of its own from the start.

## StandBy

A phone on charge, turned sideways, becomes a bedside screen with a great clock, the folder's pictures, two stacks of widgets, the
cities of `eva-clock` or the next thing to ring, the screen awake while it shows.
A swipe turns the view and a touch shows the way out. At night it is a dim red,
and it drifts so nothing burns in. **Settings, Eva** has its switch.
`morf ipc call standby [on|off|toggle|VIEW]`.

## Look

**Settings, Theme** has a **Dark mode** switch and **Lule**. The colours come from
Lule, and until the switch is touched the mode is the one Lule made. The choice
lives with the theme in `appearance.json`, so the lock and the greeter follow it
too.

`appearance.sync` pushes the mode to `gsettings`, to GTK 3 and 4's `settings.ini`
and to qt5ct and qt6ct, and to the terminals through Lule; `appearance.cursor_theme`,
`cursor_size`, `icon_theme` and `gtk_theme` go the same way. Off, nothing outside
the shell is touched. `appearance.density` moves every space one step along the
4 px grid, `appearance.corners` scales the rounding, and `appearance.font_file`
sets one file for every label. How things move (the Eva page) and the density and
corners also live in `appearance.json`, so the lock, the greeter and the tools take
them, and Reduce motion lands everything in all of them. The desktop's own `reduced_motion` setting counts too. The Eva page
also sets how quick everything is, how far surfaces deform as they move, from
rigid to liquid, and the **Island**: a pill grown out of the top of the frame that
shows the music or the time, opens on a press and walks its faces on a right
press (`morf ipc call island [on|off|toggle|next]`).

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
| `note` | adds a line to the quick notes of the Notes page, in `notes.folder` |
| `ai` | asks the assistant: `ai what is a monad`; with a provider set, any search can end there too |
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

On a phone the launcher opens as a grid: favourites, what you use most,
your folders, then every app, with chips for the categories and an alphabet down the
side. A long press lists a tile's actions. The on-screen keyboard waits until you
press the field. `launcher.layout` is `auto`, `grid` or `list`.

Settings live under `launcher` in the settings file, `launcher.sources` choosing what
a plain search reaches. Pages and tiles register themselves: anything added to
`settings_model.DETAILS` or `TOGGLES` is found as it stands, and
`lib/shell/launcher/search_index.lua` takes an entry from anywhere else.

`launcher apps` lists Flatpaks; Tab moves to the AppImages in
`launcher.menus.appimages` (`/env/app` unless set) and back. Each AppImage shows
the icon it carries, read once with `unsquashfs` (squashfs-tools) without running
it and kept in the cache; without `unsquashfs` it keeps a plain glyph.
`launcher web` lists browser history, bookmarks and search, and shows the pages of
the `bookmark` tool's files when they are in `launcher.menus.bookmarks`. A person
with their AppImages elsewhere and their own player sets, in the settings file:

```json
{ "launcher": { "menus": { "appimages": ["~/Applications"], "player": ["~/.local/sbin/play"] } } }
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

## Windows

Everything between a person and their open windows goes through
`shell/windows_model.lua`, which reads the compositor's lists and sends it
commands, and `shell/window_shots.lua`, which keeps a picture of each window.

| Verb | What it does |
|------|--------------|
| `overview [open\|close\|toggle\|state\|app]` | every workspace along the top with a map of its windows, and the windows of the one looked at spread out beneath, each flying out of where it really is; typing filters across all of them, a card dragged onto a desk or a scratchpad goes there, the middle button closes, the right one offers more. On a phone a row of cards, swiped along and thrown away |
| `switcher next\|prev\|same\|commit\|cancel` | Alt+Tab: a quick tap flips to the last window, held it shows them by application |
| `snap CELL`, `snap layout KEY`, `snap picker` | a window into a half, a quarter or a third, or a whole workspace into a layout; a snapped window offers the others for the room left. `snap drag` and `snap drop` come from the drag's button |
| `workspace_name`, `workspace_layout`, `workspace_empty` | a name kept across sessions; dwindle, master, scrolling or monocle, one workspace at a time |
| `scratchpad NAME\|list`, `scratchpad send NAME` | Hyprland's special workspaces, started from `windows.scratchpads` |
| `pip`, `float`, `split`, `keep_above`, `opacity`, `show_desktop`, `kill_mode` | what happens to the focused window, or the one pressed |
| `corner NAME ACTION GUARD` | a hot corner's action, and the key that must be held |

Under a finger, a pull up from the bottom that stops and holds is recents, and a
quick one is still the dashboard. A phone's bottom edge walks the apps
(`windows.scrub`). A pull in from the left of a settings page goes back, with the
page it goes back to in view.

The compositor keys are in `shell/keybinds.lua`. A session with no
`~/.config/hypr/hyprland.lua` gets them; `programs.eva.hyprland.binds` is `auto`,
`always` or `never`, and Settings' Keyboard shortcuts (`eva-keys`) lists the ones
that are not bound with the verb to bind.

The same page also changes them: press a row and press the new keys. Hyprland's
own bindings stand aside while it listens, so a chord already taken still reaches
the page; it then says what has it, and waits to be confirmed. New chords live in
`keys.overrides` and go through the same run-time path as every other pushed
setting, now and after each reload, so no file of yours is written. A key from
your own configuration moves with its action intact, and Reset takes a row back.
The shell's Ctrl shortcuts are listed, not changed. Modifier order does not matter
when eva finds a key, but `hl.unbind` goes by text, so an alias such as `MOD4`
written in your configuration is not found.

Settings, Windows, Window rules holds what windows open with: float, size, place,
workspace, screen, opacity and the rest, started from nothing or from a running
window (or the window menu's Rule). A rule acts as a window opens; what it says on
looks reaches those already open. They need a Lua-configured Hyprland, and are
spelled as Hyprland 0.55.4 reads them. The same page dims inactive windows.

Saved layouts keeps what is open under a name and puts it back, on request or
after login. Floating windows return to their exact box, tiled ones to their
workspace, where Hyprland tiles them. A window that is closed is started again
from its desktop entry and placed when it shows, but what was in it is not: tabs,
documents and terminal sessions start fresh. An app with no desktop entry cannot
be started, one that keeps to a single window comes back as one, and the page
says which.

In the overview a desk dragged onto another takes its place, or goes to that
screen if the desk is on another one, and a right press offers Move left and
right, Swap with, Move to and Swap screens. Windows, name and layout go together.
`eva workspace_move`, `workspace_swap`, `workspace_reorder` and `workspace_screens`
do the same.

`EVA_FAKE_WINDOWS=1`, or a JSON file like `tests/fixtures/windows.json`, stands in
for Hyprland: `shell/windows_stand_in.lua` is the same library over a list of its
own, evaluating the same `hl.*` chunks, with what the compositor really has among
its windows. `nix build .#windows-test` runs these against a real Hyprland in a VM.

### Keys and external screens

`programs.eva.remap.enable` lets Settings, Keyboard, Key remapping set Caps Lock,
a hyper key, tap versus hold and home row modifiers for every program. It is off
by default, as it reads every keyboard. kanata does the work, chosen over keyd
because its NixOS service has a dynamic user, no capabilities and no network, and
its stock build cannot run a command; keyd runs as root, and a line in its
configuration can run anything as root. Nobody joins the `input` group: only the
service's own dynamic user is in it. Settings writes words from a fixed list, and
root turns those into kanata's file, so a choices file written by hand cannot
reach kanata as text. With nothing chosen, nothing starts. Caps Lock alone needs
none of this: Settings, Keyboard has Escape and Control through xkb.

`programs.eva.hardware.ddc.enable` joins external monitors to the one brightness
level: the slider, the bar's module, the on-screen display and the keys all act on
the screen they are on, by DDC/CI where it answers and the backlight where it does
not. It installs ddcutil, and a udev rule tags only the buses that lead to a
display with `uaccess`, so it takes no group. This path has run against stand-ins
only: `lib/services/host_fake.lua` and a fake `ddcutil` in a VM, which has no
monitor on an I2C bus.

## Phone and desk

There are two forms. Each output is classed from its logical size: compact below
600 wide, medium to 839, expanded from 840, with a height class to match. A
touchscreen with no keyboard is a desk: same panels, same layout. A touchscreen
is the main input while no real keyboard is attached and the output is the
machine's own panel, so a docked phone is a desk on its monitor and a phone on
its panel. Turning the screen or docking a keyboard rebuilds that output in
place, and what was open stays open.

A phone has a status bar with the clock at the left and mobile, Wi-Fi and battery
at the right. Rare statuses, then Bluetooth, then VPN and Do not disturb fold into
a dot when the row runs out, then the percentage if the battery is above 20%. Set
`edgebar.corner` and `edgebar.cutout` for a screen's rounded corners and cutout.
Quick settings comes down from the top, and the dashboard rises from the bottom.

A desk's bar has the system tray, and optionally the wheel over the status for
volume and over the clock for the workspace (Eva, Bar). The tray serves a
StatusNotifier watcher only while the bar is up, so programs never register with
a tray nobody can see.

`EVA_FAKE_BATTERY=57,charging,saver`, `EVA_FAKE_STATUS=wifi,bluetooth,vpn,dnd`
and `EVA_FAKE_CUTOUT=400,68,34` stand in for hardware; a `tools/see/` scenario
exports them, as `tools/see/bar.steps` and `cutout.steps` do, and
`morf ipc call fake-battery 12` moves the battery while it runs. The battery's
stand-in also takes `wireless`, `fast`, `slow`, `watts=N` and `limit=N`.

### Convertibles

A convertible folded back stays a desk, its keyboard no longer counted: the same
panels and layout, the on-screen keyboard, and the screen following the
accelerometer. libinput ignores the keyboard and touchpad by itself while the
switch is on. Opened again the rotation is held by the hinge and the panel stands
upright. A keyboard plugged in or paired still counts while folded.

The state comes from the kernel's `SW_TABLET_MODE`, found through
`/proc/bus/input/devices` and read with `evtest`: its events as a stream, and
the switch asked outright at the start, after a resume, after each event, and
every 20 seconds while folded. `eva tablet on|off` is a hint the same question
follows; `eva tablet pin on|off` holds the posture over a switch that sticks,
`eva tablet auto` lets it go. `EVA_FAKE_TABLET=on|off` stands in for the switch.

```nix
programs.eva.hardware = {
  # evtest, and read access to switch devices alone. `name` is what
  # `hyprctl devices` calls the switch, and adds Hyprland's switch binds.
  tabletSwitch = { enable = true; name = "Intel HID switches"; };
  # The session may write the kernel's charge thresholds.
  chargeLimit = true;
  # A USB network port for the USB tethering tile.
  usbTether = true;
  # The Wi-Fi hotspot's clients reaching DHCP and DNS: the firewall opens those
  # ports on every Wi-Fi interface, to whatever listens on them. Without it they
  # join the network and are given no address.
  hotspot = true;
};
```

### Charging

The Power page says what feeds the battery (USB PD, a wireless pad, a weak
port), how fast and how long until it stops. A charge limit and adaptive
charging, which waits at 80% overnight and finishes by the time you set, need
`charge_control_end_threshold` from the driver and the right to write it:
`programs.eva.hardware.chargeLimit` grants that. Without the grant UPower's own
fixed thresholds can still be switched, where the driver and UPower have them;
adaptive charging runs in the shell, so a phone asleep through the night wakes
to its release late.

## Calls, texts and the modem

With `programs.eva.phone.enable` the module brings up ModemManager, callaudiod,
feedbackd and iio-sensor-proxy, and adds the user to `networkmanager` and
`feedbackd`. ModemManager's Voice and Messaging ask polkit for a password by
default, which nothing on a locked screen could answer; that group's rule is what
lets a call be taken there. `programs.eva.phone.calls = false` leaves all of it
out.

A call comes up on a surface of its own in the overlay layer: the whole screen on
a phone, a card on a desk. Pull the orb to a side of its rail, or press
that side. A locked session shows only the lock's surfaces, so the lock hosts the
same screen (`themes/phone_lock.lua`), along with the SIM's PIN and PUK and
emergency dialling, which takes only numbers that reach the emergency services:
the SIM's, 112 and 911, and six more with no SIM. The shell stays the owner either
way: it rings, routes the sound through callaudiod, holds suspend off through
logind and keeps the history. On the earpiece the proximity sensor blanks the
panel and takes every touch; the speaker stops that.

Texts go to `$XDG_STATE_HOME/eva/phone/`, private files that the shell and the
tools share, and come off the modem. A notification from one carries `reply` with
the number; `require("phone").reply(number, text)` answers it, which is what a
notification's inline reply calls. MMS is not done.

Contacts are vCards in `phone.contacts` (`~/.local/share/contacts`), which is
what vdirsyncer keeps. `phone.country` is the code bare numbers get. Favourites
and blocked numbers are eva's own, beside the history, and the cards are never
written to. A blocked call is ended before it rings.

Public warnings come by cell broadcast with ModemManager 1.24 or later. National
alerts always come through; the Mobile page turns the others off and lists what
has come. That page also shows the radio's levels, data by interface this month,
and takes `phone.data_limit` in megabytes, warning at 80% and at 100%.

The side keys reach the shell through Hyprland binds. A volume key or power
silences a call that rings. `phone.power_ends_call` ends one on power,
`phone.double_power` is a command for power pressed twice, power and volume down
takes a screenshot, and `phone.sos` counts down from five presses of power to an
emergency call. Set it on purpose: on a locked screen the countdown cannot show,
because only the lock draws there, and the call still goes.

`programs.eva.phone.suspendTimeout` is zero by default, so a phone stays awake.
Whether a call can wake a sleeping phone depends on its kernel and modem: name
what rings it in `programs.eva.phone.wakeDevices`, then call it while it sleeps
before setting a timeout. ModemManager and NetworkManager bring the modem back
after resume by themselves.

All of this comes down to one haptic seam, `require("haptics").fire(kind)`, with
one setting, `haptics.on` (Sound, Touch). Kit presses and tile toggles reach it by
themselves.

`EVA_FAKE_MODEM=1` runs the real service against ModemManager on a bus of Lua
tables (`lib/services/modem_standin.lua`). That bus knows only what ModemManager's
XML declares (`tests/fixtures/phone-bus.txt`), so a wrong name fails a spec, but
it says nothing about real timing, real errors or real audio. `phone fake ring
+316...`, `text`, `alert CHANNEL WORDS`, `lock sim-pin` and `near on` move it;
`EVA_CONTACTS`, `EVA_FAKE_HAPTICS`, `EVA_FAKE_PROXIMITY` and `EVA_FAKE_NET` stand
in for the rest. `tools/phone-wire.sh` sends every typed call through the engine's
encoder onto a real `dbus-daemon` and reads the types back off the wire, which no
spec can: it checks what goes out, not what a modem does with it.
`FEEDBACKD=... tools/phone-daemons.sh` runs the ringer against the real feedbackd.

## The bar's modules

The bar is a board of modules in three zones, start, centre and end, kept per
form factor. Eva, Bar arranges them on the same board as the quick tiles: drag a
module along or between zones, Alt and the arrows walk it, a badge removes it or
draws it as its icon alone, and Available holds the rest. From a script:

    morf ipc call bar modules
    morf ipc call bar add cpu end
    morf ipc call bar move cpu 1 start
    morf ipc call bar remove cpu

When a zone runs out of room its rarest modules fold into a mark that lists them,
then the status folds its own icons into its dot. Every module has a tooltip, a
press and a right press; a right press also arranges the bar or removes that
module, and a long press does the same on a touchscreen. A cutout parts the row:
the centre zone joins the end one and the live pill wraps the camera.

The modules: launcher, windows, window title, clock, world clock,
fuzzy clock, binary clock, countdown, next event, tasks, status, system tray,
privacy, live activity, notifications, dashboard, terminal, quick settings,
session, assistant, clipboard, colour picker, displays, keybindings, screenshot, wallpaper,
on-screen keyboard, volume, microphone, brightness, network, network speed, data
used, local and public address, VPN, Bluetooth, device batteries, battery, power
draw, power profile, CPU, CPU cores, CPU speed,
memory, swap, temperature, GPU, fans, disk, disk activity, load, uptime, machine
name, user, media, audio visualiser, lyrics, keep awake, focus, night light,
rotation lock, flashlight, recording, screen sharing, weather, updates,
keyboard layout, lock keys, key mode, failed services, containers, SSH sessions,
tmux sessions, trash, print jobs, GameMode, text, spacers and dividers.

The live pill shows the most pressing of a call, a recording, screen sharing, a
timer, the flashlight and media. It is one distance field: a press morphs it into
a panel with the activity's controls, and a second activity buds off it as a
bubble. A press on the bubble or a right press on the pill swaps them.

The privacy module names who is using the microphone, camera, screen and location
on a press. The camera comes from PipeWire's graph, and from whoever holds
`/dev/video*` open, read through `/proc` when the driver's use count moves; it
sees the person's own processes without root. Screen sharing comes from the
graph and Hyprland's screencast event, location from GeoClue.

Each screen can keep the bar up or down against the setting and keep modules of
its own (`bar.outputs`, or Eva, Bar). On Nix the Updates module reads the
generation and how old nixpkgs is, from the system and a flake.lock; elsewhere it
counts what the package managers offer.

### Your own modules

From a command, in `bar.custom` in the settings file. What it prints is the
module's text, or JSON with any of `text`, `tooltip`, `icon`, `tone` and
`percentage`. With `stream` it keeps running and each line is a new reading.

    { "bar": { "custom": [ { "id": "mail", "name": "Mail", "icon": "mail",
      "command": ["mail-count"], "interval": 60000, "press": ["thunderbird"] } ] } }

From Lua, in `~/.config/eva/bar/plugin/*.lua`, run in order at startup and then
`~/.config/eva/bar/after/plugin/*.lua`. A file registers by name, returns nothing,
and a later one replaces an earlier one of the same name. One that fails is
logged and the rest load. It runs as text in the shell's own Lua, as your code.

    local bar = require("eva.bar")
    bar.modules["ups"] = { name = "UPS", icon = "battery_saver",
      text = function() return "98%" end,
      tooltip = function() return "On mains" end,
      press = function() end,
      menu = function() return { { label = "Details", icon = "info", on_clicked = function() end } } end }

Stand-ins for a sealed session: `EVA_FAKE_MEDIA="Title|Artist"`,
`EVA_FAKE_DEVICES="Pixel Buds:82:headphones"`, `EVA_FAKE_WEATHER=18:2`,
`EVA_FAKE_CALL=Name`, `EVA_FAKE_TIMER=Tea:300` and
`EVA_FAKE_PRIVACY=mic:Firefox,camera:Zoom`. `morf ipc call fake-privacy` and
`fake-live` move them; `tools/see/barboard.steps` uses them all.

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

## Settings

Settings is a window of the shell's own, over everything: on a desk it stands in
the middle, seven tenths of the screen, and dims the rest; on a phone it fills
the screen. Every other screen dims with it. Escape, a press on any dimmed
screen and its close control shut it.
On a desk the left column has the search, the categories and their pages, and
the right one the page on show; a page one level into another has Back. On a
phone it is one page at a time, Back going up to All settings. It comes and goes
in the theme's own motion, lands at once under Reduce motion, and is open again
on its page after the shell is built again in place. A password prompt it leads
to stands in its place until answered; any other panel opening shuts it.

Quick settings, in the right panel, keeps the tiles, the sliders and who is
signed in. The quick controls' own pages open in the panel itself, sliding in
over the tiles: Wi-Fi's networks and its password, Bluetooth's devices and
pairing, Wired, Mobile data, Mesh, Tunnel (Tor too), Hotspot, Sound's outputs and
each app's volume, Microphone, Power, Focus and its modes, Screen time, Night
light, Flashlight, Colour filters and Background sounds. A tile's chevron (a
long press on a small tile) opens one; the arrow in the head, Alt+Left and a
pull in from the page's left edge go back. **More settings** in the head opens
the same page in the Settings window, and a row leading deeper (Equalizer, More
sound settings, a network's details, the proxy) opens there too. The Eva and Bar
tiles, Displays and **All settings** open the window, and the panel shuts as it
does. The bar's modules and the launcher open a quick control's page in the
panel; `morf ipc call quick KEY` does the same (`quick home`, `quick back`,
`quick more`, `quick close`, and `quick state` says where the panel stands).
`eva open settings/KEY` and `morf ipc call settings KEY` open a page in the
window (`settings home` is All settings, `settings close` shuts it and
`settings state` says where it stands); `morf ipc call settings-search WORDS`
searches, and with no words lists every page. Notifications' actions and the
window's own links lead to the window.

`shell/settings_registry.lua` is the one list of pages: `list()` gives `{ key,
name, icon, keywords }`. A new page is a row there and a builder in
`shell/utilities.lua`. A page that is only settings is a form in
`shell/settings_forms.lua`, with no view of its own. The window is
`shell/settings_window.lua`, a `shell/window_host.lua` over the theme's
`page_window` view, the same host as Tools; one of the two is open at a time.
The panel's pages are the keys of `shell/quick_details.lua`, on a navigation of
their own: the panel and the window each build their own copy of a page.

Where a system's configuration holds a value, the page says so and names the
option. On NixOS that is usually `time.timeZone`, `i18n.defaultLocale`,
`networking.hostName`, `networking.firewall` and `users.users`. Two settings
overrule the configuration, and say so where they are set:

- **Idle timeouts** are the other way about: a `programs.eva.idle.*` set in Nix
  wins over the Idle and sleep page, which shows it as set.
- **Lid and power button** start as **System**, which is logind's. Anything else
  wins while the shell runs, by an inhibitor; at the login screen logind decides.

Keyboard, pointer and accessibility choices go to Hyprland at run time and again
after each reload. They are never written into its configuration files, and
only what was changed in Settings is sent.

`EVA_FAKE_SYSTEM=1` stands a whole machine in for the real one
(`lib/services/host_fake.lua`), `=nixos` a NixOS one, and
`EVA_FAKE_CAN="suspend=no"` answers logind's questions. The service code above
it runs unchanged, against `lib.testing.dbus`. `tools/see/settings.steps` walks
every page: `EVA_FAKE_SYSTEM=1 tools/see.sh settings`.

## Welcome

The first login opens **Welcome** in the Settings window. It is four short
steps, three without a keyboard: dark or light, getting online, the gestures
this device answers to, and the keys to learn first. Each step leads to the real
page, and Back returns to the step. Skip leaves it. It comes once; Settings has
it after that (Eva, Welcome, or search), and `eva welcome` opens it too.

Someone who already used eva before this page existed is not shown it: past
notifications or reminders in the state folder, or a settings file, mark a
returning person. The mark itself is `welcome-seen` in that folder. Only the
shell loads it, so the lock and the greeter never can. `EVA_WELCOME=0` keeps it
away, as the VM tests do, and `=1` brings it to `tools/see.sh`.

## Connection help

Network and Wired each lead to **Connection help**.

**Troubleshoot** walks link, address, router, names (DNS) and internet in order
and says in plain words which one failed. A router that ignores ping is only
called the fault if names fail too. It runs when pressed, and asks your router
(`ping`), your DNS servers (`getent`) and the sign-in check's server.

**Sign-in pages**: when NetworkManager reports a captive portal, eva says so
with a notice and a row on this page, and pressing either opens the login page
in the browser. It never opens one by itself. NetworkManager only knows if its
own connectivity check is set up, so `network.portal_probe` (off by default) has
eva ask one server, once, each time a connection comes up: `nmcheck.gnome.org`
(GNOME), `detectportal.firefox.com` (Mozilla) or
`connectivitycheck.gstatic.com` (Google), by `network.portal_server`. Off, eva
sends nothing.

**Speed test** runs only when pressed, against `speed.cloudflare.com`, and uses
about 35 MB. The page says so before it starts, and warns on mobile data.
Everything outside goes through `lib/services/net_check.lua`, which names each
address, and `host.http`, which a headless run and `EVA_FAKE_SYSTEM` keep off
the network. `EVA_FAKE_NET` picks how the stand-in network breaks: `portal`,
`no-address`, `self-assigned`, `no-gateway`, `no-dns`, `no-internet`,
`quiet-router`.

## Backups

The **Backups** page works over whichever of snapper, btrbk and restic is
installed: it lists snapshots newest first, makes one on a press, and gets one
file back. With none installed it says so and what would do. Its settings pick
the tool, the snapper config, and restic's repository, password file and
folders; the password stays in its file and only that path reaches restic, in
its environment.

A restored copy lands beside the file with `.restored` on its name and
overwrites nothing. Replacing the file itself takes a second press that names
it. Snapper replaces through `undochange`, btrbk by copying from the snapshot,
and restic by restoring in place. Snapshots are often root's: a copy that
cannot read one says so. btrbk needs root even to list, so that waits for a
press and goes through polkit; `btrbk snapshot --preserve` keeps whatever a
retention policy would have pruned. Snapper uses your own rights, which its
`ALLOW_USERS` grants.

`EVA_FAKE_BACKUPS=snapper,btrbk,restic` puts stand-ins on the fake machine.

## Sound and nested settings

Sound opens **Equalizer**, which opens a deeper **Audiogram** editor. Back
returns to the parent page. Other settings can use the same hierarchy: give the
page a `parent` in `shell/settings_registry.lua`. Breadcrumbs and presentation
scopes follow it. `morf ipc call settings sound/equalizer` opens the EQ directly.

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
