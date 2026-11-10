-- Settings and the quick panel, frame by frame, in virtual time, on the
-- stand-in machine the audit shoots. Through tools/test.sh with one shard:
--
--     JOBS=1 sh tools/test.sh --snapshots DIR tools/films/settings_films_spec.lua
--
-- FILM names the one film to take, FILM_STYLE and FILM_MODE the look,
-- FILM_SIZE the screen ("1368x912"). tools/films/strip.sh lays frames out.
local test = morf.test

local STYLE = morf.env("FILM_STYLE") or "material"
local ONLY = morf.env("FILM")
local W, H = (morf.env("FILM_SIZE") or "1368x912"):match("(%d+)x(%d+)")
W, H = tonumber(W), tonumber(H)
local ROOT = morf.env("PWD") or "."

local function load()
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  test.load("../../shell/init.lua", {
    size = { W, H },
    env = { EVA_STYLE = STYLE, EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1",
      EVA_THEME_MODE = morf.env("FILM_MODE") or "dark", EVA_FAKE_SYSTEM = "1",
      EVA_FAKE_BATTERY = "64,charging", EVA_FAKE_STATUS = "wifi,bluetooth", EVA_FAKE_AUDIO = "1",
      EVA_FAKE_NET = ROOT .. "/tests/fixtures/net", EVA_FAKE_HARDWARE = "1" },
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

local function page(key)
  test.ipc("settings", key)
  test.settle(1500)
end

test.describe("settings films", function()
  take("open", function()
    load()
    test.ipc("settings", "home")
    film("open", 16)
  end)

  take("into", function()
    load()
    page("home")
    test.ipc("settings", "home/connections")
    film("into-category", 14)
    test.settle(1000)
    test.ipc("settings", "network/connection")
    film("into-page", 14)
  end)

  take("manual", function()
    load()
    page("network/connection")
    test.click { id = "connection-method-manual" }
    film("manual-on", 16)
    test.click { id = "connection-method-auto" }
    film("manual-off", 16)
  end)

  take("nav", function()
    load()
    page("network/connection")
    test.click { id = "settings-nav-sound" }
    film("nav-glide", 16)
  end)

  take("filters", function()
    load()
    page("filters")
    test.click { id = "settings-filters-extradim" }
    film("filters-on", 16)
  end)

  take("about", function()
    load()
    page("about")
    test.click { id = "about-more" }
    film("about-more", 16)
  end)

  take("lan_mouse", function()
    load()
    page("lan_mouse")
    test.snapshot("lan-mouse.png", { surface = "screen" })
    test.click { id = "lan-mouse-machine-2" }
    test.settle(800)
    test.snapshot("lan-mouse-open.png", { surface = "screen" })
  end)

  take("dashboard", function()
    load()
    test.ipc("dashboard", "open")
    test.settle(2500)
    test.snapshot("dashboard.png", { surface = "screen" })
  end)

  take("panel", function()
    load()
    test.ipc("utilities", "open")
    film("panel-open", 16)
    test.settle(1000)
    test.ipc("quick", "sound")
    film("panel-drill", 16)
  end)
end)
