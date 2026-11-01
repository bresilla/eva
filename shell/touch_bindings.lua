-- Which gesture does what, per form: every gesture the Settings page lists, the
-- defaults shell/config.lua stores under `gestures.<form>`, and what a person
-- chose. Plain data at the head, so config.lua can read it while it loads.
local M = {}

M.FORMS = { "desk", "tablet", "phone" }

-- Each gesture's `key` is what touch_gestures.key names it. `group` files it on
-- the page; `icon` is a picture of the motion.
M.GESTURES = {
  { key = "two_up_bottom", name = "Two fingers up from the bottom edge", group = "edge", icon = "arrow_upward" },
  { key = "two_down_top", name = "Two fingers down from the top edge", group = "edge", icon = "arrow_downward" },
  { key = "two_right_left", name = "Two fingers in from the left edge", group = "edge", icon = "arrow_forward" },
  { key = "two_left_right", name = "Two fingers in from the right edge", group = "edge", icon = "arrow_back" },
  { key = "two_down_keyboard", name = "Two fingers down on the keyboard", group = "edge", icon = "keyboard_hide" },
  { key = "three_up", name = "Three fingers up", group = "three", icon = "arrow_upward" },
  { key = "three_down", name = "Three fingers down", group = "three", icon = "arrow_downward" },
  { key = "three_left", name = "Three fingers left", group = "three", icon = "arrow_back" },
  { key = "three_right", name = "Three fingers right", group = "three", icon = "arrow_forward" },
  { key = "three_tap", name = "Three-finger tap", group = "three", icon = "touch_app" },
  { key = "three_hold", name = "Three fingers held", group = "three", icon = "touch_app" },
  { key = "three_pinch_in", name = "Three-finger pinch", group = "three", icon = "pinch" },
  { key = "three_pinch_out", name = "Three-finger spread", group = "three", icon = "pinch" },
  { key = "four_up", name = "Four fingers up", group = "four", icon = "arrow_upward" },
  { key = "four_down", name = "Four fingers down", group = "four", icon = "arrow_downward" },
  { key = "four_left", name = "Four fingers left", group = "four", icon = "arrow_back" },
  { key = "four_right", name = "Four fingers right", group = "four", icon = "arrow_forward" },
  { key = "four_tap", name = "Four-finger tap", group = "four", icon = "touch_app" },
  { key = "four_hold", name = "Four fingers held", group = "four", icon = "touch_app" },
  { key = "four_pinch_in", name = "Four-finger pinch", group = "four", icon = "pinch" },
  { key = "four_pinch_out", name = "Four-finger spread", group = "four", icon = "pinch" },
  { key = "five_up", name = "Five fingers up", group = "five", icon = "arrow_upward" },
  { key = "five_down", name = "Five fingers down", group = "five", icon = "arrow_downward" },
  { key = "five_left", name = "Five fingers left", group = "five", icon = "arrow_back" },
  { key = "five_right", name = "Five fingers right", group = "five", icon = "arrow_forward" },
  { key = "five_tap", name = "Five-finger tap", group = "five", icon = "touch_app" },
  { key = "five_pinch_in", name = "Five-finger pinch", group = "five", icon = "pinch" },
  { key = "five_pinch_out", name = "Five-finger spread", group = "five", icon = "pinch" },
}

M.GROUPS = {
  { id = "edge", name = "Two fingers" },
  { id = "three", name = "Three fingers" },
  { id = "four", name = "Four fingers" },
  { id = "five", name = "Five fingers" },
}

M.BY_KEY = {}
for _, gesture in ipairs(M.GESTURES) do M.BY_KEY[gesture.key] = gesture end

-- What each gesture does until a person says otherwise; the rest does nothing.
local COMMON = {
  two_up_bottom = "keyboard", two_down_keyboard = "keyboard", two_down_top = "quick_settings",
  three_up = "overview", three_down = "show_desktop",
  three_left = "workspace_next", three_right = "workspace_previous",
  four_up = "app_grid", four_left = "switch_app", four_right = "switch_app", four_tap = "launcher",
  five_pinch_in = "launcher", five_pinch_out = "show_desktop",
}
local BY_FORM = { phone = { three_up = "recents" }, tablet = { three_up = "recents" } }

--- The stored defaults for `form`, a value for every gesture.
function M.defaults(form)
  local out = {}
  for _, gesture in ipairs(M.GESTURES) do
    out[gesture.key] = (BY_FORM[form] or {})[gesture.key] or COMMON[gesture.key] or "none"
  end
  return out
end

local function config() return require("config") end

--- The form `form` means, this screen's when nil.
local function form_of(form) return form or require("responsive").form() end

--- What `key` does on `form`, an action's key.
function M.action(key, form)
  if not M.BY_KEY[key] then return "none" end
  return config().get("gestures." .. form_of(form) .. "." .. key) or "none"
end

function M.set(key, form, action)
  if M.BY_KEY[key] then config().set("gestures." .. form_of(form) .. "." .. key, action) end
end

--- The stored commands: an empty list of words for every gesture.
function M.commands()
  local out = {}
  for _, gesture in ipairs(M.GESTURES) do out[gesture.key] = {} end
  return out
end

--- The words of `key`'s custom command.
function M.command(key)
  local words = M.BY_KEY[key] and config().get("gestures.commands." .. key)
  return type(words) == "table" and words or {}
end

function M.set_command(key, words)
  if M.BY_KEY[key] then config().set("gestures.commands." .. key, words) end
end

--- Whether `key` on `form` stands as it came.
function M.is_default(key, form)
  form = form_of(form)
  return M.action(key, form) == M.defaults(form)[key]
end

--- Every gesture of `form` back as it came.
function M.reset(form)
  form = form_of(form)
  for key, action in pairs(M.defaults(form)) do config().set("gestures." .. form .. "." .. key, action) end
end

return M
