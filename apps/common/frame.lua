-- What a tool of apps/ draws with when it runs as a program of its own: the
-- shell's theme, kit and palette, the colours following lule and the appearance
-- following the shell's file. Its pages are the shell's Tools window's; on its
-- own a tool draws over the whole screen, with `frame.overlay`, or nothing at
-- all, with `frame.quiet`.
--
--     local frame = require("common.frame")
--     frame.quiet(true)
--     frame.overlay { id = "draw", root = node, close = function() morf.quit() end }
local morf = require("morf")
local config = require("config")
local theme = require("theme")
local themes = require("themes")
local terminal_colors = require("terminal_colors")

local M = {}

--- The Material scheme and lule's own colours, from what the colour tool made.
function M.follow_scheme()
  morf.effect("eva.app.lule", function() theme.apply_lule(terminal_colors.current:get()) end)
  morf.effect("eva.app.scheme", function()
    theme.track(terminal_colors.current:get(), config.get("wallpaper.path"))
  end)
end

--- A theme, a font, a motion or a density chosen elsewhere builds the tool
--- again in place, when `ready` (a fn, if any) says it may.
function M.follow_appearance(ready)
  local function look()
    local read = themes.preferences.get
    return table.concat({ read("theme"), read("font"), read("motion"), tostring(read("reduce_motion")),
      read("density"), tostring(read("corners")) }, "\n")
  end
  local built = look()
  morf.effect("eva.app.appearance", function()
    if look() ~= built and (not ready or ready()) then morf.reload() end
  end)
end

--- A surface over everything: `id`, `root` (fills it), `keyboard` ("exclusive"
--- by default), `visible` (true by default), `close` (fn: what a swipe in from
--- an edge does, the finger's Escape). Returns the surface.
function M.overlay(spec)
  if spec.close then
    local swipe = require("themes.swipe_dismiss").new { id = "overlay." .. spec.id, node = spec.root,
      ways = { left = true, right = true, up = true, down = true }, on_dismiss = spec.close }
    spec.root.on_edge_panned = function(_, ...) return swipe.on_panned(...) end
  end
  return morf.window.layer {
    blend = "srgb", namespace = "eva-" .. spec.id, layer = "overlay",
    anchors = { top = true, bottom = true, left = true, right = true },
    width = 0, height = 0, exclusive_zone = -1, keyboard_focus = spec.keyboard or "exclusive",
    visible = spec.visible ~= false, root = spec.root,
  }
end

--- Ends an overlay from anywhere, its own event handlers among them: the
--- surface goes at once and is taken apart on the next turn.
function M.dismiss(layer)
  layer:close()
  morf.time.timer(1, function() layer:destroy() end, false)
end

--- The configuration's own surface out of the way, for a tool that draws
--- nothing there; `follow` keeps the theme's colours for an overlay of its.
function M.quiet(follow)
  require("lib.util.job").quiet()
  if follow then M.follow_scheme() end
end

--- Sets what a second launch does to this tool: an overlay shuts, as a key
--- pressed twice would.
function M.on_second(action)
  morf.ipc["eva-raise"] = action
end

return M
