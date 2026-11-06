# Motion reference and current implementation

Reference: [Tsugumori](https://github.com/Aleph1-9012/Tsugumori),
commit `0b398e7fbc7633abbbdf27ea1e93d1c99e6d6866`.
Adapted code is covered by the adjacent `LICENSE-Tsugumori`.

- `widgets/Menu.qml`: covered entrance, 440 ms OutExpo; separate uncover,
  340 ms OutExpo. Exit covers over 420 ms with cubic Bézier
  `(0.76, 0, 0.24, 1)` and withdraws over 510 ms starting at 270 ms.
  `motion.lua` adapts travel to each shell edge and preserves interrupted poses.
- `components/controlcenter/ControlCenterView.qml`: subcontrols enter from
  `(-12, -8)`, 380 ms OutCubic after 280 ms plus an 80 ms stagger.
  The dashboard also adapts its selected-card branch motion: geometry travels
  over 480 ms OutCubic, surrounding cards fade over 240 ms, and withdrawal uses
  250 ms InCirc. Detail entry waits 280 ms before its 380 ms settle. Covered
  branch changes retain the shared page-cover animation. Calendar and media
  controls preserve their existing shell actions.
- `components/controlcenter/Frame.qml`: moving corner marks inform the shared
  interaction feedback. The hover underline was removed at the user's request.
- `widgets/lockscreen/PhaseArt.js` and `shaders/lines.vert`: deterministic
  hash, branching K strokes, progressive stroke lengths, and password-count
  glyph subdivision are ported to the Lua shader in `phase.lua`. The field is
  calculated on the GPU. Eleven uniform values update every 16 ms only during
  presentation or typing; the timer stops afterwards. No shader reads time.
- `widgets/lockscreen.qml` / `PhaseArt.componentState`: 1450 ms presentation,
  950 ms dismissal; staggered frame, folio, account and authentication reveal.

All colors use wallpaper-derived semantic roles. Fixed upstream red and its
branding are not required by these effects.

This is not a claim of full visual parity. The dashboard now has independent
overview-to-branch choreography, but several inherited detail pages still need
dedicated layouts. Weather has a responsive forecast register, and Battery
has a charge register and responsive instrument graphs. Both stack at compact
widths; the remaining fixed detail pages scroll their native geometry.
Intermediate-pose tests and Cage captures exercise the new transitions; they
do not establish exact motion parity with the reference.

Engine detail: reads of animated node values do not invalidate Lua bindings
each frame. Native channels therefore animate directly; auth opacity ramps
use sampled native keyframes. Only shader uniforms need the finite timer.

## Mara GAME additions

[Mara](https://github.com/bresilla/mara), inspected at
`3e8790a8bc5662dbe917875a789692e77ce32dde`, supplies the design reference
for `heading.lua`: `crates/core/src/style.rs` (`scramble_text`) and
`crates/core/src/pane/title.rs` (chromatic title ghosts and registration pips).
This is an independent Lua implementation of those visual ideas.

Titles decode left to right after their panel begins revealing. After the
normal 560 ms reveal delay, the first letter locks at 650 ms; an 80 ms stagger
caps decoding at another 1370 ms (1930 ms including the delay). The brief
workspace indicator uses the same component with a 160 ms lead and 20 ms
stagger, so it finishes before its short hold expires.
The light is slightly raised from the line-box center to align with the
visible uppercase letters beside each title, and gives two short pulses
occasionally while visible. Each title starts after a random 4–9 seconds and
chooses a fresh random 7–11 second pause between bursts, so titles do not blink
in unison. Hiding the panel or scrolling the title out of view stops its timer
and animation. A finite split-color flash accompanies the reveal.
Ghost colors use the wallpaper's secondary and tertiary roles, not fixed
red/cyan. UTF-8 characters stay intact. Hiding cancels the timer and motion;
reopening starts a fresh decode. The only text timer runs at 25 Hz during the
finite reveal. The occasional title light uses finite native animation, with
a slow timer between bursts and no redraw animation during the quiet pause;
the text and color ghosts remain still after decoding.

Mara's button motion catalogue is deliberately excluded: retain the existing
Tsugumori corner feedback and rolling button labels. The inspected "beeping"
effect is a visual blinking pip, not an audio implementation.

The workspace rail, frame registration corners and notification history
register are independent morf layouts using these shared motion and text
components. Material retains its own rounded frame, morphing workspace discs
and grouped history cards. The history controller owns actions and identity;
neither visual package owns notification expiry or server calls.

## HUD chrome and boot passes

Independent morf work; nothing in this section is code taken from the
reference. All of it uses wallpaper roles and stops at rest.

- `boot.lua`: one finite pass over a host. The outline traces in from the
  top-left corner both ways (one path, `trim_start`/`trim_end` out from 0.5),
  four brackets hold, step in and settle with an overshoot, a 2 px scan line
  with a glowing trail sweeps it top to bottom in 300 ms, and a register of
  static words prints and fades. Nodes are made on the first pass and hidden
  when it ends; a stop fades them over 90 ms.
- The content pass (`B.content`) boots what is laid out under the host as
  the scan reaches it: each card's outline draws itself in, its brackets
  fly in from the host's corners and snap on past their corner and back,
  its lit cuts flicker on, section captions light their plate and run
  their rule out, readings decode (`kit.decoding`), rolling numbers roll
  in, meters refill cell by cell and gauges sweep up. `marks.lua` holds
  what it drives, by node, until the node is destroyed; a pass looks it up
  by layout box, in three turns of its own (cards, captions, readings), at
  most 32 of each. A stop lands every track on its rest pose.
- Drawers (all but the keyboard and the notification stack) play the pass
  as their cover all but lifts, so it runs over the content, with the unit
  call sign of `curtain.lua` as the register; a dashboard tab plays its
  content pass as the wipe uncovers it.
- `motion.lock_on(host, id)`: heavy brackets close onto a host from outside,
  a scan crosses it and its content boots, looked up as the pass begins
  (the host may still be growing). The OSD bud, the session menu's focused
  row and dialogs in place use it; Material's hook draws nothing.
  Notification arrivals (`registration.lua`) lock on with heavier brackets
  from further out and flash the card's header band; popup grounds
  (`widgets/popup.lua`) play the boot pass directly.
- `dots.lua`: a dot grid behind the dashboard, side, planner and bottom
  panels, with a small cross every fourth step: two paths per panel.
- Cards (`kit.card`) and framed panels (`kit.panel`) are cut at 45 degrees
  on the top-left and bottom-right; the cuts are lit and run on along the
  top and the foot, the outline sits at 0.7, four 16 px brackets two wide
  stand on the corners, and a foot ruler, a serial strip and side notches
  share one path. The box and its geometry are the layout's; only the
  paint is cut (a field card has its corners painted out in the ground).
- Section captions (one built just after its card) carry an index plate,
  numbered in card order per page; the rule runs to the caption's end
  tick with a block of hazard stripes before it. Menus and rows have none.
- `kit.decor`: `corners` are heavy brackets the pass flies in; `ticks` and
  `scale` draw in the boxes layouts reserve, a scale's long ticks numbered
  in segment digits (`digits.lua`).
- The frame's top and bottom edges count screen pixels: a long tick every
  hundred with its number in segment digits, a middle one every fifty, a
  short one every ten. The corner reticles are 46 px Ls with a pip in the
  band's corner. A workspace switch sends a bright segment with a glowing
  tail along the rail's lip, which fades where it lands.
- Page covers slice into three bands a step apart. Rows enter on a decode
  curve (two flickers, then a settle). Meters light whole cells in sequence
  from wherever the run stands. Readouts glitch once on a change, at most
  every five seconds.
- Feedback: a hovered control's four brackets close in from 12 px out and
  snap on, a press sends a bright bar with a trail across it, and the
  keyboard focus reticle slides from the control it left. An on-screen
  keyboard's keys keep their two marks and no scan.

The moving light blade on drawer and page reveals uses the registration-edge
motif from [Tsugumori](https://github.com/Aleph1-9012/Tsugumori) and the brief
HUD accent flashes in [cyberpunk-ui](https://github.com/rintran720/cyberpunk-ui)
as visual references. It is drawn as a sibling above the clipped cover because
the renderer can hide children of an animated cover beneath its fill. A narrow
on-surface stroke leads a low-opacity wallpaper-secondary trail. Both are
finite native tracks and disappear when the reveal finishes or reverses.

## Motion across the shell

Independent morf work, like the HUD chrome above; it reuses the pieces of
that section and adds no running timer.

- The drawer calls `ctx.reveal(true)` as its cover starts to lift, and the
  curtain covers the panel's whole box, the height it grows to included,
  from the first frame. `motion.rows` plays the row decode (`kit.enter`)
  again on rows already built: the launcher's rows in sight on every
  opening, a menu's items as it opens, scan results as they join a list.
- `kit.leave` runs the decode out as a row leaves its list.
- `motion.appear`: a dialog in place (window switcher, snap picker, the
  launcher's quick look) unfolds from a band on an expo curve under a target
  lock (`motion.lock_on`), and folds a step as it goes dark, drawn until it
  has gone. Claims hold the pose, so a reversal goes on from where it stands.
- Checkbox and menu checks register their block from the left in three hard
  beats; switch, checkbox and radio frames ease their colour.
