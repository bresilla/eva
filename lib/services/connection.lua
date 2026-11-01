-- One NetworkManager connection in depth: its addresses and DNS, whether it is
-- metered, and the code that shares a Wi-Fi network.
--
-- A profile is changed with `nmcli connection modify`. A Wi-Fi password is read
-- over the bus by `secret`, goes to its caller alone, and is encoded in this
-- process by lib/util/qr.lua.
local host = require("lib.services.host")
local dbus_client = require("lib.services.dbus")
local qr = require("lib.util.qr")

local M = {}

local NM = "org.freedesktop.NetworkManager"
local CONNECTION = NM .. ".Settings.Connection"
local SECURITY = "802-11-wireless-security"
local TIMEOUT = 10000

-- What `show` asks for, by the name nmcli gives it.
local FIELDS = { "connection.id", "connection.uuid", "connection.type", "connection.metered", "connection.autoconnect",
  "connection.dns-over-tls", "ipv4.method", "ipv4.addresses", "ipv4.gateway", "ipv4.dns", "ipv4.ignore-auto-dns",
  "ipv4.dns-search", "ipv6.method", "802-11-wireless.hidden", "802-11-wireless.cloned-mac-address" }
local LIVE = { "IP4.ADDRESS", "IP4.GATEWAY", "IP4.DNS", "IP6.ADDRESS", "GENERAL.DEVICES" }

