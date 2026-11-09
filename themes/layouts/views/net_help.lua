-- Connection help, one level under Network and Wired: signing in to a network
-- that asks, a walk through what could be wrong, a speed test, and the sign-in
-- check's setting. Each thing that reaches outside names who it reaches.
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local C = theme.color
local M = {}

local ICONS = { idle = "radio_button_unchecked", running = "hourglass_top", ok = "check_circle", unsure = "help",
  failed = "cancel", skipped = "remove_circle_outline" }
local PHASES = { latency = "Timing the connection…", download = "Downloading…", upload = "Uploading…" }

function M.page(model, w, h)
  local inner = P.inner(w)

  local asking = P.section { id = "net-portal", width = w, title = "Sign in", visible = function() return model.asking:get() ~= false end,
    P.row { id = "net-portal-row", width = inner, icon = "wifi_password",
      title = function() local a = model.asking:get() return a and (a.name .. " wants you to sign in") or "" end,
      subtitle = "It lets you online after that",
      trailing = P.button { id = "net-portal-open", label = "Sign in", tone = "primary", on_clicked = model.sign_in } } }

  local steps = { id = "net-steps", width = w, title = "Troubleshoot",
    F.note(inner, function()
      return "Asks your router, your DNS servers and " .. model.server().host .. "."
    end, { id = "net-steps-who" }),
    P.button { id = "net-steps-run", width = inner, tone = "primary", icon = "troubleshoot",
      label = function() return model.walking:get() and "Stop" or "Check my connection" end,
      on_clicked = model.troubleshoot },
  }
  for _, row in ipairs(model.STEPS) do
    local name = row[1]
    local function step() return model.steps:get()[name] end
    steps[#steps + 1] = P.row { id = "net-step-" .. name, width = inner, icon = function() return ICONS[step().state] end,
      on = function() return step().state == "ok" or step().state == "running" end,
      title = row[2], subtitle = function() return step().words end,
      visible = function() return step().state ~= "idle" end }
  end
  steps[#steps + 1] = F.note(inner, function()
    local verdict = model.verdict:get()
    return verdict and verdict.words or ""
  end, { id = "net-steps-verdict", visible = function() return model.verdict:get() ~= false end,
    color = function() local v = model.verdict:get() return v and v.failed and C.error or kit.ink("hi")() end })
  steps[#steps + 1] = P.button { id = "net-steps-sign-in", width = inner, tone = "primary", label = "Open the sign-in page", icon = "open_in_new",
    visible = function() local v = model.verdict:get() return v ~= false and v.login ~= nil end, on_clicked = model.open_found }

  local function reading(id, icon, title, value)
    return F.fact { id = id, width = inner, icon = icon, title = title, subtitle = value,
      visible = function() return model.result:get() ~= false end }
  end
  local function got(name) local r = model.result:get() return r and r[name] or nil end
  local speed = P.section { id = "net-speed", width = w, title = "Speed test",
    F.note(inner, function()
      local s, parts = model.SPEED, {}
      parts[1] = ("Runs only when you press Start. Uses about %d MB, through %s, run by %s."):format(
        (s.down_bytes + s.up_bytes) // 1000000, s.host, s.name)
      if model.metered() then parts[2] = "You are on mobile data, so this counts against your allowance." end
      return table.concat(parts, " ")
    end, { id = "net-speed-who" }),
    P.button { id = "net-speed-run", width = inner, tone = "primary", icon = "speed",
      label = function() return model.phase:get() ~= "" and "Stop" or "Start" end, on_clicked = model.speed },
    F.note(inner, function()
      return PHASES[model.phase:get()] or model.speed_said:get()
    end, { id = "net-speed-said", visible = function() return model.phase:get() ~= "" or model.speed_said:get() ~= "" end }),
    reading("net-speed-latency", "timer", "Latency", function() return model.ms(got("latency")) end),
    reading("net-speed-down", "download", "Download", function() return model.rate(got("down")) end),
    reading("net-speed-up", "upload", "Upload", function() return model.rate(got("up")) end),
  }

  local servers = {}
  for index, key in ipairs(model.SERVER_ORDER) do
    servers[index] = { key, nil, model.SERVERS[key].name }
  end
  local probing = P.section { id = "net-probe", width = w, title = "Sign-in pages",
    F.toggle { id = "net-probe-on", width = inner, icon = "wifi_find", title = "Check for sign-in pages",
      on = model.probing, set = model.set_probing,
      subtitle = function() return "Asks " .. model.server().host end },
    F.note(inner, "Off, eva sends nothing, and hears of a sign-in page only if NetworkManager is set to check for one. Turn it on when a hotel or train network connects but nothing loads."),
    F.note(inner, "Which server", { id = "net-probe-which" }),
    F.choices { id = "net-probe-server", width = inner, items = servers, per_row = 3,
      now = function() return model.server_key() end, pick = model.set_server },
  }

  return P.page { id = "net-help-scroll", width = w, height = h, active = model.active, asking, P.section(steps), speed, probing }
end

return M
