-- The motion work, frame by frame, in virtual time. Through tools/test.sh, which
-- keeps the folders sealed, with one shard so the flags reach `morf test`:
--
--     JOBS=1 sh tools/test.sh --snapshots DIR tools/films/motion_films_spec.lua
--
-- FILM names the one film to take, FILM_STYLE and FILM_MODE the look, and
-- tools/films/strip.sh DIR NAME GEOMETRY lays a film's frames side by side.
local test = morf.test

local W, H = 1920, 1080
local STYLE = morf.env("FILM_STYLE") or "material"
local ONLY = morf.env("FILM")

local function load(size)
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  test.load("../../shell/init.lua", {
    size = size or { W, H },
    env = { EVA_STYLE = STYLE, EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1",
      EVA_THEME_MODE = morf.env("FILM_MODE") or "dark" },
  })
  test.settle(2000)
end

local function film(name, frames, step)
  for i = 0, frames - 1 do
    test.snapshot(("%s-%03d.png"):format(name, i), { surface = "screen" })
    test.advance(step or 32)
  end
end

local function take(name, body)
  if ONLY and ONLY ~= name then return end
  test.it(name, body)
end

test.describe("motion films", function()
  take("reversal", function()
    load()
    test.ipc("dashboard", "open")
    film("reverse-open", 6)
    test.ipc("close")
    film("reverse-close", 6)
    test.ipc("dashboard", "open")
    film("reverse-again", 14)
    test.settle(1000)
    test.snapshot("reverse-rest.png", { surface = "screen" })
  end)

  take("seams", function()
    load()
    test.ipc("sidebar", "open")
    test.settle(1000)
    test.snapshot("seam-before.png", { surface = "screen" })
    test.ipc("bottom", "open")
    film("seam-melt", 14, 32)
    test.settle(1000)
    test.snapshot("seam-melted.png", { surface = "screen" })
  end)

  take("rail", function()
    load()
    test.ipc("workspace", 5)
    film("rail-1-5", 24, 16)
    test.settle(1500)
    test.ipc("workspace", 2)
    film("rail-5-2", 24, 16)
  end)

  take("morph", function()
    test.load("../../shell/init.lua", { size = { 640, 200 },
      env = { EVA_STYLE = STYLE, EVA_WALLPAPER = "", EVA_DRY_RUN = "1" }, source = [[
        local ui = require("morf.ui")
        local kit = require("kit")
        local words = morf.signal("film.words", "10:29")
        morf.surface.width, morf.surface.height = 640, 200
        ui.Item { width = 640, height = 200,
          ui.Rect { anchors = { fill = true }, color = function() return require("theme").color.surface end },
          kit.text { x = 40, y = 30, morph = true, font_size = 110, font_weight = 500,
            color = function() return require("theme").color.primary end,
            text = function() return words:get() end } }
        morf.ipc.say = function(value) words:set(value) end
      ]] })
    test.advance(100)
    test.snapshot("morph-before.png")
    test.ipc("say", "10:30")
    film("morph", 10, 24)
    test.settle(1000)
    test.snapshot("morph-after.png")
  end)

  take("eva-page", function()
    local size = morf.env("FILM_PHONE") == "1" and { 868, 1932 } or nil
    load(size)
    test.ipc("sidebar", "open", "settings")
    test.settle(1500)
    test.click("utilities-toggle-eva")
    test.advance(2500)
    test.snapshot("eva-page.png", { surface = "screen" })
  end)

  take("lock-clock", function()
    test.load("../../lock/init.lua", { args = { "window", "preview" }, size = { 1280, 800 },
      env = { EVA_STYLE = STYLE, EVA_DRY_RUN = "1", EVA_THEME_MODE = morf.env("FILM_MODE") or "dark" } })
    test.settle(2000)
    local before = test.get("lock-clock-5-digit") or test.get("lock-clock")
    local from = before.text
    local waited = 0
    while waited < 62000 and (test.find("lock-clock-5-digit") or test.get("lock-clock")).text == from do
      test.advance(16)
      waited = waited + 16
    end
    film("lock-morph", 8, 24)
  end)

  take("stretch", function()
    load()
    test.ipc("sidebar", "open")
    film("stretch-side", 12, 16)
    test.settle(1000)
    test.ipc("close")
    film("stretch-side-close", 8, 16)
    test.settle(1000)
    test.ipc("dashboard", "open")
    film("stretch-top", 12, 16)
  end)
end)
