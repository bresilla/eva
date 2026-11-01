-- The on-screen keyboard: a drawer of its own along the bottom edge --
-- beside the capture drawer, not in it -- carrying lib.board's keys, which
-- type into whatever has the focus through a virtual keyboard. The drawer
-- never takes the focus itself, so the text goes where it was going.
--
-- It comes up by itself when a program asks for text (a text field is
-- focused: the input-method protocol says so) and no real keyboard is
-- attached (lib.keyboards), and goes when the field does -- unless it was
-- opened by hand. By hand: `keyboard [toggle|open|close]` over IPC, which a
-- key can be bound to. `keyboard.auto = false` in the settings stops the
-- coming up by itself. Hiding it by hand also suppresses automatic opening
-- for that application until it is opened by hand again, for this login.
--
-- This is the controller: shell/keyboard_model.lua holds the state, and the
-- other keyboard_ modules what typing does, what the strip offers and how a
-- language's letters reach lib.shell.osk's keys.

local morf = require("morf")
local config = require("config")
local osk = require("lib.shell.osk")
local keyboards = require("models.keyboards")
local hyprland = require("lib.compositor.hyprland")
local model = require("keyboard_model")
local predict = require("keyboard_predict")
local M = { opened = morf.signal("eva.keyboard.shown", false), model = model }

-- Application IDs, not window addresses or titles: two Kitty windows share
-- the choice, while Firefox keeps its own. An unknown app never blocks all
-- apps. The compositor's session ID keeps an old choice out of a new login.
local function application()
  local name = hyprland.state.active_window.class or ""
  name = name:match("^%s*(.-)%s*$"):lower()
  return name ~= "" and name or nil
end
local runtime = morf.env("XDG_RUNTIME_DIR")
local session = morf.env("HYPRLAND_INSTANCE_SIGNATURE")
if not session or session == "" then session = morf.env("XDG_SESSION_ID") end
if not session or session == "" then session = morf.env("WAYLAND_DISPLAY") end
local preferences
local hidden = morf.signal("eva.keyboard.hidden_apps", {})
if runtime and runtime:sub(1, 1) == "/" and session and session ~= "" then
  preferences = require("lib.shell.settings").open {
    name = "eva.keyboard.session",
    path = runtime .. "/morf/keyboard-hidden-" .. session:gsub("[^%w_.-]", "_") .. ".json",
    defaults = { hidden = {} },
  }
end
local function hidden_apps() return preferences and preferences.get("hidden") or hidden:get() end
local function suppressed(app)
  if not app then return false end
  for _, name in ipairs(hidden_apps()) do if name == app then return true end end
  return false
