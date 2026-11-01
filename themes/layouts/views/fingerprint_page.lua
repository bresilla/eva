-- The Fingerprints page, behind the Lock screen's: what the reader holds, adding a
-- finger, and how a finger reaches the lock. In the page template. `model` is
-- shell/fingerprint_model.lua.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local config = require("config")
local P = require("themes.layouts.page")
local F = require("themes.layouts.option_rows")
local C, S = theme.color, theme.space

local V = {}

--- The page at `w` x `h`. `active()` says it is on show.
function V.build(model, active, w, h)
  local inner = P.inner(w)
  local armed = morf.signal("eva.fingerprint.armed", "")
  local function state() return model.state() end
  local function ready() return state().status == "ready" end
  local function enrolling() return state().enrolling or false end

  local reader = { id = "fingerprint-reader", width = w, title = "Reader",
    P.row { id = "fingerprint-status", width = inner, icon = "fingerprint",
      title = function()
        if ready() then return state().name or "Fingerprint reader" end
        return state().status == "absent" and "No reader found" or "fprintd is not here"
      end,
      subtitle = function()
        if ready() then return "Fingers are kept by fprintd, on this machine" end
        if state().status == "absent" then return "This machine shows no fingerprint reader" end
        return "On NixOS, set services.fprintd.enable = true"
      end },
    P.row { id = "fingerprint-note", width = inner, icon = "info", title = function() return state().note or "" end,
      visible = function() return (state().note or "") ~= "" and not enrolling() end },
  }

  local fingers = { id = "fingerprint-fingers", width = w, title = "Your fingers",
    visible = function() return ready() and #(state().fingers or {}) > 0 end }
  for index = 1, #model.FINGERS do
    local function finger() return (state().fingers or {})[index] end
    fingers[#fingers + 1] = P.row { id = "fingerprint-finger-" .. index, width = inner, icon = "fingerprint",
      visible = function() return finger() ~= nil end,
      title = function() return finger() and model.name_of(finger()) or "" end,
      trailing = P.button { id = "fingerprint-remove-" .. index, icon = "delete",
        label = function() return finger() and armed:get() == finger() and "Sure?" or "Remove" end,
        on_clicked = function()
          local id = finger()
          if not id then return end
          if armed:get() == id then
            armed:set("")
            model.remove(id)
          else
            armed:set(id)
          end
        end } }
  end

  local add = { id = "fingerprint-add", width = w, title = "Add a finger",
    visible = function() return ready() and not enrolling() and #model.spare() > 0 end }
  for index = 1, #model.FINGERS do
    local function row() return model.spare()[index] end
    add[#add + 1] = P.row { id = "fingerprint-add-" .. index, width = inner, height = P.BUTTON_H, icon = "add",
      visible = function() return row() ~= nil end,
      title = function() local r = row() return r and r.name or "" end,
      on_clicked = function()
        local r = row()
        if r then model.enroll(r.id) end
      end }
  end

  -- One mark for each reading the reader wants, lit as it gets them.
  local marks = { id = "fingerprint-marks", gap = S.s, align = "center" }
  for index = 1, 12 do
    marks[#marks + 1] = ui.Rect { width = S.m, height = S.m, radius = kit.round(S.m / 2),
      visible = function() return index <= (state().stages or 0) end,
      color = function()
        local now = enrolling()
        return now and index <= now.read and C.primary or C.surfaceContainerHighest
      end }
  end
  local adding = { id = "fingerprint-adding", width = w, title = "Adding a finger",
    visible = function() return enrolling() ~= false end,
    P.row { id = "fingerprint-adding-row", width = inner, icon = "fingerprint",
      title = function() local now = enrolling() return now and model.name_of(now.finger) or "" end,
      subtitle = function() return state().note or "" end },
    ui.Row(marks),
    P.buttons { id = "fingerprint-adding-buttons", width = inner,
      { id = "fingerprint-cancel", label = "Cancel", icon = "close", on_clicked = model.cancel } },
  }

  local function readers() return config.get("lock.readers") == true end
  local lock = { id = "fingerprint-lock", width = w, title = "On the lock",
    P.row { id = "fingerprint-join", width = inner, icon = "lock",
      title = function() return model.join().title end, subtitle = function() return model.join().text end },
    F.switch { id = "fingerprint-readers", width = inner, icon = "fingerprint", title = "Fingerprint and face",
      subtitle = "Off asks for the password every time", on = readers,
      set = function(on) config.set("lock.readers", on == true) end },
  }

  local page = P.page { id = "fingerprint-scroll", width = w, height = h,
    P.section(reader), P.section(adding), P.section(fingers), P.section(add), P.section(lock) }
  morf.effect("eva.fingerprint.page", function()
    if active() then
      model.refresh()
    else
      model.cancel()
    end
  end, { owner = page })
  return page
end

return V
