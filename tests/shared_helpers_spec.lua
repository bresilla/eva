-- Helpers the shell shares, each in one place: what they answer, and no second
-- copy beside them.
--
--     morf test --no-dbus tests/shared_helpers_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local common = require("themes.kit_common")
  local text = require("themes.notification_text")
  morf.ipc.grouped = function(v) return common.grouped(tonumber(v) or v) end
  morf.ipc.decimal = function(v) return common.decimal_bytes(tonumber(v) or v) end
  morf.ipc.nothing = function() return { common.grouped(nil), common.decimal_bytes(nil), common.stamp(nil) } end
  morf.ipc.stamp = function(v) return common.stamp(v) end
  morf.ipc.trimmed = function(v) return common.trim_number(tonumber(v)) end
  morf.ipc.ago = function(seconds) return text.ago(1000, 1000 + tonumber(seconds)) end
  morf.ipc.expand = function(path) return { require("lib.integrations.lule").expand(path), morf.fs.home() } end
  morf.ipc.capture_expand = function(path) return select("#", require("lib.shell.capture").expand(path)) end
  morf.ipc.quoted = function(v) return require("lib.shell.window_dispatch").quoted(v) end
  morf.ipc.sizes = function()
    local performance = require("performance_model")
    return { performance.size_text(1536), performance.bytes == common.bytes }
  end
]]

local function load()
  test.load("../shell/init.lua", { size = { 100, 100 }, source = HOST, env = { EVA_DRY_RUN = "1" } })
  test.advance(50)
end

test.it("numbers are grouped by thousands, with a decimal where they have one", function()
  load()
  test.eq(test.ipc("grouped", "1234567"), "1,234,567")
  test.eq(test.ipc("grouped", "-1234"), "-1,234")
  test.eq(test.ipc("grouped", "999"), "999")
  test.eq(test.ipc("grouped", "1.5"), "1.5")
  test.eq(test.ipc("grouped", "words"), "words")
end)

test.it("bytes read in decimal units, and a word stands as it is", function()
  load()
  test.eq(test.ipc("decimal", "999"), "999 B")
  test.eq(test.ipc("decimal", "1500"), "1.5 kB")
  test.eq(test.ipc("decimal", "2500000"), "2.5 MB")
  test.eq(test.ipc("decimal", "many"), "many")
end)

test.it("nothing reads as nothing", function()
  load()
  test.eq(test.ipc("nothing"), { "", "", "" })
end)

test.it("a stamp that is no number stands as it is", function()
  load()
  test.eq(test.ipc("stamp", "yesterday"), "yesterday")
end)

test.it("a number loses its trailing zeros", function()
  load()
  test.eq(test.ipc("trimmed", "1.50"), "1.5")
  test.eq(test.ipc("trimmed", "2"), "2")
  test.eq(test.ipc("trimmed", "0.125"), "0.12")
end)

test.it("an age reads from a given now", function()
  load()
  test.eq(test.ipc("ago", "10"), "now")
  test.eq(test.ipc("ago", "120"), "2m")
  test.eq(test.ipc("ago", "7200"), "2h")
  test.eq(test.ipc("ago", "172800"), "2d")
end)

test.it("a leading tilde is the home folder, alone or before a path", function()
  load()
  local bare = test.ipc("expand", "~")
  test.eq(bare[1], bare[2])
  local under = test.ipc("expand", "~/Pictures")
  test.eq(under[1], under[2] .. "/Pictures")
  test.eq(test.ipc("expand", "/srv/walls")[1], "/srv/walls")
end)

test.it("capture's path comes back alone", function()
  load()
  test.eq(test.ipc("capture_expand", "~/x"), 1)
end)

test.it("a value is quoted for a Lua chunk", function()
  load()
  test.eq(test.ipc("quoted", 'a "b"'), '"a \\"b\\""')
end)

test.it("the performance page's sizes are the kit's", function()
  load()
  test.eq(test.ipc("sizes"), { "1.5 KiB", true })
end)

test.it("no copy is left beside them", function()
  local gone = {
    { "themes/material/widgets/collection.lua", "local function bytes(" },
    { "themes/tsugumori/widgets/collection.lua", "local function bytes(" },
    { "themes/material/widgets/collection.lua", "local function show(" },
    { "themes/tsugumori/widgets/collection.lua", "local function show(" },
    { "themes/material/widgets/range.lua", "local function trim(" },
    { "themes/tsugumori/widgets/range.lua", "local function trim(" },
    { "themes/material/widgets/range.lua", "local function clamp01(" },
    { "themes/tsugumori/widgets/range.lua", "local function clamp01(" },
    { "themes/material/widgets/plane.lua", "local function clamp01(" },
    { "themes/tsugumori/widgets/plane.lua", "local function clamp01(" },
    { "themes/layouts/auth/notifications.lua", "local function ago(" },
    { "shell/lule_studio.lua", "local function expand(" },
    { "shell/wallpaper.lua", "local function expand(" },
    { "shell/wallpaper_model.lua", "local function expand(" },
    { "apps/screenshot/capture.lua", "local function expand(" },
    { "shell/workspaces_model.lua", "local function quoted(" },
    { "shell/bar_modules.lua", 'return text .. " " .. unit\n' },
  }
  for _, row in ipairs(gone) do
    test.falsy(morf.fs.read(row[1]):find(row[2], 1, true), row[1] .. " still holds " .. row[2])
  end
end)
