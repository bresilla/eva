-- Where eva-clipboard keeps its history, for whoever reads it: the tool itself,
-- and the shell's on-screen keyboard. Nothing here writes.
local morf = require("morf")

local M = {}

--- The private folder the history lives in.
function M.folder()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/clipboard"
end

--- The history's index.
function M.index() return M.folder() .. "/history.json" end

--- The entries on disk, newest first and pins on top; nil when none can be read.
function M.read()
  local ok, list = pcall(function() return morf.json.decode(morf.fs.read(M.index())) end)
  if ok and type(list) == "table" then return list end
  return nil
end

return M
