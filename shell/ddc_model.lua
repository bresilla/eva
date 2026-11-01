-- External screens' brightness, for the one level the shell has: shell/osd.lua
-- asks here first, and falls back to the backlight. No nodes.
--
-- EVA_DDC=1 is the NixOS module saying the bus may be touched
-- (`programs.eva.hardware.ddc.enable`); without it nothing here runs ddcutil, on
-- any machine, whatever is on PATH. I2C is slow and takes one speaker at a time:
-- a run goes through at once, and what a slider sends meanwhile collapses into
-- the latest value.
local morf = require("morf")
local config = require("config")
local host = require("lib.services.host")
local lib = require("lib.services.ddc")

local M = {}

-- `{ bus, connector, model, serial, current, max }`, by what ddcutil found.
M.displays = morf.signal("eva.ddc.displays", {})
-- How often a screen's own buttons are noticed, in ms.
M.POLL_MS = 60000

--- Whether this system lets the shell speak to monitors.
function M.allowed()
  if host.fake() then return host.installed("ddcutil") end
  local value = morf.env("EVA_DDC")
  return value ~= nil and value ~= "" and value ~= "0"
end

function M.available() return M.allowed() and config.get("displays.ddc") ~= false end

local function outputs()
  local list = require("windows_model").monitors()
  local name = require("services").output()
  for _, m in ipairs(list) do if m.name == name then return m end end
  return { name = name, description = "" }
end

--- This screen's display, or nil.
local function here()
  if not M.available() then return nil end
  return lib.find(M.displays:get(), outputs())
end

--- This screen's level, 0 to 100, or nil where the bus does not reach it.
function M.level()
  local row = here()
  if not row or not row.current then return nil end
  return row.current * 100 / math.max(1, row.max or 100)
end

local function update(bus, fields)
  local rows = {}
  for index, row in ipairs(M.displays:get()) do
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    if row.bus == bus then
      for key, value in pairs(fields) do copy[key] = value end
    end
    rows[index] = copy
  end
  M.displays:set(rows)
end

local function read(row)
  host.read(lib.read_args(row.bus), function(text)
    local current, max = lib.parse_vcp(text)
    if current then update(row.bus, { current = current, max = max }) end
  end)
end

--- Asks what displays there are and where each stands.
function M.refresh()
  if not M.available() then return end
  host.read(lib.detect_args(), function(text)
    local found = lib.parse_detect(text)
    local before = {}
    for _, row in ipairs(M.displays:get()) do before[row.bus] = row end
    for _, row in ipairs(found) do
      local was = before[row.bus]
      if was then row.current, row.max = was.current, was.max end
    end
    M.displays:set(found)
    for _, row in ipairs(found) do read(row) end
  end)
end

local sending, waiting = {}, {}

local function send(bus, value)
  sending[bus] = true
  host.act(lib.write_args(bus, value), function(_, why)
    sending[bus] = nil
    if why then morf.log("warn", "eva: ddcutil: " .. tostring(why)) end
    local next_value = waiting[bus]
    waiting[bus] = nil
    if next_value and next_value ~= value then send(bus, next_value) end
  end)
end

--- Sets this screen's level, 0 to 100: shown at once, sent as the bus allows.
--- False where the bus does not reach it.
function M.set(percent)
  local row = here()
  if not row then return false end
  local value = lib.raw(percent, row.max)
  update(row.bus, { current = value })
  if sending[row.bus] then waiting[row.bus] = value else send(row.bus, value) end
  return true
end

--- Every display, for the Displays page: `{ name, percent }`.
function M.rows()
  local out = {}
  for _, row in ipairs(M.displays:get()) do
    out[#out + 1] = { name = row.connector ~= "" and row.connector or row.model,
      model = row.model, percent = row.current and math.floor(row.current * 100 / math.max(1, row.max or 100) + .5) or nil }
  end
  return out
end

--- Finds the displays now, as screens come and go, and now and then for a
--- screen's own buttons.
function M.start()
  if not M.allowed() then return end
  morf.effect("eva.ddc.find", function()
    morf.window.screens_revision()
    config.get("displays.ddc")
    morf.time.timer(500, M.refresh, false)
  end)
  morf.time.timer(M.POLL_MS, function()
    for _, row in ipairs(M.displays:get()) do read(row) end
  end, true)
end

return M
