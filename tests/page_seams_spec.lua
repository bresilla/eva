-- The seams a page reaches the shell through: the panel system, the launcher,
-- the tiles, and which page takes the keyboard.
--     morf test --no-dbus tests/page_seams_spec.lua
local test = morf.test
local HOST = [[
  if morf.env("MOVED") == "1" then
    morf.fs.write(morf.env("EVA_SETTINGS"), '{ "panels": { "left": ["tasks", "calendar", "notes"] } }')
  end
  require("init")
  require("config").set("notes.folder", morf.env("NOTES_DIR"))
  morf.ipc.seam_state = function()
    local pages = require("pages")
    local utilities = require("utilities")
    return { left = require("leftbar").drawer.open:get(), left_notes = require("leftbar").panel.showing("notes"),
      bottom = require("bottom").drawer.open:get(), bottom_assistant = require("bottom").panel.showing("assistant"),
      sidebar = require("sidebar").drawer.open:get(), settings_page = utilities.displayed:get(), route = utilities.detail:get(),
      keyboard = morf.surface.keyboard_focus, typing = pages.typing(), tile_notes = utilities.CONTROLS.notes ~= nil,
      tile_phone = utilities.CONTROLS.phone ~= nil, phone_present = utilities.CONTROLS.phone.present() }
  end
  morf.ipc.seam_open = function(key) return require("pages").reach(key) end
  morf.ipc.seam_calendar_active = function() return require("pages").active("calendar")() end
  morf.ipc.seam_search = function(query)
    local rows = require("apps").search(query, 7) or {}
    local out = {}
    for i, row in ipairs(rows) do out[i] = { id = row.id, name = row.name, description = row.description } end
    return out
  end
  morf.ipc.seam_run = function(query) return require("apps").search(query, 7)[1].run() end
  morf.ipc.seam_note = function() return morf.fs.read(morf.env("NOTES_DIR") .. "/Quick notes.md") end
  morf.ipc.seam_tile = function(id) require("utilities").CONTROLS[id].set(true) end
]]
local count = 0
local function load(env, size)
  count = count + 1
  local dir = ("%s/seams-spec-%d-%d"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(dir)
  local w, h = (size or { 1920, 1080 })[1], (size or { 1920, 1080 })[2]
  local all = { EVA_STYLE = "material", EVA_DRY_RUN = "1", EVA_SETTINGS = dir .. "/eva.json", NOTES_DIR = dir .. "/notes",
    LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") }
  for name, value in pairs(env or {}) do all[name] = value end
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = all })
  test.settle(1000)
end
local function state() return test.ipc("seam_state") end

test.describe("page seams", function()
  test.it("lets a person move a page by naming it in a panel", function()
    load { MOVED = "1" }
    test.ipc("seam_open", "notes")
    test.settle(1200)
    local s = state()
    test.truthy(s.left, "the left panel holds it now")
    test.truthy(s.left_notes)
    test.truthy(test.get("notes-page").visible)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("opens a page no panel holds as a settings page", function()
    load()
    test.ipc("seam_open", "notes")
    test.settle(1200)
    local s = state()
    test.truthy(s.sidebar)
    test.eq(s.route, "notes")
    test.truthy(test.get("notes-page").visible)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("opens the assistant in the panel that holds it", function()
    load()
    test.ipc("seam_open", "assistant")
    test.settle(1200)
    local s = state()
    test.truthy(s.bottom)
    test.truthy(s.bottom_assistant)
  end)

  test.it("gives the keyboard to a page with a text field, and takes it back", function()
    load()
    test.eq(state().keyboard, "none")
    test.ipc("seam_open", "assistant")
    test.settle(1200)
    test.truthy(state().typing)
    test.eq(state().keyboard, "on_demand", "nobody could type in the assistant")
    test.ipc("close")
    test.settle(1200)
    test.eq(state().keyboard, "none")
    test.ipc("seam_open", "notes")
    test.settle(1200)
    test.eq(state().keyboard, "on_demand", "nobody could type a note")
  end)

  test.it("answers `ai` and `note` in the launcher, and leaves plain words alone", function()
    load()
    local rows = test.ipc("seam_search", "ai what is a monad")
    test.eq(#rows, 1)
    test.eq(rows[1].id, "word:ai")
    test.eq(rows[1].name, "what is a monad")
    test.truthy(rows[1].description:find("Not connected", 1, true), "it says nothing is connected")
    rows = test.ipc("seam_search", "note call the bank")
    test.eq(rows[1].id, "word:note")
    test.eq(test.ipc("seam_run", "note call the bank"), "close")
    test.truthy(test.ipc("seam_note"):find("call the bank", 1, true))
    for _, row in ipairs(test.ipc("seam_search", "ai")) do test.falsy(row.id == "word:ai") end
    for _, row in ipairs(test.ipc("seam_search", "aircraft manuals")) do test.falsy(row.id == "word:ai") end
  end)

  test.it("lists the pages in the launcher's system list", function()
    load()
    local names = {}
    for _, row in ipairs(test.ipc("seam_search", "!")) do names[row.id] = true end
    local more = test.ipc("seam_search", "!notes")
    test.truthy(more[1].id == "system:notes")
  end)

  test.it("has a Notes tile, and a Phone tile only with KDE Connect", function()
    load()
    local s = state()
    test.truthy(s.tile_notes)
    test.truthy(s.tile_phone)
    test.falsy(s.phone_present)
    test.ipc("seam_tile", "notes")
    test.settle(1200)
    test.eq(state().route, "notes")
    load { PATH = morf.env("PWD") .. "/tests/fixtures/bin-stand-in:" .. morf.env("PATH") }
    test.truthy(state().phone_present)
  end)

  test.it("activates the calendar in whichever panel holds it, a phone's sheet too", function()
    load({}, { 390, 844 })
    test.ipc("seam_open", "calendar")
    test.settle(1200)
    test.truthy(state().sidebar)
    test.truthy(test.ipc("seam_calendar_active"), "the page was on show and its model never knew")
    test.eq(#test.logs("error"), 0)
  end)

  test.it("opens a settings page for each new route", function()
    load()
    for _, route in ipairs { "assistant", "calendars", "notes", "phone" } do
      test.ipc("seam_open", route == "assistant" and "notes" or route)
      test.settle(600)
    end
    test.eq(#test.logs("error"), 0)
  end)
end)
