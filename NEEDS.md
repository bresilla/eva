# What the eva port needs from the engine

Paths below (`docs/`, `crates/`) are in the engine's repository,
[paneworks/morf](https://github.com/paneworks/morf).

Found while porting phase 1 (the frame, the bar, the launcher and the
dashboard). Each entry says what is missing, the API that would cover it,
and why Lua cannot do it well. Work already under way elsewhere is marked
**in progress** and only left as a TODO in the port.

Open entries are listed first; every entry before them is in the engine (below).

Open, found against a real Hyprland in a VM:

- `lib.compositor.hyprland` starts on a one-millisecond timer, and until then
  `request` answers "unavailable" though `available()` says true. A tool that asks
  as it loads is told there is no Hyprland: `eva-displays` opened with no outputs.
  `lib.compositor.hyprland_config` asks again for its flavour, and
  `lib/shell/displays` does the same. Holding requests until the start would save
  each caller the loop.
- `hyprland.getoption` documents its reply as `int|float|str|css`, but a toggle
  answers `bool` under the Lua config manager and `int` under the legacy one, and
  a string nobody set answers `[[EMPTY]]`. `lib/services/input_config.lua` reads
  all of these. `hyprland.options` could answer one shape in both.
- With two outputs `ipc call` returns the first non-empty answer, whichever output
  it came from, so a verb answering for its own output can hide the other's.
  `drawers` keeps quiet where nothing is open and the focus is elsewhere; a way to
  get every output's answer would do it properly.

Open, found while building notifications and Focus:

- `lib.services.notifications` keeps its service to itself, so a shell cannot
  emit `NotificationReplied` or answer the `Inhibit` methods. A `server.reply(id,
  text)` and an `extra_methods` option would cover it. Lua can only do it badly:
  `lib/services/notification_server.lua` swaps `morf.dbus.serve` for the length of
  the call to catch the handle.
- `morf.image.from_dbus` pictures have no way to a file: `morf.image.process`
  takes a path or inline SVG, not a `memory:` source. A notification's raw
  `image-data` goes when its sender closes it, so the history shows the app's icon
  from then on, and a restart keeps no such picture. `morf.image.save(source,
  path)`, or `process` taking a `memory:` source, would cover it.
- A signal's `get` copies a table, so a binding that reads a long list pays for
  the whole list each time, and a table is never `==` to the last one read. eva
  keeps a revision number beside its lists (`shell/notifs.lua`, `listing`). A
  `signal:revision()` would save every list doing the same.

Open, found while building the assistant, Drop and the pages:

- **A streaming HTTP body.** `morf.http` calls back once, with the whole answer,
  and caps an exchange at 120 s, so a reply that streams cannot go through it.
  `on_chunk(bytes)` on `morf.http.request`, with `timeout_ms` covering the time
  between chunks, would cover it; the assistant streams through `curl --config -`
  instead (`lib/integrations/llm.lua`), with the key on curl's stdin.
- **Two Repeaters over one list model.** Rows added or removed reach both, but
  a changed row reaches only the first: `set` and a keyed `replace` patch one
  Repeater, and the second keeps the row it had. A page stands in a panel and as
  a settings page at once, so each view keeps a list of its own
  (`themes/layouts/mirror.lua`). Every Repeater of a model following every change
  would make that unnecessary.
- **Simulated drops.** `morf test` accepts drag and drop and goes nowhere with
  it (docs/TESTING.md, "What is not simulated"), and the sealed sway of
  `tools/see.sh` has no pointer, so `ui.DropArea` and `morf.drag.start` are
  proved in no harness. `test.drop(id, { paths = { ... } })`, entering, moving
  and dropping on a node, would prove the Drop and Phone pages' targets.

Open, found while splitting capture out:

- A layer on a chosen output from `morf app`. `runtime_bar_config` puts every
  `morf.window.layer` on its runtime's output, and an application has one
  runtime, the first output's, so a tool cannot open on the focused monitor.
  eva-screenshot runs as a plain `morf -i NAME config.lua` instead, one runtime
  per output as the shell has, with the idle runtimes held under the desk. An
  `output` key on `morf.window.layer` would let it be an application.

Phase 2 (the other dashboard tabs, the launcher's pickers, the session
menu, the bar's popouts, notifications and the OSD) found the entries
below, all now in the engine too; the popouts shut on `contains_pointer`
like the dashboard.

## Open: found building the wallpaper, widgets and glass

- **An image as a field's fill.** `ui.Sdf` takes a colour or a gradient, and
  `backdrop_blur` and `glass` work on a `Rect` or `ClipRect` only. A frame that is
  one field cannot be glass by itself, so the shell draws a blurred copy of the
  picture under it, cut by a second field that tracks the same nodes
  (`themes/glass_plate.lua`). `fill_image = source` on `ui.Sdf`, or `glass` on a
  field, would need neither the copy nor the second field.
- **Centre and tile fills.** `ui.Image`'s `fill_mode` is `stretch`,
  `preserve_aspect_fit` or `preserve_aspect_crop`; `pad` and `tile` would close
  two wallpaper fill modes other shells have.
- **`behavior` on `transform_matrix`.** UI.md says it animates like any list of
  numbers, but a `ui.spring` behavior on it is refused with "expected numeric or
  colour property", and the error takes the whole subtree with it. A carried
  widget's lean snaps for that reason.
- **`morf.fs.home()` under a test.** It ignores an `env = { HOME = ... }` given to
  `test.load`, unlike `morf.env`, so a configuration writing under the home in a
  spec reaches the real one (it did, here: see `lib/services/desktop_look.lua`,
  which now reads `HOME` first, and the guard in `tests/look_spec.lua`). The
  `--isolate` folders protect XDG paths only. `morf test` could point the home at
  its scratch folder too.
- **`morf.lock` in another process.** A shell cannot ask whether the session is
  locked by a separate lock role: `morf.lock.on_state` is for the process holding
  it. The slideshow reads logind's `LockedHint` instead.
- **Undocumented.** `morf.image.palette`, `morf.image.pixel`,
  `morf.animation.impulse` and the sixteen-layer limit of a field are in the
  source and the namespace table but not in UI.md or IO.md.

## Engine fixes made in this branch

- A node's hover including its descendants: every node has a read-only
  `contains_pointer`, true while the pointer is inside its box whatever is
  on top (docs/UI.md, "Hover and press"). The dashboard shuts on
  `panel.contains_pointer` going false instead of a hand-kept list of its
  areas.
- Opacity of one layer in a field: `opacity` on an `SdfShape` fades that
  layer, seam and all, without fading the rest of the field (docs/UI.md,
  "Fields"). A drawer's background, a layer of the frame's field, now fades
  in with its contents as the reference's does.
- Headless runs (`morf check`/`render`/`test`) stretched a layer anchored at
  both ends of an axis to the screen even when it asked for a size; a
  compositor keeps the asked size, centred. The port's wallpaper layer,
  missing `height = 0`, was whole headless and a 32 px band on Hyprland.
  Headless now does what layer shell does (`crates/morf-cli`).
- `morf render --surface screen` (and `test.snapshot(..., { surface =
  "screen" })`) composed surfaces in declaration order, so a background
  layer declared after the shell's own surface covered it. They are now
  stacked by layer-shell layer (background, bottom, top, overlay), keeping
  declaration order within a layer (`crates/morf-cli`).
- An axis other than `wght` reached only the rasteriser, so Google Sans
  Flex's `opsz` could not widen small labels. Every axis is now shaped
  (the vendored cosmic-text takes the axes), optical sizing is automatic
  from the size in pixels as in CSS, and `kit.text` sets `opsz` to the size
  in points (and `ROND` 25), as the reference's font builder does. The
  Alacritty description, at the port's 15 px, measures 366 px where it
  measured 333; at the reference's own `body.small` (12 pt, 16 px) it is
  386 against the reference's 390.
- Key names: handlers are handed the key's X name as a fifth argument
  (`on_key_pressed(keysym, text, modifiers, repeat, name)`), and
  `morf.keys.Down` is its keysym; the port compares names and its keysym
  table is gone (crates/morf-lua `keys`).
- A module's budget: `require` loads on a budget of its own (20 million
  instructions, `MORF_LIMITS=module=N`), a loading's not a handler's, and
  the budgets are listed in docs/UI.md ("How much Lua may run at once").
- Bindings after construction: a function assigned to a node's property
  is a binding, as in the constructor, and replaces any it had
  (docs/UI.md, "Bindings").
- A theme-wide colour transition: `morf.theme(tokens, { transition = {
  duration, easing } })` eases every colour written to it in OkLab, frame by
  frame; the port's scheme, variant and mode changes cross-fade in 400 ms.

## The window features: open

- A window capture with `gpu = true` on a software renderer ends the session's
  connection. Under Hyprland 0.55.4 on llvmpipe (`nix build .#windows-test`),
  `morf.screencopy.capture_window` with `{ gpu = true }` draws
  `wl_display#1: error 1: invalid arguments for
  ext_image_copy_capture_frame_v1.attach_buffer` and the shell exits. A refused
  dmabuf should fall back to shared memory, or fail the one capture.
  `shell/window_shots.lua` asks for shared memory when `LIBGL_ALWAYS_SOFTWARE`
  is set; a machine on a software GPU without it set still dies.
- A capture of a window that has just gone ends the connection too:
  `ext_foreign_toplevel_image_capture_source_manager_v1: invalid foreign toplevel
  resource`, from Hyprland 0.55.4, for a `create_source` on a handle it destroyed
  before `closed` reached the shell. `shell/window_shots.lua` holds captures back
  around a close and on `closewindow`, which narrows the race and does not end
  it; the unit restarts the shell. It needs a guard in `capture_window`, or a
  capture that fails on its own without the connection.
- `hyprland.state.active_window` can stay empty after a panel shuts. On Hyprland
  0.55.4 `activewindowv2` empties it while a layer holds the keys, and in a VM
  run nothing refilled it after the sidebar closed, so every "focused window"
  verb found none until the next click. That cause is read from the trace, not
  proven. `windows.active()` falls back to the last focused window on the
  workspace; `hyprland.refresh()` could re-read `j/activewindow` instead.
- D-Bus signals from any sender. `proxy:subscribe` needs a destination and a
  path, and `com.canonical.Unity.LauncherEntry.Update` is a broadcast from an
  application's own path, so dock badges cannot hear unread counts or progress
  from applications. The dock counts the notification history instead.
- Which modifiers are held. `on_key_released` is the only way to learn that Alt
  came up, and a surface that takes the keyboard after the key came up never
  hears it: the switcher relies on a compositor bind for that case. Something
  like `morf.keys.modifiers()`, from the `wl_keyboard.modifiers` event, would
  settle it. Hyprland has `hl.is_key_down` from 0.56, not in 0.55.
- Drag and drop from a layer surface into a window, for a dock taking a dropped
  file: `DropArea` takes one, and a launch with arguments does not exist
  (`index:launch(id)` passes no URIs).

## Phase 3: the sidebar and the utilities

Nothing open. The idle inhibitor reads back: `morf.idle.inhibited()` is
what the shell last asked for, and `morf.capabilities.idle_inhibit` says
whether the compositor can hold one (docs/IO.md, "Idle").

## Settings: open

- A binding that raises is silent. `("%d"):format(150.5)` in a row's subtitle
  left the row blank, with nothing in the log and nothing in `test.logs("error")`.
  One warning per binding would have shown it. Specs now assert a page's content.
- No virtual pointer. Mouse keys go through `wlrctl`, and are hidden without it.
- Escape reaches a drawer's close policy as well as a focused field's
  `on_escape`, so a search field cannot take the first Escape to clear itself.

## The launcher: open

- A key a text field would use, before the field uses it. `on_key_pressed` hears only
  what the field has no use for, so quick look on Space takes the character back out
  of `on_text_changed`. A `on_key_filter(keysym, text, modifiers)` that can swallow a
  key would do it cleanly.
- A second finger that lands on nothing. `pan::down` cancels a pan only for a contact
  in `input.touches`, and a contact is recorded only when it hits a node, so a
  second finger on bare desk does not cancel an edge pull.
- A clipboard offer of several types. `morf.clipboard.set(data, mime)` offers one, so
  text cannot be marked `x-kde-passwordManagerHint` beside its `text/plain`. eva hands
  secrets to `wl-copy --sensitive`, on stdin.
- Leaving stderr out of a run. `morf.process.run` keeps stdout and stderr under one
  `max_output`, and `nix search` writes 8 MiB of progress to stderr. An option to send
  stderr to /dev/null would replace the `sh -c '... 2>/dev/null'` the Nix mode uses.

## Convertible, battery and phone tiles: open

- A pen's pressure and tilt. The compositor's `zwp_tablet_v2` events reach a
  node as a pointer press with no more to them, so a drawing surface cannot
  vary its stroke and a hover cannot be told from a touch. An event table for
  pointer handlers, `{ tool = "pen"|"eraser", pressure = 0..1, tilt_x, tilt_y,
  hovering }`, on `ui.MouseArea` and `kit.Canvas` would cover it. Lua cannot get
  at the protocol at all.
- A switch's state. `morf.input.switch("tablet_mode")`, a tracked read over
  `EVIOCGSW` and the device's events, in the engine's privileges. Today
  models/posture.lua spawns `evtest`, which needs a group the session would
  rather not have, and Lua cannot make the ioctl.
- `service:call_async` on a `morf.dbus.serve` object. `service:call` blocks the
  thread that runs the object's handlers, so a service that calls back before
  it answers hangs the shell until a timeout. GeoClue's `Manager.AddAgent` does
  that (it reads `MaxAccuracyLevel` from the agent), and it takes the agent from
  the caller's connection, so no other connection can register it. Without
  this eva cannot be the session's location agent: the Location tile starts and
  stops GeoClue's demo agent, and a per-program prompt or an accuracy choice
  cannot be the shell's.

## Tools: open

- A surface ending inside its own event. `win:destroy()` on a layer surface,
  reached from a key handler on that surface or from an effect the handler
  flushes, logs `scene layout error: stale scene node handle` and the runtime is
  gone. `frame.dismiss` in `apps/common/frame.lua` closes the surface and destroys
  it on the next turn. `destroy` deferring itself past the running event would
  cover it.
- A key sent to a surface in `morf test`. `test.click` takes a `surface`;
  `test.key` goes to the focused surface alone, so Escape on an overlay is proven
  with a real key in `tools/see/` and has no spec.
- ICO images. A favicon holding only BMP frames cannot be decoded: `eva-webapp`
  takes the PNG frames out of an `.ico` in Lua and otherwise draws a letter.
- A panic on an empty field. `command_reach`
  (`crates/graphics/morf-render/src/gpu/backend_render/frame_draw.rs:242`) indexes
  out of bounds when a full-screen field resolves to no tiles and is the frame's
  last instance: a box minus a circle wider than the screen does it on the first
  frame. eva-find's centre dot and eva-kill's hint are drawn after the field so
  it never is the last.
- A layer surface with nothing to paint on its first frame never shows, so
  `eva-find --ripple` keeps a hint card.
- `morf.image.pixel` decodes the whole file on each call and refuses pictures over
  4 MP. `common/freeze.lua` samples through `morf.image.preview`.
- `morf.ipc` limits a call's arguments, so eva-draw's `stroke` verb takes one string.
- A job without a compositor. `morf app` needs Wayland and has no stdin, stdout or
  exit status for a configuration, so a tool's command line runs through files
  (`lib/util/job.lua`) and fails on a TTY or over SSH, `eva-text` included.
- `xdg_toplevel`'s suspended state. A window cannot hear that nothing shows it:
  `eva-monitor` stops sampling when minimised, paused or away, and keeps sampling
  on a hidden workspace.

## Seamless login: open

- Custom shaders on a held lock. Every renderer calls `register_shaders` except
  the lock's (`crates/frontend/morf-host/src/lock/lock.rs`, after
  `RenderEngine::new`), so a node with `shader` draws as a plain `Rect`: a
  white one, at the node's opacity. `morf render` registers them, so it does
  not show this. eva leaves Tsugumori's phase art out of a held lock until then.
