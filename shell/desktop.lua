-- The desktop's widgets on screen. They live on the wallpaper's own layer where
-- Eva paints, so their glass reads the picture; where another tool paints, on a
-- layer of their own just above it.
local morf = require("morf")
local ui = require("morf.ui")
local config = require("config")
local wallpaper = require("wallpaper")
local model = require("desktop_model")
local M = { model = model }

local own

-- The view, built on a loader's budget.
local function built()
  return ui.Loader { anchors = { fill = true }, active = true, keep = true,
    source = function() return require("themes").view("desktop").build(model) end }
end

local function open_own()
  if own then return end
  own = morf.window.layer {
    blend = "srgb", namespace = "eva-desktop", layer = "bottom",
    anchors = { top = true, bottom = true, left = true, right = true },
    width = 0, height = 0, exclusive_zone = -1, keyboard_focus = "none", visible = true,
    root = ui.Item { anchors = { fill = true }, built() },
  }
end

local function close_own()
  if own then
    local gone = own
    own = nil
    gone:destroy()
  end
end

--- Puts the desktop on the layer that fits who paints.
function M.start()
  wallpaper.on_layer(function(root) ui.reparent(built(), root) end)
  morf.effect("eva.desktop.host", function()
    if wallpaper.painter() == "eva" then close_own()
    elseif model.wanted() then open_own()
    else close_own() end
  end)
  morf.effect("eva.desktop.reading", function()
    local quiet = require("wallpaper_quiet")
    if model.wanted() then quiet.analyse(wallpaper.picture()) end
  end)
  local listed = {}
  for _, entry in ipairs(model.CATALOGUE) do listed[#listed + 1] = entry.id end
  model.watch_command(function()
    for _, item in ipairs(model.everything()) do if item.id == "command" then return true end end
    return false
  end)
end

--- `desktop edit|done|state`, `desktop add ID`, `desktop hide ID`, `desktop app
--- ID`, `desktop page N` and `desktop new-page`.
function M.verb(how, id)
  how = how or "state"
  if how == "edit" then model.set_editing(true) return true end
  if how == "done" then model.set_editing(false) return false end
  if how == "add" then return model.board.add(id) end
  if how == "hide" then model.board.hide(id) return true end
  if how == "size" then model.board.toggle_size(id) return true end
  if how == "app" then return model.toggle_app(id) end
  if how == "page" then model.page:set(tonumber(id) or 1) return model.current() end
  if how == "new-page" then return model.add_page() end
  if how == "state" then
    local out = {}
    for i, item in ipairs(model.everything()) do out[i] = item.id end
    return { editing = model.editing(), shown = out, host = wallpaper.painter() == "eva" and "wallpaper" or "own",
      home = model.home(), page = model.current(), pages = model.page_count() }
  end
  error("`" .. tostring(how) .. "`: edit, done, add, hide, size, app, page, new-page or state")
end

return M
