-- The page of a tool that draws over the whole screen, in the Tools window: what
-- it does, the choices it starts with, the controls that start it, and the keys
-- it answers to while it runs. Starting shuts the window first, so the tool has
-- the screen to itself, then runs the tool's own program, as its command does.
--
--     local overlay = require("apps.common.overlay_page")
--     overlay.build({ id = "find", text = "...",
--       choices = { { id = "find-mode", title = "It shows", items = { { key, icon, name } }, value = signal } },
--       starts = { { id = "find-start", label = "Show the pointer", icon = "my_location",
--         run = function() overlay.start("find", { "--" .. mode:get() }) end } },
--       keys = { { "Escape", "ends it" } } }, w, h)
local morf = require("morf")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}

-- How long the window takes to leave the screen, and a little more.
local LEAVE = theme.duration.normal + 150

--- Shuts the Tools window, then, once it has left the screen, does `action`.
function M.after_window(action)
  require("tools_model").close()
  morf.time.timer(LEAVE, action, false)
end

--- Shuts the Tools window and starts tool `name`'s program with `words`, as
--- `eva-NAME WORDS` does.
function M.start(name, words)
  M.after_window(function() require("lib.services.host").start_tool(name, words) end)
end

--- The page, `w` by `h`: `id`, `text` (what the tool does), `choices` (each
--- `{ id, title, items, value }`, `value` a signal of the chosen key), `starts`
--- (P.button specs, the first filled), `keys` (`{ key, what }` rows) and
--- `extra` (nodes under the choices).
function M.build(spec, w, h)
  local inner = P.inner(w)
  local blocks = { id = spec.id .. "-page", width = w, height = h,
    P.section { id = spec.id .. "-about", width = w, F.note(inner, spec.text, { id = spec.id .. "-text" }) } }
  for _, choice in ipairs(spec.choices or {}) do
    blocks[#blocks + 1] = P.section { id = choice.id .. "-section", width = w, title = choice.title,
      F.choices { id = choice.id, width = inner, per_row = choice.per_row or #choice.items, items = choice.items,
        now = function() return choice.value:get() end, pick = function(key) choice.value:set(key) end } }
  end
  for _, node in ipairs(spec.extra or {}) do blocks[#blocks + 1] = node end
  local buttons = { width = w }
  for index, start in ipairs(spec.starts) do
    local button = {}
    for key, value in pairs(start) do button[key] = value end
    button.on_clicked = start.run
    button.tone = index == 1 and "primary" or nil
    buttons[#buttons + 1] = button
  end
  blocks[#blocks + 1] = P.buttons(buttons)
  if spec.keys and #spec.keys > 0 then
    local keys = { id = spec.id .. "-keys", width = w, title = "While it runs" }
    for index, row in ipairs(spec.keys) do
      keys[#keys + 1] = F.fact { id = spec.id .. "-key-" .. index, width = inner, icon = row[3] or "keyboard",
        title = row[1], subtitle = row[2] }
    end
    blocks[#blocks + 1] = P.section(keys)
  end
  return P.page(blocks)
end

return M
