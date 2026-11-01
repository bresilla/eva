-- What can be asked of a connection: is it behind a sign-in page, where does
-- it stop working, and how fast is it. Every outside address is named here and
-- nowhere else, and the pages say each one before it is used. Nothing here runs
-- by itself: shell/net_portal.lua and shell/net_help_model.lua decide when.
--
--   net_check.probe(server, function(state, login) end)  -- "online", "portal", "offline"
--   net_check.diagnose(net, server, on_step, done)       -- link, address, gateway, DNS, internet
--   net_check.speed(on_phase, done)                      -- latency, download, upload
local host = require("lib.services.host")
local connection = require("lib.services.connection")
local morf = require("morf")

local M = {}

-- The servers a sign-in check asks, the same ones browsers and desktops ask.
-- `answer` is what the real server says; a network that says anything else
-- stands in the way.
M.SERVERS = {
  gnome = { name = "GNOME", host = "nmcheck.gnome.org", url = "http://nmcheck.gnome.org/check_network_status.txt",
    answer = "NetworkManager is online" },
  mozilla = { name = "Mozilla", host = "detectportal.firefox.com", url = "http://detectportal.firefox.com/success.txt",
    answer = "success" },
  google = { name = "Google", host = "connectivitycheck.gstatic.com", url = "http://connectivitycheck.gstatic.com/generate_204",
    status = 204 },
}
M.SERVER_ORDER = { "gnome", "mozilla", "google" }

M.SPEED = { name = "Cloudflare", host = "speed.cloudflare.com", base = "https://speed.cloudflare.com",
  down_bytes = 25000000, up_bytes = 10000000, pings = 5 }

M.PROBE_MS, M.SPEED_MS = 6000, 60000

M.STEPS = { { "link", "Link", "wifi" }, { "address", "Address", "lan" }, { "gateway", "Router", "router" },
  { "dns", "Names (DNS)", "dns" }, { "internet", "Internet", "public" } }

--- The server named `key`, the first one if there is no such server.
function M.server(key) return M.SERVERS[key] or M.SERVERS[M.SERVER_ORDER[1]] end

local function host_of(url) return tostring(url or ""):match("^%a+://([^/:]+)") or "" end

--- What an answer says: "online", "portal" and where to sign in, or "offline".
function M.read_answer(server, response)
  if not response or (response.status or 0) == 0 then return "offline" end
  local final = response.url or server.url
  if host_of(final) ~= server.host then return "portal", final end
  if server.status then
    if response.status == server.status then return "online" end
    return "portal", final
  end
  if tostring(response.body or ""):find(server.answer, 1, true) then return "online" end
  return "portal", final
end

--- Asks `server` once: `done(state, login)`. Gives what `cancel` stops it.
function M.probe(server, done)
  return host.http({ url = server.url, timeout_ms = M.PROBE_MS, max_bytes = 65536 }, function(response)
    done(M.read_answer(server, response))
  end)
end

-- ------------------------------------------------------------- troubleshoot --

local function link_of(net)
  if not net or not net.state or not net.state.available then
    return nil, "NetworkManager is not running, so eva cannot see any network."
  end
  local state = net.state
  if state.wifi.connected then
    return state.wifi.device, ("Joined to %s, signal %d%%."):format(state.wifi.ssid, state.wifi.strength or 0)
  end
  if state.wired.connected then return state.wired.device, "A cable is plugged in and working." end
  local devices = state.devices
  for index = 1, devices:len() do
    local row = devices:get(index)
    if row.state == "activated" and row.type ~= "loopback" then return row.interface, "Connected through " .. row.interface .. "." end
  end
  if state.wired.device ~= "" and state.wired.carrier then return nil, "A cable is plugged in, but it did not connect." end
  if not state.wifi_enabled then return nil, "Wi-Fi is off and no cable is connected. Turn Wi-Fi on." end
  return nil, "Wi-Fi is on but not joined to a network. Pick one on the Network page."
end

local function address_of(raw)
  local value = (raw["IP4.ADDRESS"] or {})[1] or ""
  return value:match("^[^/]+") or ""
end

local function gateway_of(raw)
  local value = raw["IP4.GATEWAY"] or ""
  return value ~= "--" and value or ""
end

