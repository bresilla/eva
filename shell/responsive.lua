-- How much screen there is, and what kind. The shell is drawn for a desk; on
-- a narrow screen (a phone held upright) its sizes give way: a panel never
-- wider than the desk between the frame's edges, and layouts that ask
-- `compact()` stack what sits side by side.
--
-- Each output has a width and a height class from its logical size, and a
-- form: phone or desk. `sheets()` is the one policy the panels share: they come
-- down over a phone's screen, and hang off a desk's sides.
local morf = require("morf")
local M = {}

-- Width classes: compact below 600, medium to 839, expanded from 840.
M.MEDIUM, M.EXPANDED = 600, 840
-- Height classes: compact below 480, medium to 899, expanded from 900.
M.MEDIUM_HEIGHT, M.EXPANDED_HEIGHT = 480, 900
-- A phone's panel: under this diagonal where it says so, else this long for
-- its width, and longer still past a short side a monitor can have.
local PHONE_DIAGONAL_MM, PHONE_ASPECT, PHONE_SHORT, PHONE_LONG_ASPECT = 190, 1.75, 1000, 1.9
-- A quick settings sheet where the screen has room to spare.
local SHEET_W = 560

local function output() return (morf.screens or {})[1] or {} end

--- The output's size, in the shell's pixels.
function M.size()
  local s = output()
  return s.width or 1920, s.height or 1080
end

-- Connectors a monitor hangs off, never the machine's own panel.
local EXTERNAL = { "^DP%-", "^HDMI", "^DVI", "^VGA", "^USB", "^Virtual" }
local function external()
  local name = output().name or ""
  for _, pattern in ipairs(EXTERNAL) do if name:match(pattern) then return true end end
  return false
end

local function read_input()
  local ok, touch = pcall(function()
    return require("models.touchscreens").attached() and not require("models.keyboards").attached()
  end)
  return ok and touch == true
end
local input = morf.signal("eva.input.touch", read_input())
local listeners = {}

