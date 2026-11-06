-- Settings, Eva, Panels: pages moved between panels the way quick tiles move,
-- saved as they move, landing when the page is left.
local test = morf.test
local SOURCE = [[
  local reloads = 0
  morf.reload = function() reloads = reloads + 1 end
  require("init")
  local pages = require("pages")
  morf.ipc.sets = function()
    local out = {}
    for _, edge in ipairs(pages.edges()) do out[edge] = pages.keys(edge) end
    return out
  end
  morf.ipc.board = function() return { spare = require("utilities").panels.spare(), reloads = reloads,
    dirty = require("utilities").panels.dirty:get() } end
  morf.ipc.step = function(key, delta) return require("utilities").panels.step(key, tonumber(delta)) end
  morf.ipc.settings_path = function() return require("config").path end
  morf.ipc.showing = function()
    local holder = pages.holder("settings")
    return { settings = pages.on_show("settings"), left = holder == package.loaded.leftbar,
      right_open = require("drawer").sidebar.open:get(), detail = require("utilities").detail:get(),
      window = require("utilities").opened:get() }
  end
]]
local loads = 0
local function load(style, size, touch)
  -- (Stubs last the file, and the verb that sets them does not last a reload.)
  if loads == 0 then test.stub_run("task", { code = 0, stdout = "[]" }) end
  loads = loads + 1
  local env = { EVA_STYLE = style, EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1",
    LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"),
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/board-" .. loads .. ".json" }
  if touch then env.EVA_INPUT_DEVICES = morf.env("PWD") .. "/tests/fixtures/input-devices-touch" end
  test.load("../shell/init.lua", { size = size or { 1920, 1080 }, source = SOURCE, env = env })
  test.settle(1000)
end
-- A real reload in place. It keeps a process's environment; `test.reload`
-- starts from the spec's, so what `load` gave it is given again.
local function rebuild(style)
  local kept = ([[
    local env = morf.env
    local kept = { EVA_SETTINGS = %q, EVA_STYLE = %q, EVA_DRY_RUN = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "",
      LULE_A = "/nonexistent/lule", HOME = %q }
    morf.env = function(name)
      if kept[name] ~= nil then return kept[name] end
      return env(name)
    end
  ]]):format(test.ipc("settings_path"), style, morf.env("XDG_CACHE_HOME"))
  test.truthy(test.reload { source = kept .. SOURCE }, "the reload failed")
  test.settle(1400)
end
local function open_page() test.ipc("settings", "panels") test.settle(1600) end
local function sets() return test.ipc("sets") end
local function centre(id) local n = test.get(id) return n.x + n.width / 2, n.y + n.height / 2 end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " opens from the Eva page and shows every panel of a desk", function()
    load(style)
    test.ipc("settings", "eva") test.settle(1400)
    test.click("settings-eva-arrange") test.settle(1400)
    test.truthy(test.get("panels-board").visible)
    for _, key in ipairs { "settings", "notifications", "tasks", "calendar", "assistant", "drop" } do
      test.truthy(test.get("panels-tile-" .. key).visible, key)
    end
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " offers Notes and Phone to any panel, and moves one in", function()
    load(style)
    open_page()
    test.truthy(test.get("panels-add-notes").visible)
    test.truthy(test.get("panels-add-linked_phone").visible)
    test.click("panels-add-notes") test.settle(700)
    test.eq(test.ipc("board").spare, { "linked_phone" })
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " takes a page off a panel to Available, and brings it back", function()
    load(style)
    open_page()
    test.click("panels-hide-drop") test.settle(700)
    test.eq(sets().bottom, { "assistant" })
    test.eq(test.ipc("board").spare, { "drop", "notes", "linked_phone" })
    test.click("panels-add-drop") test.settle(700)
    test.eq(sets().bottom, { "assistant", "drop" })
    test.eq(test.ipc("board").spare, { "notes", "linked_phone" })
  end)

  test.it(style .. " has no way to take Settings off every panel", function()
    load(style)
    open_page()
    test.falsy(test.find { id = "panels-hide-settings", visible = true })
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " drags a page to another panel", function()
    load(style)
    open_page()
    local from_x, from_y = centre("panels-tile-tasks")
    local to_x, to_y = centre("panels-tile-drop")
    test.drag({ from_x, from_y }, { to_x, to_y }, { steps = 12 }) test.settle(900)
    test.eq(sets().left, { "calendar" })
    local held = false
    for _, key in ipairs(sets().bottom) do held = held or key == "tasks" end
    test.truthy(held, "the page did not reach the bottom panel")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("walks a page by keys, within a panel and on into the next", function()
  load("material")
  open_page()
  test.truthy(test.ipc("step", "tasks", 1))
  test.eq(sets().left, { "calendar", "tasks" })
  test.truthy(test.ipc("step", "tasks", 1))
  test.eq(sets().left, { "calendar" })
  test.eq(sets().bottom, { "tasks", "assistant", "drop" })
  test.truthy(test.ipc("step", "tasks", -1))
  test.eq(sets().left, { "calendar", "tasks" })
end)

test.it("Tab reaches a tile, and Alt with the arrows walks it", function()
  load("material")
  open_page()
  local focused
  for _ = 1, 60 do
    test.key("Tab") test.advance(16)
    focused = test.find(function(n) return n.focused and (n.id or ""):match("^panels%-tile%-") end)
    if focused then break end
    local stray = test.find(function(n) return n.focused and (n.id or ""):match("^utilities%-") end)
    test.falsy(stray, "Tab stopped on the overview that slid away")
  end
  test.truthy(focused, "Tab never reached a tile")
  local key = focused.id:match("^panels%-tile%-(.+)$")
  local function flat()
    local out = {}
    for _, edge in ipairs { "right", "left", "bottom" } do
      for _, held in ipairs(sets()[edge]) do out[#out + 1] = held end
    end
    return out
  end
  local function at()
    for i, held in ipairs(flat()) do if held == key then return i end end
  end
  local before = at()
  test.key("Right", "alt") test.settle(300)
  test.eq(at(), before + 1, "Alt+Right did not walk it")
  test.key("Left", "alt") test.settle(300)
  test.eq(at(), before, "Alt+Left did not walk it back")
end)

test.it("resets this form's panels", function()
  load("material")
  open_page()
  test.click("panels-hide-drop") test.settle(500)
  test.click("panels-reset") test.settle(500)
  test.eq(sets().bottom, { "assistant", "drop" })
end)

test.it("lands when the page is left, not while it is being arranged", function()
  load("material")
  open_page()
  test.click("panels-hide-drop") test.settle(500)
  test.eq(test.ipc("board").reloads, 0, "the shell was rebuilt under the board")
  test.click("settings-back") test.settle(900)
  test.eq(test.ipc("board").reloads, 1)
  test.falsy(test.ipc("board").dirty)
end)

test.it("lands too when the panel is shut on the page, and not at all with nothing changed", function()
  load("material")
  open_page()
  test.ipc("close") test.settle(900)
  test.eq(test.ipc("board").reloads, 0, "nothing changed, nothing to build")
  open_page()
  test.click("panels-hide-drop") test.settle(500)
  test.ipc("close") test.settle(900)
  test.eq(test.ipc("board").reloads, 1)
end)

test.it("moves the quick controls to another panel, the window staying where it is", function()
  load("material")
  open_page()
  test.ipc("step", "notifications", 1)
  test.ipc("step", "settings", 1)
  test.eq(sets().left[1], "settings")
  test.click("settings-back") test.settle(900)
  test.eq(test.ipc("board").reloads, 1)
  test.truthy(test.ipc("showing").window, "the Settings window shut as the panels moved")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " a real rebuild gives the panels their new pages, what was open staying open", function()
    load(style)
    open_page()
    test.click("panels-hide-drop") test.settle(500)
    test.click("settings-back") test.settle(900)
    test.eq(test.ipc("board").reloads, 1)
    rebuild(style)
    test.truthy(test.find { id = "bottom-tab-assistant" })
    test.falsy(test.find { id = "bottom-tab-drop" }, "the bottom panel kept the page it gave up")
    local now = test.ipc("showing")
    test.truthy(now.window, "Settings shut in the rebuild")
    test.eq(now.detail, "eva", "Settings lost its place")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " a real rebuild hands the quick controls to the panel they moved to", function()
    load(style)
    open_page()
    test.ipc("step", "notifications", 1)
    test.ipc("step", "settings", 1)
    test.click("settings-back") test.settle(900)
    rebuild(style)
    local now = test.ipc("showing")
    test.truthy(now.left, "Settings did not move")
    test.truthy(now.window, "the Settings window shut in the rebuild")
    test.falsy(now.right_open, "the panel it left opened")
    test.ipc("settings") test.settle(1200)
    test.truthy(test.ipc("showing").settings, "the quick controls did not open where they went")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " a sheet arranges its one panel", function()
    load(style, { 868, 1932 }, true)
    open_page()
    test.eq(sets().top, { "notifications", "tasks", "calendar", "assistant", "drop", "settings" })
    test.click("panels-hide-assistant") test.settle(600)
    test.eq(sets().top, { "notifications", "tasks", "calendar", "drop", "settings" })
    test.eq(sets().left, nil, "a sheet has no left panel to arrange")
    test.eq(#test.logs("error"), 0)
  end)
end
