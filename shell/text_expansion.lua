-- Text expansion: a snippet's trigger, typed in any program that tells the
-- compositor what surrounds the cursor (text-input-v3), becomes the snippet. The
-- shell is the session's input method, so what it hears is the text as it stands;
-- it takes the trigger back out and commits the snippet in its place.
local morf = require("morf")
local snippets = require("lib.shell.launcher.snippets")

local M = {}

local function current_clipboard()
  local items = require("lib.shell.clipboard.store").items:get()
  return items[1] and items[1].text or ""
end

--- What the input method reports: the text around the cursor and where the
--- cursor stands, in bytes. Returns the snippet expanded, or nil.
function M.heard(active, surrounding, cursor, anchor)
  if not active or type(surrounding) ~= "string" or cursor ~= anchor then return nil end
  if not require("config").get("launcher.expansion") then return nil end
  local item = snippets.ending(surrounding:sub(1, cursor))
  if not item then return nil end
  local length = #item.trigger
  snippets.expand(item.text, current_clipboard(), function(text)
    morf.input_method.delete(length, 0)
    morf.input_method.commit(text)
  end)
  return item
end

--- Starts listening, on one screen: every screen's shell hears the same text.
function M.start()
  if not (morf.input_method and morf.input_method.subscribe) then return end
  if morf.window.primary and not morf.window.primary() then return end
  pcall(morf.input_method.subscribe, M.heard)
end

return M
