-- One connection's page, and the Proxy page.
local morf = require("morf")
local ui = require("morf.ui")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}

local METERED = { { "unknown", "auto_mode", "Auto" }, { "yes", "data_usage", "Yes" }, { "no", "all_inclusive", "No" } }
local DOT = { { "default", "auto_mode", "Default" }, { "opportunistic", "shield_question", "If offered" }, { "yes", "shield_lock", "Always" },
  { "no", "block", "Off" } }
local MAC = { { "", "memory", "Default" }, { "stable", "lock", "Stable" }, { "random", "shuffle", "Random" } }

--- A field filled from `read` (fn) when the page shows.
local function bound(id, width, placeholder, read, model)
  local value = morf.signal("eva.connection.field." .. id, "")
  local box, input = P.field { id = id, width = width, placeholder = placeholder, on_changed = function(text) value:set(text) end }
  morf.effect("eva.connection.fill." .. id, function()
    if model.active() then input.text = read() end
  end)
  return box, value
end

function M.connection_page(model, w, h)
  local inner = P.inner(w)
  local function d() return model.details() end
  local function live(id, icon, title, read)
    return P.row { id = id, width = inner, icon = icon, title = title, on = function() return false end,
      visible = function() return read() ~= "" end, subtitle = read,
      trailing = P.button { id = id .. "-copy", label = "Copy", accessible_name = "Copy " .. title,
        on_clicked = function() model.copy(read()) end } }
  end
  local address, address_text = bound("connection-address", inner, "192.168.1.20/24", function() return d().address or "" end, model)
  local gateway, gateway_text = bound("connection-gateway", inner, "192.168.1.1", function() return d().gateway or "" end, model)
  local dns, dns_text = bound("connection-dns", inner, "1.1.1.1, 9.9.9.9", function() return d().dns or "" end, model)
  return P.page { id = "connection-scroll", width = w, height = h, active = model.active,
    P.section { id = "connection-now", width = w, title = model.name,
      live("connection-ip", "lan", "Address", function() return d().live_address or "" end),
      live("connection-gw", "router", "Gateway", function() return d().live_gateway or "" end),
      live("connection-servers", "dns", "DNS servers", function() return d().live_dns or "" end),
      live("connection-v6", "public", "IPv6", function() return d().live_ipv6 or "" end),
      F.fact { id = "connection-device", width = inner, icon = "memory", title = "Device",
        visible = function() return (d().device or "") ~= "" end, subtitle = function() return d().device or "" end },
    },
    P.section { id = "connection-ip-mode", width = w, title = "IP address",
      F.choices { id = "connection-method", width = inner,
        items = { { "auto", "auto_mode", "Automatic" }, { "manual", "tune", "Manual" } },
        now = function() return d().method end,
        pick = function(mode) if mode == "auto" then model.save { dhcp = true } end end },
      F.note(inner, "Manual: the address with its prefix, and the gateway."),
      address, gateway,
      P.button { id = "connection-static-save", label = "Use this address", width = inner,
        on_clicked = function() model.save { static = { address = address_text:get(), gateway = gateway_text:get() } } end },
    },
    P.section { id = "connection-dns-section", width = w, title = "DNS",
      dns,
      P.buttons { width = inner,
        { id = "connection-dns-save", label = "Use these", on_clicked = function() model.save { dns = dns_text:get() } end },
        { id = "connection-dns-auto", label = "The network's", on_clicked = function() model.save { dns = "" } end } },
      F.note(inner, "DNS over TLS"),
      F.choices { id = "connection-dot", width = inner, items = DOT, per_row = 2, now = function() return d().dot end,
        pick = function(word) model.save { dot = word } end },
    },
    P.section { id = "connection-use", width = w, title = "Use",
      F.note(inner, "Metered: programs that ask hold back on this connection."),
      F.choices { id = "connection-metered", width = inner, items = METERED, now = function() return d().metered end,
        pick = function(word) model.save { metered = word } end },
      F.toggle { id = "connection-auto", width = inner, icon = "sync", title = "Connect by itself",
        on = function() return d().autoconnect == true end, set = function(on) model.save { autoconnect = on } end },
      F.note(inner, "MAC address", { visible = model.wifi }),
      F.choices { id = "connection-mac", width = inner, items = MAC, visible = model.wifi,
        now = function() return d().mac or "" end, pick = function(word) model.save { mac = word } end },
    },
    F.status("connection-status", w, model),
  }
end

function M.proxy_page(model, w, h)
  local inner = P.inner(w)
  local function manual() return model.mode() == "manual" end
  local function auto() return model.mode() == "auto" end
  local function line(key, placeholder, visible)
    local box, input = P.field { id = "proxy-" .. key, width = inner, placeholder = placeholder, visible = visible,
      on_changed = function(text) model.set(key, text) end }
    morf.effect("eva.proxy.fill." .. key, function()
      if model.active() then input.text = model.value(key) end
    end)
    return box
  end
  return P.page { id = "proxy-scroll", width = w, height = h, active = model.active,
    P.section { id = "proxy-mode", width = w, title = "Proxy",
      F.choices { id = "proxy-how", width = inner, items = model.MODES, now = model.mode, pick = function(mode) model.set("mode", mode) end },
      line("http", "http://proxy:3128", manual),
      line("https", "http://proxy:3128 for secure sites", manual),
      line("socks", "socks5://proxy:1080", manual),
      line("exclude", "Sites to reach directly", manual),
      line("pac", "http://example.com/proxy.pac", auto),
      P.button { id = "proxy-save", label = "Save", tone = "primary", width = inner, on_clicked = model.apply },
      F.note(inner, "Set through the session's environment and the desktop's proxy setting. Programs already running keep what they had. An address with a password in it would sit in a plain file: use one without."),
      F.status("proxy-status", inner, model),
    },
  }
end

return M
