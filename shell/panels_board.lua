-- The board of pages: which panel holds which on this form (`panels.<edge>`),
-- as `tiles_model` keeps the quick tiles. State and actions only.
--
-- The panels are built from these sets, so a change lands when the page is
-- left: `on_page()` says whether it still is on show.
local morf = require("morf")
local config = require("config")
local pages = require("pages")
local M = {}

local NAMES = { right = "Right", left = "Left", bottom = "Bottom", top = "Sheet" }
-- Where a page added back goes: the panel it starts in.
local HOME = { settings = "right", notifications = "right", tasks = "left", calendar = "left",
  assistant = "bottom", drop = "bottom" }

local function index_of(list, key)
  for i, v in ipairs(list) do if v == key then return i end end
end

--- A board. `on_page()`: whether its page is on show.
function M.new(on_page)
  local board = { dirty = morf.signal("eva.panels.dirty", false) }

  --- The panels, in order: `{ edge, name, keys }`.
  function board.groups()
    local out = {}
    for _, edge in ipairs(pages.edges()) do
      out[#out + 1] = { edge = edge, name = NAMES[edge], keys = pages.keys(edge) }
    end
    return out
  end

  --- The pages no panel holds, in catalogue order.
  function board.spare()
    local out = {}
    for _, key in ipairs(pages.ORDER) do
      if not pages.panel_name(key) then out[#out + 1] = key end
    end
    return out
  end

  --- Whether `key` may leave every panel: Settings holds this page.
  function board.can_hide(key) return key ~= "settings" end

  local function write(edge, keys)
    config.set("panels." .. edge, keys)
    board.dirty:set(true)
  end

  local function without(edge, key)
    local out = {}
    for _, v in ipairs(pages.keys(edge)) do if v ~= key then out[#out + 1] = v end end
    return out
  end

  --- `key` into the panel on `edge`, at `index`.
  function board.place(key, edge, index)
    if not pages.all[key] then return false end
    local target = without(edge, key)
    for _, other in ipairs(pages.edges()) do
      if other ~= edge and index_of(pages.keys(other), key) then write(other, without(other, key)) end
    end
    table.insert(target, math.max(1, math.min(index or #target + 1, #target + 1)), key)
    write(edge, target)
    return true
  end

  --- `key` out of its panel, to the Available pages.
  function board.hide(key)
    if not board.can_hide(key) then return false end
    for _, edge in ipairs(pages.edges()) do
      if index_of(pages.keys(edge), key) then write(edge, without(edge, key)) end
    end
    return true
  end

  --- `key` back in a panel: the one it starts in, or the form's first.
  function board.add(key)
    local edges, edge = pages.edges(), HOME[key]
    if not index_of(edges, edge) then edge = edges[1] end
    return board.place(key, edge)
  end

  --- `key` a step along: within its panel, and past either end into the next.
  function board.step(key, delta)
    local groups = board.groups()
    for g, group in ipairs(groups) do
      local at = index_of(group.keys, key)
      if at then
        if group.keys[at + delta] then return board.place(key, group.edge, at + delta) end
        local next_group = groups[g + delta]
        if not next_group then return false end
        return board.place(key, next_group.edge, delta > 0 and 1 or #next_group.keys + 1)
      end
    end
    return false
  end

  --- This form's panels as they start.
  function board.reset()
    for _, edge in ipairs(pages.edges()) do config.reset("panels." .. edge) end
    board.dirty:set(true)
  end

  -- The settled sets build the shell again in place, what is open staying
  -- open; if Settings moved, it reopens where it now is.
  local moved = require("themes.session").keep("eva.panels.reopen", false)
  local function apply()
    local holder = pages.holder("settings")
    for _, name in ipairs { "sidebar", "leftbar", "bottom" } do
      local panel = package.loaded[name]
      if panel and panel ~= holder and panel.drawer.open:get() and panel.panel.showing("settings") then
        panel.drawer.set(false)
        moved:set(true)
      end
    end
    -- The rebuild reads the file: nothing may still be on its way there.
    config.flush()
    require("themes.session").hold()
    morf.reload()
  end
  morf.effect("eva.panels.apply", function()
    if board.dirty:get() and not on_page() then
      board.dirty:set(false)
      morf.time.timer(1, apply, false)
    end
  end)

  --- Opens Settings in its new panel, after a reload that moved it.
  function board.settle()
    if not moved:get() then return end
    moved:set(false)
    -- After the build: a drawer's motion wants its panel laid out.
    morf.time.timer(1, function() pages.open("settings") end, false)
  end

  return board
end

return M
