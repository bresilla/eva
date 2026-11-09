-- The Storage and Printers pages. The passphrase of an encrypted drive stays
-- in a local of the prompt, as Hotspot's password does, and is handed over
-- once.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local unicase = require("lib.util.unicase")
local S = theme.space

local M = {}

--- A bar of `usage()`: how full, and the words beside it.
local function usage_row(id, inner, title, usage, model)
  local function u() return usage() end
  return ui.Column { id = id, width = inner, gap = S.xs, visible = function() return u() ~= nil end,
    kit.text { width = inner, elide = "right", font_size = theme.size.normal, color = kit.ink("hi"),
      text = function()
        local now = u()
        if not now then return title end
        return ("%s · %s free of %s"):format(title, model.human(now.free), model.human(now.total))
      end },
    kit.fill { width = inner, height = S.m, color = kit.signal("accent"),
      value = function() local now = u() return now and now.share or 0 end },
  }
end

function M.storage_page(model, w, h)
  local inner = P.inner(w)
  local function asked() return model.asked() end

  local function volume_list(id, rows, max, none)
    return F.list(inner, id .. "-row-", function() return #rows() end, function(index, width)
      local function row() return rows()[index] or {} end
      local function locked() local r = row() return r.encrypted == true and not r.unlocked end
      return P.row { id = id .. "-" .. index, width = width,
        icon = function()
          local r = row()
          if r.encrypted then return r.unlocked and "lock_open" or "lock" end
          return r.removable and "usb" or "hard_drive"
        end,
        on = function() return row().mounted == true end,
        title = function() return row().name or "" end,
        subtitle = function()
          local r = row()
          local parts = { model.human(r.size) }
          if (r.fs or "") ~= "" then parts[#parts + 1] = r.fs end
          parts[#parts + 1] = r.mounted and r.mount_point or (locked() and "Locked" or "Not mounted")
          return table.concat(parts, " · ")
        end,
        trailing = ui.Row { gap = S.xs, align = "center",
          P.button { id = id .. "-unlock-" .. index, label = "Unlock", visible = locked, on_clicked = function() model.ask(row()) end },
          P.button { id = id .. "-mount-" .. index, label = function() return row().mounted and "Unmount" or "Mount" end,
            visible = function() local r = row() return not locked() and not r.system end,
            on_clicked = function() local r = row() if r.mounted then model.unmount(r) else model.mount(r) end end },
          P.button { id = id .. "-eject-" .. index, label = "Eject", tone = "primary",
            visible = function() return row().can_eject == true end, on_clicked = function() model.eject(row()) end } } }
    end, none, max)
  end

  local passphrase, input = "", nil
  local typed = morf.signal("eva.storage.typed", false)
  local function forget()
    passphrase = ""
    input.text = ""
    typed:set(false)
  end
  local function send()
    local given = passphrase
    forget()
    model.unlock(given)
  end
  local function cancel() forget() model.dismiss() end
  local box
  box, input = P.field { id = "storage-passphrase", kind = "password", width = inner, placeholder = "Passphrase",
    on_changed = function(value) passphrase = value typed:set(value ~= "") end, on_accepted = send, on_escape = cancel }
  morf.effect("eva.storage.passphrase.focus", function() input.focus = asked() ~= nil end)
  local prompt = ui.Column { id = "storage-unlock-prompt", width = inner, gap = S.s, visible = function() return asked() ~= nil end,
    F.note(inner, function() return "Passphrase for " .. ((asked() or {}).name or "") end),
    box,
    P.buttons { width = inner,
      { id = "storage-unlock-cancel", label = "Cancel", on_clicked = cancel },
      { id = "storage-unlock-send", label = "Unlock", tone = "primary", on_clicked = send,
        enabled = function() return typed:get() end } },
  }

  local function trash_words()
    local bin = model.trash()
    if bin.count == 0 then return "Empty" end
    return ("%d item%s"):format(bin.count, bin.count == 1 and "" or "s")
  end
  local function confirming() return model.emptying:get() end

  return P.page { id = "storage-scroll", width = w, height = h, active = model.active,
    P.section { id = "storage-usage", width = w, title = "Space",
      usage_row("storage-root", inner, "System", model.root, model),
      usage_row("storage-home", inner, "Home", model.home, model),
    },
    P.section { id = "storage-removable", width = w, title = "Removable drives",
      volume_list("storage-drive", model.removable, 8, "No drives plugged in"), prompt,
      F.status("storage-status", inner, model),
    },
    P.section { id = "storage-fixed", width = w, title = "Disks", visible = function() return #model.fixed() > 0 end,
      volume_list("storage-disk", model.fixed, 8) },
    P.section { id = "storage-trash", width = w, title = "Trash",
      F.fact { id = "storage-trash-row", width = inner, icon = "delete", title = "Trash", subtitle = trash_words,
        trailing = P.button { id = "storage-empty", label = "Empty", visible = function()
          return model.trash().count > 0 and not confirming() end,
          on_clicked = function() model.emptying:set(true) end } },
      P.buttons { width = inner, visible = confirming,
        { id = "storage-empty-cancel", label = "Keep them", visible = confirming, on_clicked = function() model.emptying:set(false) end },
        { id = "storage-empty-yes", label = "Delete for good", tone = "primary", visible = confirming, on_clicked = model.empty_trash } },
    },
    P.section { id = "storage-options", width = w, title = "Warnings",
      F.slider { id = "storage-low", width = inner, icon = "warning", name = "Warn below", from = 0, to = 30, step = 1,
        value = model.low_space, set = model.set_low_space,
        format = function(v) return v == 0 and "Never" or ("%d%% free"):format(v) end },
      F.toggle { id = "storage-popup", width = inner, icon = "usb", title = "Popup for new drives",
        on = model.popup, set = model.set_popup },
    },
  }
end

function M.printers_page(model, w, h)
  local inner = P.inner(w)
  local function here() return model.available() end
  local printers = F.list(inner, "printer-row-", function() return #model.list() end, function(index, width)
    local function row() return model.list()[index] or {} end
    return P.row { id = "printer-" .. index, width = width, icon = "print", on = function() return row().enabled == true end,
      title = function() return (row().name or "") .. (row().default and " · Default" or "") end,
      subtitle = function()
        local r = row()
        if (r.reason or "") ~= "" then return r.reason end
        return r.enabled and unicase.capitalise(r.state or "") or "Paused"
      end,
      trailing = ui.Row { gap = S.xs, align = "center",
        P.button { id = "printer-default-" .. index, label = "Default", visible = function() return row().default ~= true end,
          on_clicked = function() model.set_default(row()) end },
        P.button { id = "printer-remove-" .. index, label = "Remove", on_clicked = function() model.remove(row()) end } } }
  end, "No printers added", 8)
  local jobs = F.list(inner, "printer-job-", function() return #model.jobs() end, function(index, width)
    local function job() return model.jobs()[index] or {} end
    return P.row { id = "printer-queue-" .. index, width = width, icon = "description", on = function() return false end,
      title = function() return job().id or "" end, subtitle = function() return job().user or "" end,
      trailing = P.button { id = "printer-cancel-" .. index, label = "Cancel", on_clicked = function() model.cancel(job()) end } }
  end, "Nothing is printing", 8)
  local found = F.list(inner, "printer-found-", function() return #model.found() end, function(index, width)
    local function row() return model.found()[index] or {} end
    return P.row { id = "printer-add-" .. index, width = width, icon = "add", title = function() return row().name or "" end,
      subtitle = function() return row().uri or "" end, on_clicked = function() model.add(row()) end }
  end, nil, 8)
  local address = morf.signal("eva.printers.address", "")
  local box = P.field { id = "printer-address", width = inner, placeholder = "ipp://printer.local/ipp/print",
    on_changed = function(value) address:set(value) end }
  local scanners = F.list(inner, "scanner-row-", function() return #model.scanners() end, function(index, width)
    local function row() return model.scanners()[index] or {} end
    return P.row { id = "scanner-" .. index, width = width, icon = "scanner", on = function() return false end,
      title = function() return row().name or "" end, subtitle = function() return row().device or "" end }
  end, nil, 4)
  local missing = P.empty { id = "printers-none", width = w, icon = "print_disabled", title = "No printing here",
    text = "CUPS is not installed or not running." }
  missing.visible = function() return not here() end
  return P.page { id = "printers-scroll", width = w, height = h, active = model.active,
    missing,
    F.note(w, "On NixOS, services.printing.enable turns printing on, and hardware.sane.enable scanning.",
      { id = "printers-declared", visible = function() return not here() and model.declared() end }),
    P.section { id = "printers-queues", width = w, title = "Printers", visible = here, printers },
    P.section { id = "printers-jobs", width = w, title = "Printing now", visible = here, jobs },
    P.section { id = "printers-add", width = w, title = "Add a printer", visible = here, found,
      P.button { id = "printers-discover", icon = "search", width = inner,
        label = function() return model.searching:get() and "Looking…" or "Look on this network" end,
        on_clicked = model.discover },
      box,
      P.button { id = "printers-add-address", label = "Add this address", width = inner,
        on_clicked = function() model.add_address(address:get():match("//([^/:]+)") or "printer", address:get()) end },
      F.status("printers-status", inner, model),
    },
    P.section { id = "printers-scanners", width = w, title = "Scanners",
      visible = function() return #model.scanners() > 0 end, scanners },
  }
end

return M