- A failed dmabuf import. `BufferSink::import` uses `create_immed` and ignores
  `failed`, so the compositor ends the client with a protocol error at the first
  `attach`. Falling back to the swapchain would keep the shell up on a software
  GPU. `MORF_PRESENT=swapchain` does it by hand, in `nix/tests/login.nix`.
- A first-frame hook. `enter` starts on a surface's first frame, but Lua cannot
  hear it. Plymouth's hand-over listens for Hyprland's `layer.opened` instead.
- Font features on `ui.Text`. The default skin's `numeric` token names
  `features = { "tnum" }`, but no node property carries it, so a bar clock with
  seconds, or a rate that ticks, shifts width as its digits change. `features`
  on `Text`, passed to shaping as `axes` are, would give tabular figures.
- Video streams in `morf.audio`. `streams` lists audio alone, so the privacy
  module spawns `pw-dump` to see who reads a camera or a shared screen. Video
  nodes and links there would save the child process and hear each change.
- A monotonic clock. `morf.time.now_ms` is the wall clock, which a suspend and a
  changed date both move. The lock's window after an idle lock reads
  `/proc/uptime` for its deadline and for the gap that says the machine slept;
  `morf.time.monotonic()` and `morf.time.boottime()` would replace that file.
- Lock keys with a key event. `modifiers` holds `ctrl`, `shift`, `alt` and
  `super`, not Caps Lock, so the login screens read the LED under
  `/sys/class/leds` a moment after each key. A keyboard without the LED gets no
  warning. xkb's locked modifiers are what the compositor already sends.
