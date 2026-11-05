-- Tsugumori's HUD motion, frame by frame: every test starts a transition
-- and snapshots the screen on a fixed virtual step, so the frames can be laid
-- side by side or made into a GIF. Only useful with snapshots on:
--
--     morf test --no-dbus --snapshots DIR tools/films/tsugumori_hud_spec.lua
--
-- FILM_SCREEN=868x1932 films the phone.
local test = morf.test
local W, H = 1920, 1080
local screen = morf.env("FILM_SCREEN")
if screen and screen:match("^%d+x%d+$") then
  W, H = screen:match("^(%d+)x(%d+)$")
  W, H = tonumber(W), tonumber(H)
end

local function load(extra)
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  local env = { EVA_STYLE = "tsugumori", EVA_DRY_RUN = "1", EVA_FONT_FILE = "",
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/hud-film-settings.json",
    EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/hud-film-appearance.json" }
  for k, v in pairs(extra or {}) do env[k] = v end
  test.load("../../shell/init.lua", { size = { W, H }, env = env })
  test.settle(2000)
end

local function film(name, frames, step)
  for i = 0, frames - 1 do
    test.snapshot(("%s-%03d.png"):format(name, i))
    test.advance(step or 33)
  end
end

test.it("dashboard boots open and wipes between tabs", function()
  load()
  test.ipc("dashboard", "open")
  film("dashboard-open", 30)
  test.settle(1500)
  test.snapshot("dashboard-rest.png")
  test.ipc("dashboard", "open", "weather")
  film("dashboard-tab", 18, 25)
  test.settle(1500)
  test.eq(#test.logs("error"), 0)
end)

test.it("quick settings boot open", function()
  load()
  test.ipc("sidebar", "open", "settings")
  film("sidebar-open", 30)
  test.settle(1500)
  test.snapshot("sidebar-rest.png")
  test.eq(#test.logs("error"), 0)
end)

test.it("the launcher opens and its reticle moves between rows", function()
  load()
  test.ipc("launcher", "open")
  film("launcher-open", 24)
  test.settle(1500)
  test.key("Down") test.key("Down")
  film("launcher-select", 16, 25)
  test.settle(800)
  test.type("bl")
  film("launcher-type", 14, 16)
  test.eq(#test.logs("error"), 0)
end)

test.it("a notification arrives under a target lock", function()
  load()
  test.ipc("notify", "Download complete", "report.pdf has finished downloading", "normal", "Firefox")
  film("notify", 30)
  test.eq(#test.logs("error"), 0)
end)

test.it("the volume readout comes and the session menu boots", function()
  load()
  test.ipc("osd", "volume")
  film("osd", 24)
  test.settle(4000)
  test.ipc("session", "open")
  film("session-open", 28)
  test.settle(1000)
  test.key("Down")
  film("session-focus", 12, 25)
  test.eq(#test.logs("error"), 0)
end)

test.it("a workspace change traces along the rail", function()
  load()
  test.ipc("workspace", 4)
  film("workspace", 20, 25)
  test.eq(#test.logs("error"), 0)
end)
