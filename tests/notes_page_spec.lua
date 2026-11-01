-- Quick notes: plain files, written after the typing stops.
--     morf test --no-dbus tests/notes_page_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  local config, model = require("config"), require("notes_model")
  config.set("notes.folder", morf.env("NOTES_DIR"))
  local shown = morf.signal("notes.spec.shown", false)
  local active = function() return shown:get() end
  ui.Item { width = W, height = H, require("notes_page").build(active, W, function() return H end) }
  morf.ipc.show = function(on) shown:set(on == "yes") end
  morf.ipc.state = function()
    local rows = {}
    for i = 1, model.rows:len() do rows[i] = model.rows:get(i).name end
    return { rows = rows, selected = model.selected:get(), text = model.text:get(), said = model.said:get(), deleting = model.deleting:get() }
  end
  morf.ipc.create = model.create
  morf.ipc.open = model.open
  morf.ipc.close = model.close
  morf.ipc.edit = model.edited
  morf.ipc.quick = model.quick
  morf.ipc.delete = model.delete
  morf.ipc.search = model.search
  morf.ipc.flush = model.flush
]]
local count = 0
local dir
local function load(style, size)
  count = count + 1
  dir = ("%s/notes-spec-%d-%d/notes"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(dir)
  local w, h = (size or { 408, 900 })[1], (size or { 408, 900 })[2]
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = { EVA_STYLE = style or "material",
    NOTES_DIR = dir, EVA_SETTINGS = dir .. "/../eva.json", TEST_WIDTH = tostring(w), TEST_HEIGHT = tostring(h) } })
  test.ipc("show", "yes")
  test.advance(50)
end
local function state() return test.ipc("state") end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end

test.describe("notes", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. " says where notes live while there are none", function()
      load(style)
      test.truthy(test.get("notes-empty").visible)
      test.truthy(test.find { text = "Nothing written yet" })
      test.ipc("create", "Ideas")
      test.advance(50)
      test.truthy(test.get("notes-editor").visible)
      test.falsy(test.get("notes-list").visible, "the list stayed behind the note")
      shot(style .. "-notes")
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("makes a plain file and writes after the typing stops", function()
    load()
    test.eq(test.ipc("create", "Shopping list"), "Shopping list.md")
    test.truthy(morf.fs.exists(dir .. "/Shopping list.md"))
    test.ipc("edit", "milk\neggs")
    test.eq(state().said, "Saving…")
    test.eq(morf.fs.read(dir .. "/Shopping list.md"), "", "not yet")
    test.advance(600)
    test.eq(morf.fs.read(dir .. "/Shopping list.md"), "milk\neggs")
    test.eq(state().said, "Saved")
  end)

  test.it("writes what is unsaved on leaving a note", function()
    load()
    test.ipc("create", "One")
    test.ipc("edit", "typed fast")
    test.ipc("close")
    test.eq(morf.fs.read(dir .. "/One.md"), "typed fast")
  end)

  test.it("writes what is unsaved when the page goes away", function()
    load()
    test.ipc("create", "One")
    test.ipc("edit", "typed fast")
    test.ipc("show", "no")
    test.advance(20)
    test.eq(morf.fs.read(dir .. "/One.md"), "typed fast")
  end)

  test.it("keeps names inside the folder", function()
    load()
    test.eq(test.ipc("create", "../../etc/passwd"), "etc passwd.md")
    test.falsy(test.ipc("open", "../eva.json"))
    test.eq(state().selected, "etc passwd.md")
  end)

  test.it("opens what exists rather than overwriting it", function()
    load()
    morf.fs.write(dir .. "/Kept.md", "keep me")
    test.ipc("create", "Kept")
    test.eq(state().text, "keep me")
    test.eq(morf.fs.read(dir .. "/Kept.md"), "keep me")
  end)

  test.it("takes a line from the launcher with its time", function()
    load()
    test.truthy(test.ipc("quick", "call the bank"))
    test.ipc("quick", "buy stamps")
    local text = morf.fs.read(dir .. "/Quick notes.md")
    test.truthy(text:find("call the bank", 1, true))
    test.truthy(text:find("buy stamps", 1, true))
    test.eq(select(2, text:gsub("\n", "\n")), 2)
    test.falsy(test.ipc("quick", "   "))
  end)

  test.it("lists only notes, newest first, and finds by name", function()
    load()
    morf.fs.write(dir .. "/a.md", "")
    morf.fs.write(dir .. "/b.txt", "")
    morf.fs.write(dir .. "/picture.png", "")
    test.ipc("search", "")
    test.eq(#state().rows, 2)
    test.ipc("search", "b.t")
    test.eq(state().rows, { "b.txt" })
  end)

  test.it("deletes on the second press", function()
    load()
    test.ipc("create", "Gone")
    test.falsy(test.ipc("delete", "Gone.md"))
    test.truthy(morf.fs.exists(dir .. "/Gone.md"))
    test.eq(state().deleting, "Gone.md")
    test.truthy(test.ipc("delete", "Gone.md"))
    test.falsy(morf.fs.exists(dir .. "/Gone.md"))
    test.eq(state().selected, "")
  end)

  test.it("follows a note another program changes", function()
    load()
    test.ipc("create", "Shared")
    morf.fs.write(dir .. "/Shared.md", "from outside")
    test.wait(function() test.advance(30) return state().text == "from outside" end, 3000, "the outside edit")
  end)

  test.it("fits a phone", function()
    load("material", { 390, 780 })
    test.ipc("create", "On a phone")
    test.advance(50)
    test.truthy(test.get("notes-text").width <= 390)
    shot("phone-notes")
  end)
end)