--- `nmcli -t` lines as a table by key, `\:` undone; `IP4.ADDRESS[1]` and its
--- like as lists under `IP4.ADDRESS`.
function M.parse_terse(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local key, value = line:match("^([^:]+):(.*)$")
    if key then
      value = value:gsub("\\:", ":"):gsub("\\\\", "\\")
      local base = key:match("^(.-)%[%d+%]$")
      if base then
        out[base] = out[base] or {}
        table.insert(out[base], value)
      else
        out[key] = value
      end
    end
  end
  return out
end

local function clean(value)
  if value == nil or value == "--" or value == "" then return "" end
  return value
end

-- `connection.dns-over-tls` as `nmcli -t` prints it.
local DOT = { ["-1"] = "default", ["0"] = "no", ["1"] = "opportunistic", ["2"] = "yes" }

--- The DNS-over-TLS word for what nmcli printed: a number when terse, a word
--- otherwise.
function M.parse_dot(value)
  local word = tostring(value or ""):match("^%-?%d+")
  if word then return DOT[word] or "default" end
  return tostring(value or ""):match("%((%a+)%)") or tostring(value or ""):match("^%a+") or "default"
end

--- `done(details, err)`: the profile `uuid` as a plain table.
function M.show(uuid, done)
  local keys = {}
  for index, key in ipairs(FIELDS) do keys[index] = key end
  for _, key in ipairs(LIVE) do keys[#keys + 1] = key end
  host.read({ "nmcli", "-t", "-f", table.concat(keys, ","), "connection", "show", uuid }, function(text, why)
    if not text then return done(nil, why) end
    local raw = M.parse_terse(text)
    local dns = raw["IP4.DNS"] or {}
    local method = raw["ipv4.method"] or "auto"
    done {
      id = clean(raw["connection.id"]), uuid = uuid, type = clean(raw["connection.type"]),
      metered = clean(raw["connection.metered"]):match("^%a+") or "unknown",
      autoconnect = raw["connection.autoconnect"] ~= "no", dot = M.parse_dot(raw["connection.dns-over-tls"]),
      method = method, static = method == "manual",
      address = clean(raw["ipv4.addresses"]), gateway = clean(raw["ipv4.gateway"]), dns = clean(raw["ipv4.dns"]),
      search = clean(raw["ipv4.dns-search"]), ignore_auto_dns = raw["ipv4.ignore-auto-dns"] == "yes",
      hidden = raw["802-11-wireless.hidden"] == "yes", mac = clean(raw["802-11-wireless.cloned-mac-address"]),
      live_address = (raw["IP4.ADDRESS"] or {})[1] or "", live_gateway = clean(raw["IP4.GATEWAY"]),
      live_dns = table.concat(dns, ", "), live_ipv6 = (raw["IP6.ADDRESS"] or {})[1] or "",
      device = clean(raw["GENERAL.DEVICES"]),
    }
  end)
end

--- Whether `text` is an IPv4 address, with a `/prefix` when `prefixed`.
function M.ipv4(text, prefixed)
  local a, b, c, d, rest = tostring(text):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)(.*)$")
  if not a then return false end
  for _, part in ipairs { a, b, c, d } do if tonumber(part) > 255 then return false end end
  if prefixed then
    local prefix = rest:match("^/(%d+)$")
    return prefix ~= nil and tonumber(prefix) <= 32
  end
  return rest == ""
end

--- Whether `text` is a list of DNS servers: IPv4 or IPv6, by commas or spaces.
function M.dns_list(text)
  local count = 0
  for word in tostring(text):gmatch("[^,%s]+") do
    if not (M.ipv4(word) or word:match("^[%x:]+$")) then return false end
    count = count + 1
  end
  return count > 0
end

--- A change as `nmcli connection modify` words, or nil and why. `change`:
--- `static` ({ address, gateway }), `dhcp`, `dns` (text, "" to go back to the
--- network's), `metered`, `dot`, `mac`, `autoconnect`.
function M.modify_words(change)
  local words = {}
  local function put(key, value) words[#words + 1] = key words[#words + 1] = value end
  if change.static then
    if not M.ipv4(change.static.address, true) then return nil, "An address looks like 192.168.1.20/24" end
    if (change.static.gateway or "") ~= "" and not M.ipv4(change.static.gateway) then return nil, "That gateway is not an address" end
    put("ipv4.method", "manual")
    put("ipv4.addresses", change.static.address)
    put("ipv4.gateway", change.static.gateway or "")
  elseif change.dhcp then
    put("ipv4.method", "auto")
    put("ipv4.addresses", "")
    put("ipv4.gateway", "")
  end
  if change.dns ~= nil then
    if change.dns ~= "" and not M.dns_list(change.dns) then return nil, "Those are not DNS servers" end
    put("ipv4.dns", (change.dns:gsub("[,%s]+", " ")))
    put("ipv4.ignore-auto-dns", change.dns ~= "" and "yes" or "no")
  end
  if change.metered ~= nil then put("connection.metered", change.metered) end
  if change.dot ~= nil then put("connection.dns-over-tls", change.dot) end
  if change.mac ~= nil then put("802-11-wireless.cloned-mac-address", change.mac) end
  if change.autoconnect ~= nil then put("connection.autoconnect", change.autoconnect and "yes" or "no") end
  if #words == 0 then return nil, "Nothing to change" end
  return words
end

--- Saves `change` and brings the connection up again if `reapply`. `done(ok, why)`.
function M.modify(uuid, change, done, reapply)
  local words, why = M.modify_words(change)
  if not words then return done(nil, why) end
  local argv = { "nmcli", "connection", "modify", uuid }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  host.act(argv, function(text, failed)
    if text == nil then return done(nil, failed) end
    if not reapply then return done(true) end
    host.act({ "nmcli", "connection", "up", uuid }, done)
  end)
end

--- `done(password, err)`: the saved Wi-Fi password of the profile at `path`.
--- NetworkManager checks the caller may read it.
function M.secret(path, done)
  local sent, why = host.bus("system").call1_async(NM, path, CONNECTION, "GetSecrets", { SECURITY }, TIMEOUT,
    function(reply, err)
      local secrets = type(reply) == "table" and reply[SECURITY]
      if not secrets then return done(nil, err or "No saved password") end
      local key = secrets.psk or secrets["wep-key0"]
      if not key or key == "" then return done(nil, "No saved password") end
      done(key)
    end)
  if not sent then done(nil, why) end
end

--- The text a phone's camera reads as this network.
function M.wifi_uri(ssid, security, password, hidden)
  local auth = (security == "open" or security == "owe") and "nopass" or (security == "wep" and "WEP" or "WPA")
  return qr.wifi({ ssid = ssid, security = auth, hidden = hidden }, password)
end

return M
