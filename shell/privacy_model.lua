-- The Privacy and Firewall pages, and the record of what used the microphone
-- lately. Portal permissions cover sandboxed apps only, which the page says.
local morf = require("morf")
local config = require("config")
local permissions = require("lib.services.permissions")
local firewall = require("lib.services.firewall")
local host = require("lib.services.host")
local page_model = require("page_model")

local M = {}

local KEEP = 24
local recent = morf.signal("eva.privacy.recent", {})
local noted = {}

local function history_path() return morf.paths.state("eva/privacy-recent.json") end

local function load_history()
  local ok, value = pcall(function() return morf.json.decode(morf.fs.read(history_path())) end)
  if ok and type(value) == "table" then recent:set(value) end
end

local function note(kind, app)
  if noted[kind .. app] then return end
  noted[kind .. app] = true
  local rows = { { kind = kind, app = app, at = morf.time.now() } }
  for _, row in ipairs(recent:get()) do
    if #rows < KEEP and not (row.kind == kind and row.app == app) then rows[#rows + 1] = row end
  end
  recent:set(rows)
  if not host.dry() then
    local path = history_path()
    pcall(morf.fs.mkdir, (path:gsub("/[^/]+$", "")))
    pcall(morf.fs.write, path, morf.json.encode(rows))
  end
end

--- Notes each app as it starts recording, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  load_history()
  local audio = morf.audio
  if not audio or not audio.streams then return end
  morf.effect("eva.privacy.watch", function()
    local ok, count = pcall(function() return audio.available() and audio.streams:len() or 0 end)
    local seen = {}
    for index = 1, ok and count or 0 do
      local row = audio.streams:get(index)
      if row and row.direction ~= "playback" then
        local app = row.app_name or row.binary or "App"
        seen["microphone" .. app] = true
        note("microphone", app)
      end
    end
    for key in pairs(noted) do if not seen[key] then noted[key] = nil end end
  end)
end

function M.new(active)
  local model = page_model.new("privacy", active)
  model.KINDS = permissions.KINDS
  local rows = morf.signal("eva.privacy.rows", {})
  local missing = morf.signal("eva.privacy.missing", false)
  model.selected = morf.signal("eva.privacy.selected", "location")

  local function read(kind)
    permissions.read(kind, function(list)
      if list.missing then missing:set(true) end
      local now = {}
      for key, value in pairs(rows:get()) do now[key] = value end
      now[kind.id] = list
      rows:set(now)
    end)
  end
  local function refresh() for _, kind in ipairs(permissions.KINDS) do read(kind) end end
  model.on_show(refresh)

  function model.missing() return missing:get() end
  function model.kind() return permissions.BY_ID[model.selected:get()] end
  function model.rows() return rows:get()[model.selected:get()] or {} end
  function model.count(kind) return #(rows:get()[kind.id] or {}) end
  function model.app_name(row) return permissions.app_name(row.app) end
  function model.set(row, on)
    local kind = model.kind()
    return model.action(function(done) permissions.set(kind, row, on, done) return true end, function() read(kind) end)
  end
  function model.forget(row)
    local kind = model.kind()
    return model.action(function(done) permissions.forget(kind, row, done) return true end, function() read(kind) end)
  end

  --- What used what lately, newest first: audio as it was seen, location from
  --- the store's own stamps.
  function model.recent()
    local out = {}
    for _, row in ipairs(recent:get()) do out[#out + 1] = row end
    for _, row in ipairs(rows:get().location or {}) do
      if row.used_at then out[#out + 1] = { kind = "location", app = permissions.app_name(row.app), at = row.used_at } end
    end
    table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return out
  end
  function model.when(at) return morf.time.format("%-d %b, %H:%M", at) end

  -- ------------------------------------------------------------ security --

  local security = morf.signal("eva.privacy.security", {})
  model.on_show(function()
    local fake = host.fake() and require("lib.services.host_fake")
    security:set(fake and fake.security() or M.read_security())
  end)
  function model.secure_boot() return security:get().secure_boot end
  function model.encrypted() return security:get().encrypted end
  function model.agent() return config.get("polkit.agent") ~= "off" end
  function model.set_agent(on) config.set("polkit.agent", on and "on" or "off") end
  function model.clear_recent()
    return model.action(function(done)
      if host.held("clear recent files") then done(true) return true end
      local path = (morf.env("XDG_DATA_HOME") or (morf.fs.home() .. "/.local/share")) .. "/recently-used.xbel"
      pcall(morf.fs.remove, path)
      done(true)
      return true
    end, function() model.say("Recent files cleared") end)
  end
  return model
end

--- Secure boot from its EFI variable, and whether the root filesystem sits on
--- an encrypted device. Either is nil where it cannot be told.
function M.read_security()
  local out = {}
  local ok, names = pcall(morf.fs.glob, "/sys/firmware/efi/efivars/SecureBoot-*")
  local path = ok and type(names) == "table" and names[1]
  if path then
    local read, bytes = pcall(morf.fs.read, path)
    if read and type(bytes) == "string" and #bytes > 0 then out.secure_boot = bytes:byte(#bytes) == 1 end
  end
  local mounts_ok, mounts = pcall(morf.fs.read, "/proc/mounts")
  local device = mounts_ok and tostring(mounts):match("\n(%S+) / ") or tostring(mounts):match("^(%S+) / ")
  local name = device and device:match("/dev/(dm%-%d+)")
  if device then
    if not name then
      local target_ok, target = pcall(morf.fs.read_link, device)
      name = target_ok and tostring(target):match("(dm%-%d+)") or nil
    end
    if name then
      local uuid_ok, uuid = pcall(morf.fs.read, "/sys/block/" .. name .. "/dm/uuid")
      out.encrypted = uuid_ok and tostring(uuid):find("^CRYPT%-") ~= nil
    else
      out.encrypted = false
    end
  end
  return out
end

--- The Firewall page.
function M.firewall(active)
  local model = page_model.new("firewall", active)
  local state = morf.signal("eva.firewall.state", { backend = "" })
  local function refresh() firewall.read(function(now) state:set(now) end) end
  model.on_show(refresh)
  function model.backend() return state:get().backend end
  function model.on() return state:get().on == true end
  function model.declarative() return state:get().declarative == true end
  function model.present() return state:get().backend ~= "" end
  function model.set(on)
    return model.action(function(done) firewall.set(state:get().backend, on, done) return true end, refresh)
  end
  return model
end

return M
