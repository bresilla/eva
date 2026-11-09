-- The Backups page: the snapshots of whichever tool is here, a way to make one,
-- and one file back from the snapshot pressed. With no tool, what would be needed.
local morf = require("morf")
local ui = require("morf.ui")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local M = {}

local SHOWN = 12

function M.page(model, w, h)
  local inner = P.inner(w)
  local function tool_items()
    local out = {}
    for index, row in ipairs(model.tools:get()) do out[index] = row end
    return out
  end

  -- One row to a tool, its own lit, when there is more than one.
  local tools = { width = inner, gap = P.ROW_GAP, visible = function() return #tool_items() > 1 end }
  for index = 1, 3 do
    local function row() return tool_items()[index] end
    tools[#tools + 1] = P.row { id = "backups-tool-" .. index, width = inner, icon = "backup",
      visible = function() return row() ~= nil end,
      on = function() local r = row() return r ~= nil and r.id == model.tool() end,
      title = function() local r = row() return r and r.name or "" end,
      on_clicked = function() local r = row() if r then model.set_tool(r.id) end end }
  end

  local list = { id = "backups-list", width = w, title = "Snapshots", visible = model.any,
    note = function() return model.loading:get() and "Reading…" or tostring(#model.rows:get()) end,
    ui.Column(tools),
    P.button { id = "backups-make", width = inner, tone = "primary", icon = "add",
      label = function() return model.busy:get() and "Working…" or "Make one now" end, on_clicked = model.create },
    F.note(inner, "None yet.", { id = "backups-none",
      visible = function() return not model.loading:get() and not model.locked:get() and #model.rows:get() == 0 end }),
    F.note(inner, "Reading these takes your password.", { id = "backups-locked", visible = function() return model.locked:get() end }),
    P.button { id = "backups-unlock", width = inner, label = "Read them", icon = "lock_open", on_clicked = model.unlock,
      visible = function() return model.locked:get() end },
  }
  for index = 1, SHOWN do
    local function row() return model.rows:get()[index] end
    list[#list + 1] = P.row { id = "backups-row-" .. index, width = inner, icon = "history",
      visible = function() return row() ~= nil end,
      on = function() local r = row() return r ~= nil and r.id == model.chosen:get() end,
      title = function() local r = row() return r and r.title or "" end,
      subtitle = function() local r = row() return r and (r.when ~= "" and (r.when .. " · " .. r.detail) or r.detail) or "" end,
      on_clicked = function() local r = row() if r then model.choose(r) end end }
  end

  local path_box, path_input = P.field { id = "backups-path", width = inner, placeholder = "/home/you/notes.txt",
    on_changed = function(text) model.set_path(text) end }
  local choosing = morf.signal("eva.backups.choosing", false)
  local restore = P.section { id = "backups-restore", width = w, title = "Get a file back",
    visible = function() return model.selected() ~= nil end, fold = true,
    F.note(inner, function()
      local row = model.selected()
      return row and ("From %s"):format(row.when ~= "" and row.when or row.detail) or ""
    end, { id = "backups-from" }),
    path_box,
    P.button { id = "backups-browse", width = inner, label = function() return choosing:get() and "Close" or "Choose the file" end,
      icon = "folder_open", on_clicked = function() choosing:set(not choosing:get()) end },
    F.chooser { id = "backups-chooser", width = inner, open = function() return choosing:get() end,
      on_accepted = function(path)
        choosing:set(false)
        path_input.text = path
        model.set_path(path)
      end, on_cancelled = function() choosing:set(false) end },
    P.buttons { width = inner,
      { id = "backups-copy", label = "Restore a copy", tone = "primary", on_clicked = model.restore_copy },
      { id = "backups-replace", icon = "warning", on_clicked = model.restore_replace,
        label = function() return model.confirming:get() and "Yes, replace it" or "Replace the file" end },
    },
    F.status("backups-said", inner, model),
    P.fold { width = inner, shown = function() return model.confirming:get() end,
      P.button { id = "backups-keep", width = inner, label = "Keep the file as it is", on_clicked = model.keep_file } },
    F.note(inner, "A copy lands beside the file, with .restored on its name. Nothing is overwritten."),
  }

  local missing = { id = "backups-missing", width = w, title = "No backup tool here", visible = function() return not model.any() end,
    F.note(inner, "eva works with snapper, btrbk and restic, and finds none of them on this machine. Any one of these is enough:"),
  }
  for index, need in ipairs(model.needs()) do
    missing[#missing + 1] = F.fact { id = "backups-need-" .. index, width = inner, icon = "backup", title = need[1], subtitle = need[2] }
  end

  local status = F.status("backups-status", w, model)
  status.visible = function() return (model.message:get() or "") ~= "" and model.selected() == nil end
  return P.page { id = "backups-scroll", width = w, height = h, active = model.active,
    P.section(list), restore, P.section(missing), status,
    P.section { id = "backups-more", width = w,
      F.link { id = "backups-settings", width = inner, icon = "tune", title = "Backup settings",
        subtitle = "Which tool, the repository, what to keep", go = function() model.request("backups/more") end } },
  }
end

return M
