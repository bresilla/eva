-- eva-screenshot's page in the Tools window: what a screenshot takes, what
-- happens to it and after how long, and the controls that take one, record the
-- screen or open the capture panel with the rest. Each shuts the window first,
-- so the capture tool, a program of its own, sees the screen without it.
local morf = require("morf")
local overlay = require("apps.common.overlay_page")

local M = {}

local target = morf.signal("eva.tools.screenshot.target", "region")
local after = morf.signal("eva.tools.screenshot.after", "edit")
local delay = morf.signal("eva.tools.screenshot.delay", "0")

local function shoot()
  local words = { target:get(), "--" .. after:get() }
  if delay:get() ~= "0" then words[#words + 1] = "--delay" words[#words + 1] = delay:get() end
  overlay.start("screenshot", words)
end
local function record()
  overlay.after_window(function() require("capture").record(target:get()) end)
end
local function panel()
  overlay.after_window(function() require("capture").drawer.set(true) end)
end

--- The page, `w` by `h`.
function M.build(w, h)
  return overlay.build({ id = "screenshot",
    text = "Pictures and recordings of the screen, through the frozen selection. A screenshot opens in the editor, "
      .. "or goes to the clipboard, the captures folder or a pin over the windows. Recording uses the same target; "
      .. "the capture panel has the rest: reading text, a scrolling capture, a replay buffer.",
    choices = {
      { id = "screenshot-target", title = "Of", value = target, items = {
        { "region", "screenshot_region", "A region" }, { "window", "select_window", "A window" },
        { "screen", "fullscreen", "The screen" } } },
      { id = "screenshot-after", title = "Then", value = after, items = {
        { "edit", "edit", "Edit" }, { "copy", "content_copy", "Copy" }, { "save", "save", "Save" },
        { "pin", "push_pin", "Pin" } } },
      { id = "screenshot-delay", title = "After", value = delay, items = {
        { "0", "bolt", "At once" }, { "3", "timer_3", "3 s" }, { "5", "timer", "5 s" }, { "10", "timer_10", "10 s" } } },
    },
    starts = { { id = "screenshot-start", icon = "screenshot_region", label = "Take it", run = shoot },
      { id = "screenshot-record", icon = "fiber_manual_record", label = "Record", run = record },
      { id = "screenshot-panel", icon = "screenshot_monitor", label = "Capture panel", run = panel } } }, w, h)
end

M.verbs = {
  choose = function(what, value)
    local chosen = ({ target = target, after = after, delay = delay })[what]
    if not chosen then error("`" .. tostring(what) .. "`: target, after or delay") end
    chosen:set(value)
    return true
  end,
  shoot = function() shoot() return true end,
  record = function() record() return true end,
  panel = function() panel() return true end,
}

return M
