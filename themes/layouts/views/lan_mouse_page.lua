-- The Mouse sharing page, in the page template (themes/layouts/page.lua):
-- lan-mouse on or off, this machine's fingerprint, the machines it reaches
-- (each turned on or off, set to a side, taken away), adding one, the
-- machines asking to reach this one and those allowed to.
local morf = require("morf")
local ui = require("morf.ui")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}

local SLOTS = 6

function M.build(model, w, h)
  local inner = P.inner(w)
  local open = morf.signal("eva.lan_mouse.open." .. tostring({}), 0)

  local main = P.section { id = "lan-mouse", width = w, visible = model.installed,
    P.row { id = "lan-mouse-on", width = inner, icon = "swap_horiz", title = "Mouse sharing", on = model.on,
      subtitle = function()
        if not model.on() then return "One mouse and keyboard across your machines" end
        if not model.up() then return "Starting…" end
        return ("Ready on port %d"):format(model.port())
      end,
      trailing = P.switch { id = "lan-mouse-switch", name = "Mouse sharing", on = model.on, on_toggled = model.set_on } },
    P.fold { width = inner, shown = model.blocked,
      P.row { id = "lan-mouse-blocked", width = inner, icon = "info", title = "The pointer is held here",
        subtitle = "This desktop refused to lend or take it",
        trailing = P.button { id = "lan-mouse-retake", label = "Try again", icon = "restart_alt", on_clicked = model.retake } } },
    F.note(inner, function() return model.release_keys() .. " together bring the pointer back" end,
      { id = "lan-mouse-release" }),
    F.status("lan-mouse-status", inner, model),
  }

  local this = P.section { id = "lan-mouse-this", width = w, title = "This machine", visible = model.up, fold = true,
    F.fact { id = "lan-mouse-fingerprint", width = inner, icon = "fingerprint", title = "Fingerprint",
      subtitle = function() return model.short(model.fingerprint()) end,
      trailing = P.button { id = "lan-mouse-copy", label = "Copy", icon = "content_copy", on_clicked = model.copy } },
    F.note(inner, "Allow this fingerprint on the other machine, and it reaches this one"),
  }

  -- The machines it reaches: a row each, its side and Remove under it.
  local machines = { id = "lan-mouse-machines", width = w, title = "Machines", visible = model.up, fold = true }
  for i = 1, SLOTS do
    local function c() return model.clients()[i] end
    local function active() local m = c() return m ~= nil and m.active end
    local function each(act) return function(...) local m = c() if m then return act(m, ...) end end end
    -- Its side and Remove fold out under it, made the first time it opens.
    local under = ui.Column { width = inner }
    local made = false
    morf.effect("eva.lan_mouse.under." .. i .. "." .. tostring(under), function()
      if made or open:get() ~= i then return end
      made = true
      ui.reparent(P.fold { width = inner, gap = P.ROW_GAP, shown = function() return open:get() == i and c() ~= nil end,
        F.choices { id = "lan-mouse-machine-" .. i .. "-side", width = inner, items = model.SIDES, per_row = 4,
          now = function() return (c() or {}).pos end, pick = each(function(m, pos) model.place(m.handle, pos) end) },
        P.button { id = "lan-mouse-machine-" .. i .. "-remove", label = "Remove", icon = "delete", width = inner,
          on_clicked = each(function(m) open:set(0) model.remove(m.handle) end) } }, under)
    end, { owner = under })
    machines[#machines + 1] = ui.Column { width = inner, visible = function() return c() ~= nil end,
      P.row { id = "lan-mouse-machine-" .. i, width = inner, on = active,
        icon = function() return model.icon((c() or {}).pos) end,
        title = function()
          local m = c() or {}
          if (m.hostname or "") ~= "" then return m.hostname end
          return (m.ips or {})[1] or "A machine"
        end,
        subtitle = function()
          local m = c()
          if not m then return "" end
          return model.where(m.pos) .. " · " .. (m.alive and "Connected" or m.active and "Not reachable" or "Off")
        end,
        trailing = P.switch { id = "lan-mouse-machine-" .. i .. "-switch", name = "Use this machine", on = active,
          on_toggled = each(function(m, on) model.activate(m.handle, on) end) },
        on_clicked = function() open:set(open:get() == i and 0 or i) end },
      under }
  end
  machines[#machines + 1] = P.row { id = "lan-mouse-none", width = inner, icon = "info", title = "No machines yet",
    visible = function() return #model.clients() == 0 end }

  -- Another machine to reach: its name or address and its side.
  local name = morf.signal("eva.lan_mouse.name", "")
  local side = morf.signal("eva.lan_mouse.side", "right")
  local input
  local function add()
    if model.add(name:get(), side:get()) then
      name:set("")
      if input then input.text = "" end
    end
  end
  local box
  box, input = F.field { id = "lan-mouse-add-name", width = inner, label = "Its name or address",
    placeholder = "laptop or 100.68.8.20", on_changed = function(text) name:set(text) end, on_accepted = add }
  local adding = P.section { id = "lan-mouse-add", width = w, title = "Add a machine", visible = model.up, fold = true,
    box,
    F.note(inner, "Where it stands from here"),
    F.choices { id = "lan-mouse-add-side", width = inner, items = model.SIDES, per_row = 4,
      now = function() return side:get() end, pick = function(pos) side:set(pos) end },
    P.button { id = "lan-mouse-add-button", icon = "add", label = "Add this machine", tone = "primary", width = inner,
      enabled = function() return name:get():find("%S") ~= nil end, on_clicked = add },
  }

  -- Who asks to reach this one, and who may.
  local asking = { id = "lan-mouse-asking", width = w, title = "Asking to connect", fold = true,
    visible = function() return model.up() and #model.asking() > 0 end }
  for i = 1, 3 do
    local function fp() return model.asking()[i] end
    asking[#asking + 1] = P.row { id = "lan-mouse-asking-" .. i, width = inner, icon = "how_to_reg",
      title = "A machine asks to reach this one", subtitle = function() return model.short(fp()) end,
      visible = function() return fp() ~= nil end,
      trailing = P.button { id = "lan-mouse-asking-" .. i .. "-allow", label = "Allow", icon = "check", tone = "primary",
        on_clicked = function() local f = fp() if f then model.allow(f, "Machine " .. f:sub(1, 5)) end end } }
  end

  local allowed = { id = "lan-mouse-allowed", width = w, title = "Allowed to reach this one", visible = model.up,
    fold = true }
  for i = 1, SLOTS do
    local function a() return model.allowed()[i] end
    allowed[#allowed + 1] = P.row { id = "lan-mouse-allowed-" .. i, width = inner, icon = "verified_user",
      title = function() return (a() or {}).name or "" end,
      subtitle = function() return model.short((a() or {}).fingerprint) end,
      visible = function() return a() ~= nil end,
      trailing = P.button { id = "lan-mouse-allowed-" .. i .. "-remove", label = "Remove", icon = "delete",
        on_clicked = function() local x = a() if x then model.forget(x.fingerprint) end end } }
  end
  allowed[#allowed + 1] = P.row { id = "lan-mouse-allowed-none", width = inner, icon = "info", title = "None yet",
    visible = function() return #model.allowed() == 0 end }

  return P.page { id = "lan-mouse-scroll", width = w, height = h, active = model.active,
    main, this, P.section(machines), adding, P.section(asking), P.section(allowed),
    P.empty { id = "lan-mouse-missing", width = w, title = "lan-mouse is not installed",
      text = "Add it to this system to share a mouse and keyboard with other machines",
      visible = function() return not model.installed() end },
  }
end

return M
