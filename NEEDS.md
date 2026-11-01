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

## Phase 3: the sidebar and the utilities

Nothing open. The idle inhibitor reads back: `morf.idle.inhibited()` is
what the shell last asked for, and `morf.capabilities.idle_inhibit` says
whether the compositor can hold one (docs/IO.md, "Idle").

## On-screen keyboard: open

- A text field's content type. `zwp_input_method_v2` sends `content_type(hint,
  purpose)` and `crates/platform/morf-app/src/backend/wayland/protocol_handlers.rs`
  has no arm for it (it falls to `_ => {}`), so Lua cannot tell a password field
  from a search box. Keep it on `InputMethodState` and pass it on as two more
  arguments: `morf.input_method.subscribe(function(active, surrounding_text,
  cursor, anchor, serial, purpose, hints) end)`, `purpose` the protocol's name
  (`"password"`, `"phone"`, `"url"`, ...) and `hints` a list of its flag names
  (`"hidden_text"`, `"sensitive_data"`, ...). `shell/keyboard_model.lua` already
  takes both, so nothing else changes. Until then autocorrect and learning stay
  off by default, and a window's class stands in for the field.
- Layouts in `lib.shell.osk`. `PAGES` and `ALTS` are locals with no way in, so a
  language can only be painted over the QWERTY keys. Wanted: `osk.new { pages =
  { letters = rows, ... }, alts = { e = { "é" } } }`, and `shifted` taking
  `options.upper(text)`, since `string.upper` is ASCII only. eva's workaround is
  `shell/keyboard_board.lua`: it rewrites each key's place through `action`, its
  label through `key_face` and its letter in `send`. It costs:
  - osk.lua's row formula copied into `shell/keyboard_layouts.lua`, and its
    key-height formula into `themes/keyboard.lua`'s `metrics`; a change in osk
    breaks both without an error.
  - `ALTS` copied as `ACCENTS`, because a moved letter needs the accents of the
    letter it now shows.
  - A key `id` format (`<prefix>.key.<mode>.<page>.<char>`) read as an interface.
  - Only 36 letter keys exist, the 26 and the digit row's ten, so a language past
    26 letters gives its digit row up. Russian and Ukrainian can have no number row.
  - A press outside the language's letters (a long press on a digit's key) keeps
    osk's offers for that key.
- osk's alternates and preview have no API either. They are `morf.signal`s made
  inside `osk.new`, and a signal's name finds nothing: `morf.signal` makes a new
  signal each call. `boards.capture` in `shell/keyboard_board.lua` wraps
  `morf.signal` for the length of `osk.new` to keep them, which depends on osk
  calling it through the shared `morf` table. Wanted: `osk.new { offers =
  function(key, list) return list end, preview = function(key, text) return text
  end }`.
- Keyboard metrics after build. `osk.new`'s `width` and `metrics` are fixed, so one
  hand, floating, split, the height setting and a language change each destroy the
  board and build another (`build_board` in `themes/layouts/views/keyboard.lua`).
  Wanted: `kb.resize(width, metrics)`.
- A hook on the whole press. `action` wraps `on_pressed` and `on_released`, but
  `on_touch_canceled` is assigned to the node after `action` returns, so a cancelled
  press is only heard through `keys.cancel`. Wanted: `options.on_cancel(id)`.
- Text past ASCII with no field asking. `osk.sender` types key presses on a US
  layout, so `é` or `я` goes nowhere when no input method is active: the shell's own
  fields, and any program without text-input-v3. Wanted: `morf.virtual_keyboard.keymap
  (text)` to upload one, or a Lua way to insert into the focused `ui.TextInput`.
- A short sound with no process. A key click needs a sample played with no spawn
  per press; `morf.audio` has streams and no sample player. Wanted:
  `morf.audio.play(path, { volume })`. eva has no key sound until then.

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
