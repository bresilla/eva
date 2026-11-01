-- The wallpaper: which picture, and a background layer that paints it.
--
-- The picture is, first found: EVA_WALLPAPER, the setting `wallpaper.path` while
-- Lule has not made a new one since it was chosen, the one lule last made its
-- colours from (lib/lule: its colors.json, watched, so a new `lule create`
-- brings its picture along with its colours), or the path the eva tools keep in
-- ~/.local/state/eva/wallpaper/path.txt. `wallpaper.day` and `wallpaper.night`
-- stand in for it by the colour mode. Without one there is no layer at all, and
-- whatever already paints the desk shows through.
--
-- That picture is `M.current`, which the scheme follows. What this screen shows
-- is `M.picture()`: this workspace's own, this output's own, or the current one.
-- Only the layer can show those, and only the layer can animate a change: with
-- `wallpaper.draw` off, `M.painter()` says so and the compositor's tool paints.

local morf = require("morf")
local ui = require("morf.ui")
local config = require("config")
local theme = require("theme")

local M = {}

M.FITS = { crop = "preserve_aspect_crop", fit = "preserve_aspect_fit", stretch = "stretch" }

local function expand(path)
  if path:sub(1, 2) == "~/" then return morf.fs.home() .. path:sub(2) end
  return path
end

local function state_file()
  local base = (morf.env and morf.env("XDG_STATE_HOME")) or (morf.fs.home() .. "/.local/state")
  return base .. "/eva/wallpaper/path.txt"
end

M.current = morf.signal("eva.wallpaper", "")

local lule = require("lib.integrations.lule")
local lule_scheme = lule.watch("eva.wallpaper.lule")

-- The picture before the colour mode has its say.
local function chosen()
  local path = (morf.env and morf.env("EVA_WALLPAPER")) or ""
  if path ~= "" then return path end
  local scheme = lule_scheme:get()
  local tool, set = scheme and scheme.wallpaper or "", config.get("wallpaper.path")
  if set ~= "" and (tool == "" or config.get("wallpaper.pin") == tool) then return set end
  if tool ~= "" then return tool end
  if set ~= "" then return set end
  return (morf.fs.read(state_file()) or ""):match("^%s*(.-)%s*$") or ""
end

local function existing(path)
  path = expand(path or "")
  if path ~= "" and not morf.fs.exists(path) then
    morf.log("warn", "eva: no wallpaper at " .. path)
    return ""
  end
  return path
end

local function resolve()
  local tool = lule_scheme:get()
  local mode = require("themes.color_mode").resolve(tool and tool.theme)
  local timed = config.get(mode == "light" and "wallpaper.day" or "wallpaper.night")
  if timed ~= "" and existing(timed) ~= "" then return existing(timed) end
  return existing(chosen())
end

M.current:set(resolve())
-- lule changing its picture changes this one.
morf.effect("eva.wallpaper.follow", function()
  lule_scheme:get()
  local path=resolve()
  M.current:set(path)
  require("themes.wallpaper_handoff").publish(path,lule.path())
end)

--- The record of list setting `key` whose `field` is `value`.
local function record(key, field, value)
  for _, item in ipairs(config.get(key)) do
    if tostring(item[field]) == tostring(value) then return item end
  end
end
M.record = record

