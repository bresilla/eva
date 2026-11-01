-- One connection's page, the Proxy page, and sharing a Wi-Fi network by code.
-- The page shows whichever connection Network or Wired asked for. A Wi-Fi
-- password goes from NetworkManager to the encoder without touching a signal.
local morf = require("morf")
local config = require("config")
local services = require("services")
local connection = require("lib.services.connection")
local host = require("lib.services.host")
local qr = require("lib.util.qr")
local page_model = require("page_model")

local M = {}

--- The connection the page is about: a saved profile's row.
M.target = morf.signal("eva.connection.target", {})

--- Asks for the page about the profile named `id` (an SSID or a profile's
--- id). False where there is none.
function M.open(settings, id)
  local net = services.net
  for _, row in ipairs(net and net.snapshot and net.snapshot().known or {}) do
    if row.id == id or row.ssid == id then
      M.target:set(row)
      return settings.request("network/connection")
    end
  end
  return false
end

function M.new(active)
  local model = page_model.new("network/connection", active)
  local details = morf.signal("eva.connection.details", {})
  model.target = M.target

  --- A page opened without a connection named shows the one in use.
  local function primary()
    local net = services.net
    local snapshot = net and net.snapshot and net.snapshot() or {}
    local active = net and net.state and net.state.primary or {}
    for _, row in ipairs(snapshot.known or {}) do
      if row.id == active.id then return row end
    end
    return (snapshot.known or {})[1]
  end
  local function refresh()
    local row = M.target:get()
    if not row.uuid then
      row = primary() or {}
      if row.uuid then M.target:set(row) end
    end
    if not row.uuid then details:set({}) return end
    connection.show(row.uuid, function(found) details:set(found or {}) end)
  end
  model.on_show(refresh)

  function model.details() return details:get() end
  function model.name() return details:get().id or M.target:get().id or "" end
  function model.wifi() return M.target:get().type == "802-11-wireless" end
  --- Saves `change`; a live connection takes it at once.
  function model.save(change)
    local row = M.target:get()
    return model.action(function(done)
      connection.modify(row.uuid, change, done, true)
      return true
    end, function() refresh() model.say("Saved") end)
  end
  function model.copy(text)
    local ok = pcall(morf.clipboard.set, text)
    model.say(ok and "Copied" or "Could not reach the clipboard", not ok)
  end
  return model
end

--- The code for the network `row` (an access point row) to `draw(code)`, never
--- kept. `fail(why)` hears why not.
function M.share(row, draw, fail)
  local net = services.net
  local known
  for _, each in ipairs(net and net.snapshot and net.snapshot().known or {}) do
    if each.ssid == row.ssid then known = each end
  end
  local function encode(password)
    qr.encode(connection.wifi_uri(row.ssid, row.security, password, row.hidden), "M", function(code, why)
      if not code then return fail(why) end
      draw(code)
    end)
  end
  if row.security == "open" or row.security == "owe" then return encode(nil) end
  if not known then return fail("This network is not saved here") end
  connection.secret(known.path, function(password, why)
    if not password then return fail(why) end
    encode(password)
  end)
end

-- ------------------------------------------------------------------ proxy --

local PROXY = { { "none", "block", "None" }, { "manual", "tune", "Manual" }, { "auto", "auto_mode", "Automatic" } }
local ENV = { http = { "http_proxy", "HTTP_PROXY" }, https = { "https_proxy", "HTTPS_PROXY" }, socks = { "all_proxy", "ALL_PROXY" } }

local function get(key) return config.get("proxy." .. key) or "" end

--- The environment file for a mode: names and values for new sessions.
function M.proxy_lines()
  local lines = {}
  if get("mode") ~= "manual" then return lines end
  for _, key in ipairs { "http", "https", "socks" } do
    local value = get(key)
    if value ~= "" then
      for _, name in ipairs(ENV[key]) do lines[#lines + 1] = name .. "=" .. value end
    end
  end
  if #lines > 0 and get("exclude") ~= "" then
    lines[#lines + 1] = "no_proxy=" .. get("exclude")
    lines[#lines + 1] = "NO_PROXY=" .. get("exclude")
  end
  return lines
end

--- Tells the session and new programs. `done(ok, why)`.
function M.apply_proxy(done)
  if host.held("proxy " .. get("mode")) then return done(true) end
  local root = morf.env("XDG_CONFIG_HOME") or (morf.fs.home() .. "/.config")
  local lines = M.proxy_lines()
  local path = root .. "/environment.d/90-eva-proxy.conf"
  morf.fs.mkdir(root .. "/environment.d")
  if #lines == 0 then pcall(morf.fs.remove, path)
  else
    local wrote, why = pcall(morf.fs.write, path, table.concat(lines, "\n") .. "\n")
    if not wrote then return done(nil, tostring(why)) end
  end
  if host.installed("gsettings") then
    local mode = get("mode")
    host.act({ "gsettings", "set", "org.gnome.system.proxy", "mode", mode })
    if mode == "auto" then host.act({ "gsettings", "set", "org.gnome.system.proxy", "autoconfig-url", get("pac") }) end
  end
  local argv = { "systemctl", "--user", #lines > 0 and "set-environment" or "unset-environment" }
  if #lines > 0 then
    for _, line in ipairs(lines) do argv[#argv + 1] = line end
  else
    for _, names in pairs(ENV) do argv[#argv + 1] = names[1] argv[#argv + 1] = names[2] end
  end
  host.act(argv, done)
end

function M.proxy(active)
  local model = page_model.new("network/proxy", active)
  model.MODES = PROXY
  function model.mode() return get("mode") end
  function model.value(key) return get(key) end
  function model.set(key, value) config.set("proxy." .. key, value) end
  function model.apply()
    return model.action(function(done) M.apply_proxy(done) return true end, function()
      model.say("Saved. Programs started from now on use it.")
    end)
  end
  return model
end

return M