- A point to a text offset. `ui.TextInput` has `cursor_position` but no way to
  ask which offset lies under a point, or where the caret is drawn, so a field
  cannot draw a caret handle a finger drags. `themes/kit/text_touch.lua` walks
  the caret with the engine's drag selection instead, and drops the selection
  on release. `:offset_at(x, y)` and a `cursor_rectangle` would allow a handle.
- A touch mode for `ui.Terminal`. A finger is the left button, so one finger on
  a terminal selects as it moves, held first or not, and `:scroll` has no way
  in from a pan because a terminal keeps every drag. A `touch_selects = false`,
  with selection beginning from `on_long_pressed`, would let one finger scroll.
- A node's parent from Lua. `themes/overscroll.lua` finds an enclosing list and
  the panel under a finger by comparing rectangles, for want of `node.parent`.

## Global touch: open

- Reading a touchscreen. `shell/touch_driver.lua` hears every contact through a
  `libinput debug-events` child and parses its lines, for want of an evdev API:
  `morf.touch.open(node, handlers)` in the engine would save the process and the
  parsing, and stop for good with the handle.
- Output power as a signal. Nothing says an output went dark, so the driver asks
  Hyprland's `j/monitors` as each contact sequence starts, to keep gestures from
  firing on a dark screen. A tracked read beside `morf.output_power.set` would do.
- `pcall` of a nil value raises rather than returning false, unlike Lua, and
  `debug` is absent, so an effect's error names no line: `could not call a nil
  value` from `pcall(child.pid, child)` took a spec to find.
- Taking a contact back. Hyprland 0.55 has `sendTouchCancel` and never calls it,
  and a libinput TOUCH_CANCEL does nothing there, so a global gesture cannot take
  its fingers away from the app under them. Hyprland also keeps one touch focus:
  with a finger on eva and a finger on an app, both lifts go to the app, so the
  strip under the first finger never hears it lift.
- Cancelling a surface's contacts. A second finger on a surface interrupts its
  pan, but one landing on an app does not, so `phone_gestures.yield` reaches the
  panels' pans and drawers by hand. A list's scroll or `themes/swipe_dismiss.lua`
  under one of three fingers runs on. `morf.surface.cancel_touches()` would end
  them all.