--- `heard()` from here on, each time an input device comes or goes.
function M.on_input(heard) listeners[#listeners + 1] = heard end

--- Reads the input devices again as they come and go, and as the machine
--- folds (models.posture, which this panel's shell starts).
function M.watch_input()
  local posture = require("models.posture")
  if not external() then posture.start() end
  morf.effect("eva.input.posture", function() input:set(read_input()) end)
  if not (morf.udev and morf.udev.subscribe) then return end
  pcall(morf.udev.subscribe, "input", function()
    input:set(read_input())
    if not external() then posture.refresh() end
    for _, heard in ipairs(listeners) do heard() end
  end)
end

--- Whether a touchscreen is this output's main input: one is attached, no
--- keyboard is in reach, and the output is the machine's own panel.
function M.touch() return input:get() and not external() end

--- Whether the output is a phone's panel, in either orientation and at any
--- scale: by its diagonal where it reports one, else by its shape.
function M.phone()
  local s = output()
  local mm_w, mm_h = s.physical_width_mm or 0, s.physical_height_mm or 0
  if mm_w > 0 and mm_h > 0 then return math.sqrt(mm_w * mm_w + mm_h * mm_h) < PHONE_DIAGONAL_MM end
  local w, h = M.size()
  local short, long = math.min(w, h), math.max(w, h)
  if short <= 0 or long / short < (short < PHONE_SHORT and PHONE_ASPECT or PHONE_LONG_ASPECT) then return false end
  return h > w or M.touch()
end

--- compact, medium or expanded. A phone's panel is compact across its
--- narrow side at any scale.
function M.width_class()
  local w, h = M.size()
  if M.phone() then return h > w and "compact" or "expanded" end
  return w < M.MEDIUM and "compact" or w < M.EXPANDED and "medium" or "expanded"
end

--- compact, medium or expanded, as `width_class` for the other axis.
function M.height_class()
  local w, h = M.size()
  if M.phone() then return h > w and "expanded" or "compact" end
  return h < M.MEDIUM_HEIGHT and "compact" or h < M.EXPANDED_HEIGHT and "medium" or "expanded"
end

--- phone or desk: what the output is used as. A touchscreen changes nothing:
--- an upright output too narrow for a desk's sides is a phone, the rest a desk.
function M.form()
  local class = M.width_class()
  if class == "compact" or M.phone() then return "phone" end
  return class == "medium" and M.portrait() and "phone" or "desk"
end

--- Whether the panels come down as sheets and the edges belong to gestures.
function M.sheets() return M.form() ~= "desk" end

--- The size of a pressable thing: a finger's in touch mode, else a pointer's.
function M.target()
  local space = require("themes.spacing")
  return M.sheets() and space.TOUCH or space.TARGET
end

--- What a layout is built for: a change rebuilds the output's shell in place.
function M.layout()
  return table.concat({ M.form(), M.width_class(), M.height_class(), M.portrait() and "upright" or "wide",
    M.touch() and "touch" or "keys" }, "/")
end

--- How wide a sheet from the top is: the desk on a phone held upright, a
--- panel where there is room beside it.
function M.panel_width()
  local full = M.sheet_width()
  return M.width_class() == "compact" and full or math.min(full, SHEET_W)
end

--- How tall that sheet may be, of a desk `h` tall: four fifths when it spans
--- the desk, all of it as a panel in the corner.
function M.panel_height(h)
  local room = h - 2 * require("theme").BORDER
  return M.width_class() == "compact" and math.floor(room * 0.8) or room
end

--- Where that sheet hangs: from the middle on a phone held upright, else
--- in the corner under the status it was pulled from.
function M.panel_anchors()
  if M.width_class() == "compact" then return { top = true, horizontal_center = true } end
  return { top = true, right = true }
end

-- A cutout from EVA_FAKE_CUTOUT ("x,width,height") or the settings, in the
-- panel's natural upright orientation.
local function natural_cutout()
  local spec = morf.env and morf.env("EVA_FAKE_CUTOUT")
  if spec and spec ~= "" then
    local x, width, height = spec:match("(%d+),(%d+),(%d+)")
    if x then return { x = tonumber(x), width = tonumber(width), height = tonumber(height) } end
  end
  local ok, cut = pcall(function() return require("config").get("edgebar.cutout") end)
  return ok and type(cut) == "table" and (tonumber(cut.width) or 0) > 0 and cut or nil
end

--- The cutout as this orientation has it: `{ x, y, width, height }`, or nil.
function M.cutout()
  local cut = natural_cutout()
  if not cut then return nil end
  local w, h = M.size()
  local transform = output().transform or "normal"
  if transform:match("180") then return { x = w - cut.x - cut.width, y = h - cut.height, width = cut.width, height = cut.height } end
  if transform:match("90") then return { x = 0, y = cut.x, width = cut.height, height = cut.width } end
  if transform:match("270") then return { x = w - cut.height, y = h - cut.x - cut.width, width = cut.height, height = cut.width } end
  return { x = cut.x, y = 0, width = cut.width, height = cut.height }
end

--- What the screen's rounded corners take from either end of a bar:
--- `edgebar.corner`, else a phone's in proportion to its short side.
function M.corner()
  local ok, set = pcall(function() return require("config").get("edgebar.corner") end)
  set = ok and tonumber(set) or 0
  if set > 0 then return set end
  local w, h = M.size()
  return M.phone() and math.floor(math.min(w, h) * 0.045) or 34
end

--- The bar's row, clear of corners and cutout: `left`, `right`, and `gap_from`
--- and `gap_to` when a cutout splits it. `thick` is how far down the row goes.
function M.lanes(thick)
  local w = M.size()
  local inset = math.max(M.corner(), require("theme").BORDER + require("theme").ROUNDING - 1)
  local lanes = { left = inset, right = w - inset }
  local cut = M.cutout()
  if not cut or cut.y >= thick then return lanes end
  local margin = require("themes.spacing").s
  local from, to = cut.x - margin, cut.x + cut.width + margin
  if to <= w / 3 then lanes.left = math.max(lanes.left, to)
  elseif from >= 2 * w / 3 then lanes.right = math.min(lanes.right, from)
  else lanes.gap_from, lanes.gap_to = from, to end
  return lanes
end

--- The desk's width: the screen inside the frame and any bar.
function M.desk_width()
  local _, _, w = require("bar").desk()
  return w or 1920
end

--- The desk's height.
function M.desk_height()
  local _, _, _, h = require("bar").desk()
  return h or 1080
end

--- `design`, or less: as wide as the desk leaves with `margin` each side.
function M.fit(design, margin)
  return math.max(0, math.min(design, M.desk_width() - 2 * (margin or 12)))
end

--- Whether the desk is too narrow for a page's columns side by side, or
--- upright: a phone's, at any scale.
function M.compact()
  -- Upright is a phone's however small the shell is drawn on it.
  return M.desk_width() < 1000 or M.portrait()
end

--- What kind of machine this is, by the name the tile board keeps its sets
--- under: `form()`.
function M.form_factor() return M.form() end

--- How wide a dashboard page is on a phone: the desk inside the frame,
--- less the drawer's padding.
function M.sheet_width()
  local theme = require("theme")
  return math.max(1, M.desk_width() - 2 * theme.BORDER - 2 * theme.ROUNDING)
end

function M.page_width()
  local panel = M.portrait() and M.sheet_width() or M.desk_width() - 2 * require("theme").BORDER
  return math.max(1, panel - 2 * 16)
end

--- How tall: the desk inside the frame, less the tabs and the padding.
function M.page_height()
  return M.desk_height() - 2 * require("theme").BORDER - 68 - 2 * 16
end

-- Each dashboard tab's own page on a desk (the drawer eases from one to
-- the next): its width and height.
local DASHBOARD = {
  overview = { 1100, 600 }, media = { 1000, 400 }, battery = { 1040, 520 },
  weather = { 838, 561 },
}

--- The dashboard page of tab `key`: its width and height. On a phone every
--- tab is the desk less the tabs and a page's head (four fifths of it, the
--- rest to tap it shut), and scrolls; on a desk each tab has its own size.
function M.dashboard(key)
  local theme = require("theme")
  local TABS_H, PAD = 68, 16
  if M.compact() then
    local panel_h = math.floor((M.desk_height() - 2 * theme.BORDER) * 0.8)
    -- (Less a page's head: a phone's tabs are icons, so each page is named.)
    local P = require("themes.layouts.page")
    return M.page_width(), panel_h - TABS_H - 2 * PAD - P.HEADER_H - P.GAP
  end
  -- The big ones (performance, the terminal) take as much of the screen as
  -- sits well.
  if key == "performance" or key == "terminal" then
    local sw, sh = M.desk_width(), M.desk_height()
    return math.max(960, math.min(1400, sw - 2 * theme.BORDER - 2 * PAD - 2 * 40)),
      math.max(560, math.min(760, sh - 2 * theme.BORDER - TABS_H - 2 * PAD - 40))
  end
  local size = DASHBOARD[key] or DASHBOARD.overview
  return M.fit(size[1], 40), size[2]
end

--- Whether the screen stands upright (a phone): the workspaces run along
--- the bottom edge, and what a desk keeps on its side edges gives way.
function M.portrait()
  local s = require("morf").screens[1]
  local w, h = (s and s.width) or 1920, (s and s.height) or 1080
  return h > w
end

return M