end
local function remember(on)
  local app = application()
  if not app or suppressed(app) == (not on) then return end
  local apps = {}
  for _, name in ipairs(hidden_apps()) do if name ~= app then apps[#apps + 1] = name end end
  if not on then apps[#apps + 1] = app end
  if preferences then
    preferences.set("hidden", apps)
    preferences.flush()
  else hidden:set(apps) end
end

local field = false
local send = osk.sender { ime = function() return field end }
local typing
local function dry()
  local value = morf.env("EVA_DRY_RUN")
  return value ~= nil and value ~= "" and value ~= "0"
end
local function deliver(event)
  if not dry() then send(event) end
end
local function delete_before(bytes)
  if dry() or not (morf.input_method and morf.input_method.delete) then return end
  pcall(morf.input_method.delete, bytes, 0)
end

function M.active() return M.opened:get() end
--- What osk struck, on its way to the field.
function M.strike(event)
  if not M.active() then return end
  typing.strike(event)
end
M.send = M.strike
function M.close() M.set(false) end
function M.desk_size()
  local _, _, w, h = require("bar").desk()
  return w, h
end

--- A finger came down on the key `name`.
function M.pressed(name)
  if config.get("keyboard.haptics") ~= false then require("haptics").fire("key") end
  typing.pressed(name)
end
--- The cursor moved by a key of the board's own.
function M.move(key, mods)
  deliver { key = key, mods = mods }
  if not model.known() then model.forget() end
end
function M.pick(offer) typing.pick(offer) end
function M.paste(text)
  typing.paste(text)
  model.tray:set("words")
end

local recent = morf.signal("eva.keyboard.emoji.recent", {})
--- The emoji picked since the shell started, the latest first. Never written down.
function M.recent_emoji() return recent:get() end
function M.type_emoji(char)
  typing.emoji(char)
  local list = { { char = char } }
  for _, row in ipairs(recent:get()) do
    if row.char ~= char and #list < 32 then list[#list + 1] = row end
  end
  recent:set(list)
end
function M.start_search()
  model.searching:set(true)
  model.query:set("")
  model.show_pane("keys")
end
function M.end_search()
  model.searching:set(false)
  model.show_pane("emoji")
end
local searched = { query = nil, found = {} }
--- What the emoji search finds, at most `limit`.
function M.search_results(limit)
  local query = model.query:get()
  if query == "" then return {} end
  if searched.query ~= query then
    searched = { query = query, found = require("lib.shell.emoji").search(query, limit) }
  end
  return searched.found
end

local function flip(name)
  return function() config.set("keyboard." .. name, config.get("keyboard." .. name) ~= true) end
end
function M.swap_hand()
  config.set("keyboard.hand", config.get("keyboard.hand") == "left" and "right" or "left")
end
function M.both_hands() config.set("keyboard.hand", "both") end

--- The strip's tools, in order.
function M.tools()
  local wide = require("responsive").desk_width() >= require("responsive").MEDIUM
  local list = {
    { id = "clipboard", icon = "content_paste", name = "Clipboard", run = function() model.tray:set("clips") end },
    { id = "emoji", icon = "mood", name = "Emoji", on = function() return model.pane:get() == "emoji" end,
      run = function() model.show_pane(model.pane:get() == "emoji" and "keys" or "emoji") end },
    { id = "edit", icon = "text_select_move_forward_character", name = "Cursor keys", run = function() model.tray:set("edit") end },
    { id = "boards", icon = "dialpad", name = "Boards", run = function() model.tray:set("boards") end },
    { id = "language", label = function() return model.layout().short end, name = "Next language",
      run = model.next_language },
    { id = "hand", icon = "back_hand", name = "One hand", on = function() return config.get("keyboard.hand") ~= "both" end,
      run = function()
        if config.get("keyboard.hand") == "both" then
          config.set("keyboard.floating", false)
          config.set("keyboard.hand", "right")
        else M.both_hands() end
      end },
    { id = "floating", icon = "picture_in_picture_alt", name = "Floating",
      on = function() return config.get("keyboard.floating") == true end, run = flip("floating") },
  }
  if wide then
    list[#list + 1] = { id = "split", icon = "vertical_split", name = "Split",
      on = function() return config.get("keyboard.split") == true end, run = flip("split") }
  end
  list[#list + 1] = { id = "private", icon = "visibility_off", name = "Private typing",
    on = function() return model.private:get() end, run = function() model.private:set(not model.private:get()) end }
  if #config.get("keyboard.voice") > 0 then
    list[#list + 1] = { id = "voice", icon = "mic", name = "Voice typing", on = function() return M.listening:get() end,
      run = M.listen }
  end
  list[#list + 1] = { id = "settings", icon = "settings", name = "Keyboard settings", run = function()
    local sidebar = require("sidebar")
    require("utilities").request("keyboard")
    sidebar.select("settings")
    sidebar.drawer.set(true)
  end }
  list[#list + 1] = { id = "hide", icon = "keyboard_hide", name = "Hide", run = function() M.set(false) end }
  return list
end

M.listening = morf.signal("eva.keyboard.listening", false)
--- Runs the person's `keyboard.voice` command and types what it prints.
function M.listen()
  if M.listening:get() then return end
  M.listening:set(true)
  local ok = pcall(morf.process.run, config.get("keyboard.voice"), {}, function(result)
    M.listening:set(false)
    local text = result.ok and (result.stdout or ""):gsub("%s+$", "") or ""
    if text ~= "" then typing.paste(text) end
  end)
  if not ok then M.listening:set(false) end
end

--- The boards to pick by hand, for the strip of the board `keys`.
function M.boards(keys)
  local function board(mode, icon, name)
    return { id = "board-" .. mode, icon = icon, name = name, on = function() return keys.mode:get() == mode end,
      run = function()
        model.tray:set("words")
        M.show(mode)
      end }
  end
  return {
    { id = "boards-back", icon = "chevron_left", name = "Back", run = function() model.tray:set("words") end },
    board("full", "keyboard", "Letters"), board("dev", "terminal", "Terminal"),
    board("numbers", "pin", "Numbers"), board("phone", "dialpad", "Dial pad"),
  }
end

--- The cursor keys and the edit commands, for the strip.
function M.editing()
  local function key(name) return function() M.move(name) end end
  local function chord(letter)
    return function()
      deliver { text = letter, mods = { ctrl = true } }
      if not model.known() then model.forget() end
    end
  end
  return {
    { id = "edit-back", icon = "chevron_left", name = "Back", run = function() model.tray:set("words") end },
    { id = "edit-left", icon = "arrow_back", name = "Left", run = key("left") },
    { id = "edit-down", icon = "arrow_downward", name = "Down", run = key("down") },
    { id = "edit-up", icon = "arrow_upward", name = "Up", run = key("up") },
    { id = "edit-right", icon = "arrow_forward", name = "Right", run = key("right") },
    { id = "edit-home", icon = "first_page", name = "Start of the line", run = key("home") },
    { id = "edit-end", icon = "last_page", name = "End of the line", run = key("end") },
    { id = "edit-all", icon = "select_all", name = "Select all", run = chord("a") },
    { id = "edit-copy", icon = "content_copy", name = "Copy", run = chord("c") },
    { id = "edit-paste", icon = "content_paste", name = "Paste", run = chord("v") },
  }
end

-- The handle: a finger down it pulls the keyboard shut, or carries it about
-- while it floats.
local grab
function M.handle_down(x, y)
  grab = { x = x, y = y, at = y, speed = 0, clock = morf.time.elapsed(), float_x = config.get("keyboard.float_x"),
    float_y = config.get("keyboard.float_y"), pulled = false }
end
local float_at = morf.signal("eva.keyboard.float", { x = config.get("keyboard.float_x"), y = config.get("keyboard.float_y") })

local view = {}
local function room()
  local w, h = require("responsive").size()
  return math.max(1, w - view.width()), math.max(1, h - view.height())
end
function M.handle_move(x, y)
  if not grab then return end
  if view.floating() then
    local free_x, free_y = room()
    float_at:set { x = math.max(0, math.min(1, grab.float_x + (x - grab.x) / free_x)),
      y = math.max(0, math.min(1, grab.float_y + (y - grab.y) / free_y)) }
    return
  end
  local pull = y - grab.y
  if not grab.pulled then
    if pull < 4 then return end
    grab.pulled = M.drawer.begin_drag()
  end
  local dt = math.max(1, grab.clock:elapsed_ms())
  grab.speed = (y - grab.at) * 1000 / dt
  grab.at = y
  grab.clock = morf.time.elapsed()
  M.drawer.drag_by(pull)
end
function M.handle_up()
  if not grab then return end
  local done = grab
  grab = nil
  if view.floating() then
    local at = float_at:get()
    config.set("keyboard.float_x", at.x)
    config.set("keyboard.float_y", at.y)
  elseif done.pulled then
    M.drawer.end_drag(done.speed)
    if not M.drawer.open:get() then remember(false) end
  end
end

for name, part in pairs(require("themes").view("keyboard").build(M)) do view[name] = part end
M.keys, M.WIDTH = view.keys, view.width
M.drawer = require("drawer").new {
  name = "keyboard", edge = view.edge or "bottom", width = view.width,
  height = view.height, content = view.content, props = view.props,
}
-- It belongs to the physical bottom edge, outside the shrinking desktop.
M.drawer.docked = true
-- A role on the real laid-out panel, never a caller-supplied rectangle.
M.drawer.panel.input_context = function()
  return { role = "keyboard", layout = M.keys.mode:get() }
end
-- Floating, it leaves the edge: drawn where it was left, rounded all round, a
-- box of its own in the frame's field that melts into the frame near an edge.
M.drawer.panel.transform_matrix = function()
  if not view.floating() then return { 1, 0, 0, 1, 0, 0 } end
  local free_x, free_y = room()
  local at = float_at:get()
  return { 1, 0, 0, 1, (at.x - .5) * free_x, (at.y - 1) * free_y }
end
do
  local shape, round = M.drawer.shape, require("theme").ROUNDING
  local function corner() return view.floating() and round or 0 end
  shape.bottom_left_radius, shape.bottom_right_radius = corner, corner
  morf.effect("eva.keyboard.floating", function()
    shape.track = view.floating() and M.drawer.panel or M.drawer.backing
  end)
end
morf.effect("eva.keyboard.reserve",function()
  require("themes.keyboard").inset:set((M.drawer.open:get() and not view.floating())
    and math.ceil(view.height()+require("theme").BORDER) or 0)
end)

typing = require("keyboard_typing").new {
  keys = M.keys, deliver = deliver, delete = delete_before,
  set_clipboard = function(text)
    if not dry() then pcall(morf.clipboard.set, text) end
  end,
}

local asked = false
-- A board picked by hand stays until the keyboard goes.
local chosen = false
function M.set(on)
  asked = false
  if not on then chosen = false end
  remember(on)
  M.drawer.set(on)
end
function M.toggle() M.set(not M.drawer.open:get()) end
function M.show(mode)
  local valid = mode == nil
  for _, name in ipairs(osk.MODES) do if mode == name then valid = true end end
  if not valid then return false end
  asked = false
  if mode then
    M.keys.mode:set(mode)
    chosen = true
  end
  M.keys.reset()
  M.set(true)
  return true
end

-- The board the focused field calls for.
local function fit_board()
  if chosen then return end
  local mode = model.intent().mode
  if M.keys.mode:get() ~= mode then M.keys.mode:set(mode) end
end

local function auto_show()
  if suppressed(application()) then
    asked = false
    M.drawer.set(false)
    return
  end
  if field then fit_board() end
  if config.get("keyboard.auto") == false then return end
  if field then
    if not M.drawer.open:get() and not keyboards.attached() then
      asked = true
      M.keys.reset()
      M.drawer.set(true)
    end
  elseif asked then
    asked = false
    M.drawer.set(false)
  end
end
local function hear_field(active, text, cursor, anchor, _, purpose, hints)
  field = active == true
  model.update(field, text, cursor, anchor, purpose, hints)
  auto_show()
end
if morf.input_method and morf.input_method.subscribe then
  pcall(morf.input_method.subscribe, hear_field)
end
-- A text-capable app can replace another without an IME inactive/active
-- pair. Recheck on app changes too, including a keyboard left open in Firefox
-- when returning to Kitty. Automatic closes never become a user preference.
local previous_app, previous_hidden
morf.effect("eva.keyboard.application", function()
  local app = application()
  local blocked = suppressed(app)
  model.app:set(app or "")
  if app == previous_app and blocked == previous_hidden then return end
  previous_app, previous_hidden = app, blocked
  auto_show()
end)
morf.effect("eva.keyboard.hand", function()
  local on = M.drawer.open:get()
  M.opened:set(on)
  if not on then asked = false end
  require("keyboard_clips").follow(on)
  if on then predict.prepare() else model.leave() end
end)
morf.effect("eva.keyboard.purpose", function()
  model.purpose()
  if field and M.drawer.open:get() then fit_board() end
end)
morf.effect("eva.keyboard.language", function()
  if M.drawer.open:get() then predict.prepare() end
end)
morf.effect("eva.keyboard.offers", function()
  model.revision:get()
  require("lib.shell.words").revision:get()
  local offers = {}
  if M.drawer.open:get() then offers = predict.offers(M.keys.mode:get()) end
  model.candidates:set(offers)
end)
-- A capital at the start of a sentence: shift taken once, and let go again if
-- the cursor moves away. A change of mind about shift stays until the cursor moves.
do
  local done, ours = "", false
  morf.effect("eva.keyboard.capitals", function()
    local stamp = model.revision:get() .. "/" .. tostring(M.drawer.open:get()) .. "/" .. M.keys.mode:get()
      .. "/" .. M.keys.page:get()
    local shift = M.keys.shift:get()
    if stamp == done then return end
    done = stamp
    local want = M.drawer.open:get() and config.get("keyboard.autocaps") == true and model.known()
      and M.keys.page:get() == "letters" and model.aids(M.keys.mode:get()) and model.sentence_start()
    if want and shift == "off" then
      M.keys.shift:set("once")
      ours = true
    elseif not want and shift == "once" and ours then
      M.keys.shift:set("off")
      ours = false
    elseif shift ~= "once" then
      ours = false
    end
  end)
end

--- `keyboard VERB VALUE` over IPC: what a tool of eva's own, a key binding or a
--- scenario says. Nil for a verb that is not one of these.
function M.control(verb, value)
  if verb == "purpose" then return model.ask(value) end
  if verb == "language" then
    if value == "next" then model.next_language() return true end
    return model.use_language(value)
  end
  if verb == "pane" then model.show_pane(value) return true end
  if verb == "tray" then model.tray:set(value) return true end
  if verb == "hand" then config.set("keyboard.hand", value) return true end
  if verb == "floating" or verb == "split" or verb == "private" then
    local now = value == "on"
    if verb == "private" then model.private:set(now) else config.set("keyboard." .. verb, now) end
    return now
  end
  local fake = morf.env("EVA_FAKE_IME")
  if fake and fake ~= "" and fake ~= "0" then
    if verb == "field" then
      hear_field(value ~= "off", value ~= "off" and value or nil, value and #value or 0, value and #value or 0)
      return true
    end
    if verb == "type" then
      for _, cp in utf8.codes(value, true) do M.strike { text = utf8.char(cp), mods = {} } end
      return true
    end
    if verb == "pick" then
      local offer = model.candidates:get()[tonumber(value) or 1]
      if offer then M.pick(offer) end
      return offer ~= nil
    end
    if verb == "read" then return { before = model.before(), known = model.known(), shift = M.keys.shift:get() } end
  end
  return nil
end
return M
