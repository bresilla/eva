-- The Software page: what this machine installs with, the apps that can be taken
-- off it, what cannot and why, and the apps hidden from the grid. In the page
-- template. `model` is shell/software_model.lua.
local morf = require("morf")
local P = require("themes.layouts.page")

local V = {}
local ROWS, KINDS = 24, 6

--- The page at `w` x `h`.
function V.build(model, w, h)
  local inner = P.inner(w)
  local apps = require("apps")
  local armed = morf.signal("eva.software.armed", "")
  local function machine() return model.machine() end
  local function can_install() return machine().nix or machine().flatpak end

  local on_machine = { id = "software-machine", width = w, title = "This machine",
    P.row { id = "software-nixos", width = inner, icon = "deployed_code", title = "NixOS",
      subtitle = "System apps cannot be removed from here",
      visible = function() return machine().nixos end },
    P.row { id = "software-flatpak", width = inner, icon = "package_2", title = "Flatpak",
      subtitle = function() return machine().flatpak and "Installs and removes apps" or "Not on this machine" end,
      on = function() return machine().flatpak end },
    P.row { id = "software-nix", width = inner, icon = "deployed_code", title = "Nix profile",
      subtitle = function() return machine().nix and "Installs and removes your own apps" or "Not on this machine" end,
      on = function() return machine().nix end },
    P.row { id = "software-working", width = inner, icon = "hourglass_top",
      title = function() local job = model.job:get() return job and (job.verb .. " " .. job.name) or "" end,
      subtitle = "Under way", visible = function() return model.job:get() ~= false end },
    P.buttons { id = "software-get", width = inner, visible = can_install,
      { id = "software-get-button", label = "Get apps", icon = "add_circle",
        on_clicked = function() require("launcher").open_on("> get ") end },
      { id = "software-updates-button", label = "Updates", icon = "system_update",
        on_clicked = function() require("utilities").request("updates") end } },
  }

  local function removable()
    local out = {}
    for _, group in ipairs(model.by_source()) do
      for _, item in ipairs(group.rows) do
        if item.source.removable then out[#out + 1] = item end
      end
    end
    return out
  end
  local yours = { id = "software-yours", width = w, title = "Can be removed",
    visible = function() return #removable() > 0 end }
  for index = 1, ROWS do
    local function item() return removable()[index] end
    local function key() local it = item() return it and it.row.id or "" end
    yours[#yours + 1] = P.row { id = "software-app-" .. index, width = inner, icon = "apps",
      visible = function() return item() ~= nil end,
      title = function() local it = item() return it and it.row.name or "" end,
      subtitle = function() local it = item() return it and (it.source.label .. " · " .. it.source.what) or "" end,
      trailing = P.button { id = "software-remove-" .. index, icon = "delete",
        label = function() return armed:get() == key() and key() ~= "" and "Sure?" or "Remove" end,
        on_clicked = function()
          local it = item()
          if not it then return end
          if armed:get() == it.row.id then
            armed:set("")
            model.uninstall(it.row)
          else
            armed:set(it.row.id)
          end
        end } }
  end

  local function refused()
    local out = {}
    for _, group in ipairs(model.by_source()) do
      local count = 0
      for _, item in ipairs(group.rows) do
        if not item.source.removable then count = count + 1 end
      end
      if count > 0 then out[#out + 1] = { label = group.label, why = group.why, count = count } end
    end
    return out
  end
  local stays = { id = "software-stays", width = w, title = "Cannot be removed here",
    visible = function() return #refused() > 0 end }
  for index = 1, KINDS do
    local function group() return refused()[index] end
    stays[#stays + 1] = P.row { id = "software-kind-" .. index, width = inner, icon = "lock",
      visible = function() return group() ~= nil end,
      title = function() local g = group() return g and (g.label .. " · " .. g.count) or "" end,
      subtitle = function() local g = group() return g and g.why or "" end }
  end

  local function hidden() model.revision:get() return apps.hidden_rows() end
  local kept = { id = "software-hidden", width = w, title = "Hidden from the grid",
    visible = function() return #hidden() > 0 end }
  for index = 1, ROWS do
    local function row() return hidden()[index] end
    kept[#kept + 1] = P.row { id = "software-hidden-" .. index, width = inner, icon = "visibility_off",
      visible = function() return row() ~= nil end,
      title = function() local r = row() return r and r.name or "" end,
      trailing = P.button { id = "software-show-" .. index, label = "Show", icon = "visibility",
        on_clicked = function()
          local r = row()
          if r then model.show(r) end
        end } }
  end

  return P.page { id = "software-scroll", width = w, height = h,
    P.section(on_machine), P.section(yours), P.section(stays), P.section(kept) }
end

return V
