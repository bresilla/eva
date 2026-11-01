-- Workspaces move: to another screen, trading places, shifting along, from the
-- model and from the overview's desks. The stand-in compositor here;
-- nix/tests/windows.py does the same with two screens on Hyprland 0.55.4.
--
--     morf test --no-dbus tests/workspaces_move_spec.lua

local test = morf.test

local HOST = [[
  require("init")
  local spaces = require("workspaces_model")
  local windows = require("windows_model")
  local overview = require("overview")
  morf.ipc.on = function(id)
    local out = {}
    for _, c in ipairs(windows.on(tonumber(id))) do out[#out + 1] = c.title end
    table.sort(out)
    return out
  end
  morf.ipc.name_of = function(id) return spaces.name(tonumber(id)) end
  morf.ipc.layout_of = function(id) return spaces.layout(tonumber(id)) end
  morf.ipc.actions = function(id)
    local out = {}
    for _, item in ipairs(overview.desk_actions(tonumber(id))) do out[#out + 1] = item.label end
    return out
  end
  morf.ipc.act = function(id, label)
    for _, item in ipairs(overview.desk_actions(tonumber(id))) do
      if item.label == label then item.run() return true end
    end
    return false
  end
  morf.ipc.drag = function(from, to)
    local box = overview.strip:get()[to]
    overview.desk_drag_start(tonumber(from), 0, 0)
    overview.desk_drag_move(box.x + 2, box.y + 2)
    return overview.desk_drag_end()
  end
  morf.ipc.menu = function(id) overview.desk_menu:set(tonumber(id)) return true end
]]

local function load(scene)
  local settings = morf.env("XDG_CACHE_HOME") .. "/workspaces-move.json"
  morf.fs.remove(settings)
  test.load("../shell/init.lua", { source = HOST, size = { 1920, 1080 }, env = { EVA_SETTINGS = settings, EVA_DRY_RUN = "1",
    EVA_FAKE_WINDOWS = scene or "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(800)
end

local function wire()
  return table.concat(test.ipc("windows", "wire"), "\n")
end

test.it("a workspace goes to another screen in the words Hyprland took", function()
  load()
  test.ipc("workspace_move", 3, "DP-9") test.settle(100)
  test.contains(wire(), 'hl.dispatch(hl.dsp.workspace.move({ workspace = 3, monitor = "DP-9" }))')
  test.eq(#test.logs("warn"), 0)
end)

test.it("two screens trade what they show", function()
  load()
  test.ipc("workspace_screens", "DP-1", "DP-9") test.settle(100)
  test.contains(wire(), 'hl.dsp.workspace.swap_monitors({ monitor1 = "DP-1", monitor2 = "DP-9" })')
end)

test.it("two workspaces trade windows, names and layouts", function()
  load()
  test.ipc("workspace_name", "code", 1) test.settle(50)
  test.ipc("workspace_layout", "master", 1) test.settle(50)
  local one, three = test.ipc("on", 1), test.ipc("on", 3)
  test.eq(test.ipc("workspace_swap", 1, 3), true)
  test.settle(200)
  test.eq(test.ipc("on", 3), one)
  test.eq(test.ipc("on", 1), three)
  test.eq(test.ipc("name_of", 3), "code")
  test.eq(test.ipc("name_of", 1), "")
  test.eq(test.ipc("layout_of", 3), "master")
end)

test.it("a workspace moved along shifts those between, and nothing is lost", function()
  load()
  local one, two, three = test.ipc("on", 1), test.ipc("on", 2), test.ipc("on", 3)
  test.eq(test.ipc("workspace_reorder", 1, 3), true)
  test.settle(200)
  test.eq(test.ipc("on", 3), one)
  test.eq(test.ipc("on", 1), two)
  test.eq(test.ipc("on", 2), three)
end)

test.it("onto itself nothing happens", function()
  load()
  test.eq(test.ipc("workspace_swap", 2, 2), false)
  test.eq(test.ipc("workspace_reorder", 2, 2), false)
end)

test.it("a desk's menu offers what its place allows", function()
  load()
  test.ipc("overview", "open") test.settle(600)
  local labels = table.concat(test.ipc("actions", 2), ",")
  test.contains(labels, "Move left")
  test.contains(labels, "Move right")
  test.contains(labels, "Swap with 1")
  test.falsy(labels:find("Move to", 1, true), "one screen has nowhere to move to")
  local before = test.ipc("on", 2)
  test.truthy(test.ipc("act", 2, "Move right"))
  test.settle(200)
  test.eq(test.ipc("on", 3), before)
end)

test.it("with a second screen a desk can go there", function()
  load('{"second_monitor":true,"workspaces":[{"id":1},{"id":2}],"clients":[{"class":"kitty","title":"one","workspace":1},{"class":"kitty","title":"two","workspace":2}],"places":{},"focus":1}')
  test.ipc("overview", "open") test.settle(600)
  local labels = table.concat(test.ipc("actions", 1), ",")
  test.contains(labels, "Move to DP-9")
  test.contains(labels, "Swap screens with DP-9")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": a right press opens a desk's menu, and a desk dragged takes the place dropped on", function()
    local settings = morf.env("XDG_CACHE_HOME") .. "/workspaces-move-" .. style .. ".json"
    morf.fs.remove(settings)
    test.load("../shell/init.lua", { source = HOST, size = { 1920, 1080 }, env = { EVA_STYLE = style, EVA_SETTINGS = settings, EVA_DRY_RUN = "1",
      EVA_FAKE_WINDOWS = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") } })
    test.settle(800)
    test.ipc("overview", "open") test.settle(600)
    test.ipc("menu", 2) test.settle(300)
    test.truthy(test.find { id = "overview-desk-menu", visible = true })
    test.ipc("menu", 0) test.settle(300)
    local before = test.ipc("on", 1)
    test.eq(test.ipc("drag", 1, "2"), true)
    test.settle(200)
    test.eq(test.ipc("on", 2), before)
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": a real pointer drags a desk, and its right press opens the menu", function()
    local settings = morf.env("XDG_CACHE_HOME") .. "/workspaces-pointer-" .. style .. ".json"
    morf.fs.remove(settings)
    test.load("../shell/init.lua", { source = HOST, size = { 1920, 1080 }, env = { EVA_STYLE = style, EVA_SETTINGS = settings, EVA_DRY_RUN = "1",
      EVA_FAKE_WINDOWS = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") } })
    test.settle(800)
    test.ipc("overview", "open") test.settle(900)
    local first, third = test.get("overview-desk-1"), test.get("overview-desk-3")
    local windows = test.ipc("on", 1)
    test.drag({ first.x + first.width / 2, first.y + first.height / 2 }, { third.x + third.width / 2, third.y + third.height / 2 }, { steps = 8 })
    test.settle(300)
    test.eq(test.ipc("on", 3), windows, "the windows took the place dropped on")
    local second = test.get("overview-desk-2")
    test.drag({ second.x + 10, second.y + 10 }, { second.x + 10, second.y + 10 }, { button = "right", steps = 1 })
    test.settle(300)
    test.truthy(test.find { id = "overview-desk-menu", visible = true })
  end)
end
