-- The files the shell and the capture tool tell each other through. Each display
-- has its own, in the session's private runtime folder.
local morf = require("morf")
local M = {}

local function folder() return (morf.env("XDG_RUNTIME_DIR") or "/tmp") .. "/eva/" end
local function display() return (morf.env("WAYLAND_DISPLAY") or "wayland-0"):match("[^/]+$") end

--- What the tool publishes: its panel, editor and recording.
function M.path() return folder() .. "capture-" .. display() .. ".json" end

--- Where the shell names its process.
function M.shell_path() return folder() .. "shell-" .. display() .. ".pid" end

return M
