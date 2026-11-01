# What the eva port needs from the engine

Paths below (`docs/`, `crates/`) are in the engine's repository,
[paneworks/morf](https://github.com/paneworks/morf).

Found while porting phase 1 (the frame, the bar, the launcher and the
dashboard). Each entry says what is missing, the API that would cover it,
and why Lua cannot do it well. Work already under way elsewhere is marked
**in progress** and only left as a TODO in the port.

Open entries are listed first; every entry before them is in the engine (below).

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
