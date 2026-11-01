-- Script commands: every executable in $XDG_CONFIG_HOME/eva/scripts is a launcher
-- command, described by comment lines at its head.
--
--   #!/bin/sh
--   # @eva.title Restart the audio
--   # @eva.description Brings PipeWire back
--   # @eva.icon restart_alt
--   # @eva.mode silent        silent, terminal, copy or notify
--   # @eva.argument a name    Return asks for this before it runs
--   # @eva.confirm true       Return twice
--
-- `silent` runs it, `terminal` runs it in a terminal, `copy` copies what it
-- prints, and `notify` shows what it prints.

local morf = require("morf")

local M = {}

local HEAD = 2048

--- The folder scripts live in.
function M.folder()
  local base = (morf.env and morf.env("XDG_CONFIG_HOME")) or (morf.fs.home() .. "/.config")
  return base .. "/eva/scripts"
end

--- What the head of a script says of it.
function M.parse(text, file)
  local meta = {}
  for key, value in text:sub(1, HEAD):gmatch("@eva%.([%w_]+)[ \t]+([^\r\n]*)") do
    meta[key] = (value:gsub("%s+$", ""))
  end
  local name = (file or ""):gsub("%.%w+$", ""):gsub("[-_]", " ")
  return {
    title = meta.title or name, description = meta.description or "", icon = meta.icon or "terminal",
    mode = meta.mode or "silent", argument = meta.argument, confirm = meta.confirm == "true",
  }
end

--- The scripts in the folder: each `{ path, file, title, ... }`.
function M.scan()
  local out = {}
  local ok, entries = pcall(morf.fs.list, M.folder())
  if not ok or type(entries) ~= "table" then return out end
  for _, e in ipairs(entries) do
    local stat = e.is_file and morf.fs.stat(e.path)
    if stat and ((stat.mode or 0) & 73) ~= 0 then
      local fine, text = pcall(morf.fs.read, e.path)
      local script = M.parse(fine and type(text) == "string" and text or "", e.name)
      script.path, script.file = e.path, e.name
      out[#out + 1] = script
    end
  end
  table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
  return out
end

return M