--- Sets or clears `path` for `value` in list setting `key`.
local function assign(key, field, value, path)
  local out = {}
  for _, item in ipairs(config.get(key)) do
    if tostring(item[field]) ~= tostring(value) then out[#out + 1] = item end
  end
  if path and path ~= "" then out[#out + 1] = { [field] = value, path = path } end
  config.set(key, out)
end

function M.output() return ((morf.screens or {})[1] or {}).name or "" end
function M.workspace() return require("services").workspace.active() end

--- What this screen shows now: tracked in a binding.
function M.picture()
  local own = record("wallpaper.workspaces", "workspace", M.workspace())
    or record("wallpaper.outputs", "output", M.output())
  local path = own and existing(own.path) or ""
  if path ~= "" then return path end
  return M.current:get()
end

--- Gives this output or workspace its own picture; "" takes it back.
function M.set_output(output, path) assign("wallpaper.outputs", "output", output, path) end
function M.set_workspace(workspace, path) assign("wallpaper.workspaces", "workspace", workspace, path) end

--- How `path` fills the screen.
function M.fit(path)
  local own = record("wallpaper.fits", "path", path or "")
  return own and own.fit or config.get("wallpaper.fit")
end
function M.set_fit(path, fit)
  if not M.FITS[fit] then return false end
  local out = {}
  for _, item in ipairs(config.get("wallpaper.fits")) do
    if item.path ~= path then out[#out + 1] = item end
  end
  out[#out + 1] = { path = path, fit = fit }
  config.set("wallpaper.fits", out)
  return true
end

--- Sets the picture (and the setting), and the scheme follows it. Lule's own
--- picture gives way until it makes another.
function M.set(path)
  local scheme = lule_scheme:get()
  config.set("wallpaper.pin", scheme and scheme.wallpaper or "")
  config.set("wallpaper.path", path)
  M.current:set(resolve())
end

-- ------------------------------------------------------------------ layer --

local layer, swap, hosts = nil, nil, {}
-- Where a change starts, in the screen's own pixels; nil is its middle.
M.origin = nil

--- Who paints the desk: "eva", "tool" (the compositor's own wallpaper tool) or
--- "none" (no picture and nothing asked to paint).
function M.painter()
  if config.get("wallpaper.draw") and (M.current:get() ~= "" or config.get("wallpaper.color") ~= "") then return "eva" end
  return M.current:get() ~= "" and "tool" or "none"
end

--- Whether this screen's layer is up.
function M.painting() return layer ~= nil end

--- `build(root)` runs for each layer that opens: what else lives on it.
function M.on_layer(build)
  hosts[#hosts + 1] = build
  if layer then build(layer.root_node) end
end

-- How far across the workspaces this one stands, 0 to 1.
local function along()
  local shown = math.max(2, tonumber(config.get("bar.workspaces.shown")) or 5)
  return ((M.workspace() - 1) % shown) / (shown - 1)
end

--- How wide the picture stands: wider than the screen by the parallax.
function M.overscan() return 1 + math.max(0, math.min(0.5, tonumber(config.get("wallpaper.parallax")) or 0)) end

--- A change of picture through the layer: what it was given, at the settings'
--- kind, length and softness. `kind` overrides the setting once.
function M.change(source, kind)
  if not swap then return end
  local w, h = require("workspace_wallpaper").screen_size()
  local at = M.origin or {}
  -- The plate may stand off the screen by the parallax: a change starts under
  -- the pointer on the screen all the same.
  local shift = (M.overscan() - 1) * w * along()
  swap.show(source, { kind = kind or config.get("wallpaper.transition.kind"), x = at.x and at.x + shift, y = at.y,
    width = math.floor(w * M.overscan()), height = h, time = config.get("wallpaper.transition.duration"),
    soft = config.get("wallpaper.transition.softness"), ease = theme.ease.emphasized,
    instant = config.get("appearance.reduce_motion") == true })
end

-- Prepares what `M.picture()` says off the render thread, then changes to it.
local function follow(first)
  local prepare = require("workspace_wallpaper")
  local release, wanted, token, shown_key = nil, nil, 0, nil
  morf.effect("eva.wallpaper.paint", function()
    local path = M.picture()
    local w, h, scale = prepare.screen_size()
    local key = path .. "\n" .. math.floor(w * M.overscan()) .. "x" .. h .. "@" .. scale
    if key == shown_key then return end
    shown_key, wanted = key, path
    token = token + 1
    local own = token
    local old = release
    if path == "" then
      if old then old() end
      release = nil
      M.change("", "fade")
      return
    end
    local function arrive(source)
      if own ~= token or not swap then return end
      local kind = first and not config.get("wallpaper.transition.startup") and "fade" or nil
      local instant_first = first and not config.get("wallpaper.transition.startup")
      first = false
      if instant_first then
        swap.show(source, { instant = true })
      else
        M.change(source, kind)
      end
      -- The picture on show stays held until the next has taken over.
      if old then morf.time.timer(config.get("wallpaper.transition.duration") + 200, old, false) end
    end
    release = prepare.prepare(path, math.floor(w * M.overscan()), h, scale, function(source) arrive(source or path) end)
    if not release then arrive(path) end
  end)
end

--- The pointer on the desktop, in the screen's own pixels: where a change
--- starts, and where the second picture shows through.
function M.pointer(x, y)
  M.origin = { x = x, y = y }
  local hole = M.pointer_hole
  if hole and layer then hole.x, hole.y = x - 140, y - 140 end
end

--- A background layer with the picture on it, opened once there is a
--- picture: without one the desk's own wallpaper is left alone. It comes and
--- goes with `wallpaper.draw`.
function M.open_layer()
  morf.effect("eva.wallpaper.layer", function()
    local wanted = M.painter() == "eva"
    if wanted and not layer then
      layer = M.layer()
      for _, build in ipairs(hosts) do build(layer.root_node) end
    elseif not wanted and layer then
      local gone = layer
      layer, swap = nil, nil
      gone.handle:destroy()
    end
  end)
end

function M.layer()
  local function fit_now() return M.FITS[M.fit(M.picture())] or M.FITS.crop end
  swap = require("themes.wallpaper_swap").new { id = "wallpaper", fit = fit_now }
  local plate = ui.Item {
    id = "wallpaper-plate", y = 0, height = function()
      morf.window.screens_revision()
      local _, h = require("workspace_wallpaper").screen_size()
      return h
    end,
    width = function()
      morf.window.screens_revision()
      local w = require("workspace_wallpaper").screen_size()
      return math.ceil(w * M.overscan())
    end,
    translate_x = function()
      local w = require("workspace_wallpaper").screen_size()
      return -(M.overscan() - 1) * w * along()
    end,
    behavior = { translate_x = theme.spring.slow },
    swap.node,
  }
  -- A second picture seen through the first, in a soft hole round the pointer.
  local hole = ui.SdfShape { id = "wallpaper-xray-hole", shape = "circle", width = 280, height = 280 }
  M.pointer_hole = hole
  local xray = ui.Image { id = "wallpaper-xray", anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
    source = function() return config.get("wallpaper.xray") end,
    visible = function() return config.get("wallpaper.xray") ~= "" end,
    mask = ui.Sdf { anchors = { fill = true }, softness = 32, hole } }
  -- Bright with every beat, in the palette's accent, while something plays.
  local media = require("media_state")
  media.hear(function() return config.get("wallpaper.glow") == true end)
  local glow = ui.Rect { id = "wallpaper-glow", anchors = { fill = true },
    visible = function() return config.get("wallpaper.glow") == true end,
    opacity = function() return media.pulse:get() * 0.35 end,
    behavior = { opacity = theme.spring.effects },
    gradient = function()
      local accent = theme.color.primary
      return { kind = "radial", radius = 0.7, stops = { accent:alpha(0), accent } }
    end }
  local root = ui.Item {
    anchors = { fill = true },
    ui.Rect { id = "wallpaper-ground", anchors = { fill = true }, color = function()
      local color = config.get("wallpaper.color")
      return color ~= "" and morf.color(color) or theme.color.surface
    end },
    plate, xray, glow,
  }
  local handle = morf.window.layer {
    blend = "srgb",
    namespace = "eva-wallpaper",
    layer = "background",
    anchors = { top = true, bottom = true, left = true, right = true },
    -- Zero on both axes: the output's size (a layer is 32 px tall unless
    -- told otherwise).
    width = 0, height = 0,
    exclusive_zone = -1,
    keyboard_focus = "none",
    visible = true,
    -- Opaque: a solid fill under the picture, so the compositor draws
    -- nothing of its own under it -- one full-screen layer fewer to blend
    -- on every redraw of whatever sits over it.
    opaque = true,
    root = root,
  }
  follow(true)
  return { handle = handle, root_node = root }
end

return M
