-- The session menu's rows hold their notes whole, in both themes.
--
--     morf test tests/session_fit_spec.lua

local test = morf.test

local function natural(style, text)
  test.load("../shell/init.lua", { size = { 800, 200 }, env = { EVA_STYLE = style }, source = ([[
    local ui = require("morf.ui")
    local kit = require("kit")
    ui.Item { width = 800, height = 200, kit.label { id = "natural", text = %q } }
  ]]):format(text) })
  test.settle(500)
  return test.get("natural").width
end

local function box(style, id)
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, env = { EVA_STYLE = style, EVA_DRY_RUN = "1",
    EVA_FONT_FILE = "", LULE_A = "/nonexistent/lule", HYPRLAND_INSTANCE_SIGNATURE = false }, source = [[
      require("services").here = function() return true end
      require("init")
    ]] })
  test.advance(1800)
  test.ipc("session", "open")
  test.settle(1000)
  return test.get(id).width
end

-- The notes of models/session_actions.lua, read from the file.
local function notes()
  local out = {}
  for note in morf.fs.read("models/session_actions.lua"):gmatch('detail = "([^"]+)"') do out[#out + 1] = note end
  return out
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": no note of a session row is cut off", function()
    local room = box(style, "session-lockdown-detail")
    local list = notes()
    test.truthy(#list > 5, "the notes were read")
    for _, note in ipairs(list) do
      test.truthy(natural(style, note) <= room, note .. " fits")
    end
  end)
end
