# What the eva port needs from the engine

Paths below (`docs/`, `crates/`) are in the engine's repository,
[paneworks/morf](https://github.com/paneworks/morf).

Found while porting phase 1 (the frame, the bar, the launcher and the
dashboard). Each entry says what is missing, the API that would cover it,
and why Lua cannot do it well. Work already under way elsewhere is marked
**in progress** and only left as a TODO in the port.

Nothing open: every entry found so far is in the engine (below).

Phase 2 (the other dashboard tabs, the launcher's pickers, the session
menu, the bar's popouts, notifications and the OSD) found the entries
below, all now in the engine too; the popouts shut on `contains_pointer`
like the dashboard.

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
