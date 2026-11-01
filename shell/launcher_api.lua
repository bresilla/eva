-- The launcher as a plugin sees it, by `require("eva.launcher")`. A plugin
-- registers and returns nothing.
--
--   local launcher = require("eva.launcher")
--   launcher.mode {
--     id = "ip", name = "Address", material = "public", words = { "ip" },
--     search = function(term)
--       return { launcher.copy("ip", "192.0.2.1", "This machine", "public") }
--     end,
--   }
--   launcher.entry { id = "nas", name = "Open the NAS", run = function() return launcher.open("smb://nas") end }
--   launcher.on.chosen(function(row, query) end)
local registry = require("lib.shell.launcher.registry")
local index = require("lib.shell.launcher.search_index")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")

local M = {}

--- Adds a mode, or replaces the one with its `id`; see
--- lib/shell/launcher/registry.lua for its fields.
function M.mode(mode) registry.mode(mode) end

--- Adds something plain searches find; see
--- lib/shell/launcher/search_index.lua for its fields.
function M.entry(entry)
  entry.kind = entry.kind or "menu"
  entry.tag = entry.tag or "Plugin"
  index.register(entry)
end

M.row, M.note, M.copy, M.file = rows.row, rows.note, rows.copy, rows.file
M.fuzzy = rows.fuzzy

--- Asks a program without holding the search up: `ask(slot, question, argv,
--- parse, options)` is nil and false until it answers, and the search runs again
--- when it does.
M.ask = rows.ask_run

M.start, M.open, M.browse, M.terminal, M.clip, M.paste = run.start, run.open, run.browse, run.terminal, run.copy, run.paste

local chosen = {}

--- What happens as something is picked.
M.on = {}

--- `fn(row, query)` runs after a result is chosen.
function M.on.chosen(fn) chosen[#chosen + 1] = fn end

--- Tells every listener `row` was chosen; a listener that raises is logged and
--- the rest still hear it.
function M.chosen(row, query)
  for _, fn in ipairs(chosen) do
    local ok, why = pcall(fn, row, query)
    if not ok then require("morf").log("warn", "eva: a launcher plugin raised: " .. tostring(why)) end
  end
end

return M