--- Walks the steps in order, telling `step(name, state, words)` as each
--- starts ("running") and ends ("ok", "unsure", "failed", "skipped"). Then
--- `done(verdict)`: `{ failed, words, login }`. Gives a function that stops it.
function M.diagnose(net, server, step, done)
  local stopped = false
  local verdict = {}
  local running
  local function fail(name, words)
    step(name, "failed", words)
    if not verdict.failed then verdict.failed, verdict.words = name, words end
  end
  local function skip(from)
    local past = false
    for _, row in ipairs(M.STEPS) do
      past = past or row[1] == from
      if past then step(row[1], "skipped", "Not tried.") end
    end
    done(verdict)
  end
  local function finish()
    if not verdict.failed then verdict.words = "Your connection works." end
    done(verdict)
  end

  local function internet()
    step("internet", "running", "Asking " .. server.host .. "…")
    running = M.probe(server, function(state, login)
      if stopped then return end
      if state == "online" then
        step("internet", "ok", server.host .. " answered.")
      elseif state == "portal" then
        fail("internet", "This network wants you to sign in before it lets you online.")
        verdict.login = login
      else
        fail("internet", "Your router works, but nothing past it answers. The fault is with the network or your provider.")
      end
      finish()
    end)
  end

  local function dns(gateway_unsure, servers)
    step("dns", "running", "Looking up " .. server.host .. "…")
    host.read({ "getent", "ahostsv4", server.host }, function(text)
      if stopped then return end
      if text and text ~= "" then
        step("dns", "ok", "Names resolve" .. (servers ~= "" and (", through " .. servers) or "") .. ".")
        return internet()
      end
      if gateway_unsure then
        step("gateway", "failed", gateway_unsure)
        verdict.failed, verdict.words = "gateway", gateway_unsure
        step("dns", "failed", "Names do not resolve either.")
        return skip("internet")
      end
      fail("dns", "Your router answers, but names do not resolve. The DNS servers" ..
        (servers ~= "" and (" (" .. servers .. ")") or "") .. " are not answering. Try others on the Connection page.")
      skip("internet")
    end, { timeout_ms = 8000 })
  end

  local function gateway(address, value, servers)
    if value == "" then
      fail("gateway", "This network gave no route out, so nothing past this machine can be reached.")
      return skip("dns")
    end
    if not host.installed("ping") then
      step("gateway", "unsure", "ping is not installed, so the router was not tried.")
      return dns(nil, servers)
    end
    step("gateway", "running", "Trying the router at " .. value .. "…")
    host.read({ "ping", "-c", "2", "-W", "1", "-q", value }, function(text)
      if stopped then return end
      if text then
        step("gateway", "ok", "The router at " .. value .. " answers.")
        return dns(nil, servers)
      end
      local words = "The router at " .. value .. " is not answering."
      step("gateway", "unsure", "The router at " .. value .. " did not answer a ping. Some routers ignore it.")
      dns(words, servers)
    end, { timeout_ms = 6000 })
    return address
  end

  local function address(device)
    step("address", "running", "Reading the address…")
    host.read({ "nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", device }, function(text)
      if stopped then return end
      local raw = connection.parse_terse(text or "")
      local value = address_of(raw)
      if value == "" then
        fail("address", "This machine got no address. The router did not hand one out over DHCP.")
        return skip("gateway")
      end
      if value:match("^169%.254%.") then
        fail("address", "This machine gave itself the address " .. value .. " because the router did not hand one out.")
        return skip("gateway")
      end
      step("address", "ok", "This machine is " .. value .. ".")
      gateway(value, gateway_of(raw), table.concat(raw["IP4.DNS"] or {}, ", "))
    end)
  end

  step("link", "running", "Looking for a network…")
  local device, words = link_of(net)
  if not device then
    fail("link", words)
    skip("address")
  else
    step("link", "ok", words)
    address(device)
  end
  return function()
    stopped = true
    if running then running:cancel() end
  end
end

-- ------------------------------------------------------------------- speed --

local function now_ms() return morf.time.now_ms() end

local function mbps(bytes, ms) return ms > 0 and (bytes * 8 / 1000) / ms or 0 end

--- A test a person started: `phase(name)` as it moves ("latency", "download",
--- "upload"), `done(result, why)` with `{ latency, jitter, down, up }`, ms and
--- Mbit/s. Gives a function that stops it.
function M.speed(phase, done)
  local stopped, current = false, nil
  local base = M.SPEED.base
  local result = {}
  local function failed(response)
    done(nil, tostring(response and response.error or ("answered " .. tostring(response and response.status))))
  end
  local function upload()
    phase("upload")
    local body = string.rep("0", M.SPEED.up_bytes)
    local from = now_ms()
    current = host.http({ url = base .. "/__up", method = "POST", body = body, timeout_ms = M.SPEED_MS }, function(response)
      if stopped then return end
      if not response.ok then return failed(response) end
      result.up = mbps(M.SPEED.up_bytes, response.took_ms or (now_ms() - from))
      done(result)
    end)
  end
  local function download()
    phase("download")
    local from = now_ms()
    current = host.http({ url = base .. "/__down?bytes=" .. M.SPEED.down_bytes, timeout_ms = M.SPEED_MS,
      max_bytes = M.SPEED.down_bytes + 65536 }, function(response)
      if stopped then return end
      if not response.ok then return failed(response) end
      result.down = mbps(response.bytes or #(response.body or ""), response.took_ms or (now_ms() - from))
      upload()
    end)
  end
  local samples = {}
  local function ping()
    local from = now_ms()
    current = host.http({ url = base .. "/__down?bytes=0", timeout_ms = M.PROBE_MS }, function(response)
      if stopped then return end
      if not response.ok then return failed(response) end
      samples[#samples + 1] = response.took_ms or (now_ms() - from)
      if #samples < M.SPEED.pings then return ping() end
      -- The first holds the connection's setup; the rest are the wire.
      table.remove(samples, 1)
      local least, spread = math.huge, 0
      for _, ms in ipairs(samples) do least = math.min(least, ms) end
      for _, ms in ipairs(samples) do spread = spread + (ms - least) end
      result.latency, result.jitter = least, spread / #samples
      download()
    end)
  end
  phase("latency")
  ping()
  return function()
    stopped = true
    if current then current:cancel() end
  end
end

return M
