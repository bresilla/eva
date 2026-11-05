-- eva's motion across its surfaces, frame by frame, in either theme: each
-- test starts a transition and snapshots the screen on a fixed virtual step,
-- so the frames can be laid side by side or made into a GIF. Only useful with
-- snapshots on:
--
--     morf test --no-dbus --snapshots DIR tools/films/motion_all_spec.lua
--
-- FILM_STYLE picks the theme (tsugumori by default), FILM_SCREEN=868x1932
-- films the phone, FILM_MODE=light the light palette, FILM_LULE a folder
-- holding a colors.json.
local test = morf.test
local W, H = 1920, 1080
local screen = morf.env("FILM_SCREEN")
if screen and screen:match("^%d+x%d+$") then
  W, H = screen:match("^(%d+)x(%d+)$")
  W, H = tonumber(W), tonumber(H)
end
local PHONE = W < H

local function load(extra)
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  local cache = morf.env("XDG_CACHE_HOME")
  local env = { EVA_STYLE = morf.env("FILM_STYLE") or "tsugumori", EVA_DRY_RUN = "1", EVA_FONT_FILE = "",
    EVA_SETTINGS = cache .. "/motion-film-settings.json",
    EVA_APPEARANCE = cache .. "/motion-film-appearance.json" }
  if morf.env("FILM_MODE") then env.EVA_THEME_MODE = morf.env("FILM_MODE") end
  if morf.env("FILM_LULE") then env.LULE_A = morf.env("FILM_LULE") end
  if PHONE then env.EVA_INPUT_DEVICES = morf.env("PWD") .. "/tests/fixtures/input-devices-touch" end
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

test.it("the launcher opens, filters and shuts", function()
  load()
  test.ipc("launcher", "open")
  film("launcher-open", 26)
  test.settle(1500)
  test.type("se")
  film("launcher-type", 16, 25)
  test.settle(800)
  test.key("BackSpace") test.key("BackSpace")
  film("launcher-clear", 16, 25)
  test.settle(800)
  test.ipc("launcher", "close")
  film("launcher-close", 14, 25)
end)

test.it("quick settings open, a tile turns, a page opens", function()
  load()
  test.ipc("sidebar", "open", "settings")
  film("sidebar-open", 26)
  test.settle(1500)
  test.ipc("settings", "network")
  film("settings-page", 20, 25)
  test.settle(1500)
  test.ipc("sidebar", "close")
  film("sidebar-close", 16, 25)
end)

test.it("notifications come, stack and go", function()
  load()
  test.ipc("notify", "Download complete", "report.pdf has finished downloading", "normal", "Firefox")
  film("notify-one", 20)
  test.settle(400)
  test.ipc("notify", "Message", "Lunch at one?", "normal", "Chat")
  film("notify-two", 20)
  test.settle(400)
  test.ipc("notifications", "dismiss")
  film("notify-dismiss", 16, 25)
end)

test.it("the history fills and clears", function()
  load()
  for i = 1, 3 do test.ipc("notify", "Build " .. i, "finished in " .. (10 * i) .. " s", "normal", "CI") end
  test.settle(8000)
  test.ipc("sidebar", "open", "notifications")
  film("history-open", 26)
  test.settle(1500)
  test.ipc("notifications", "clear")
  film("history-clear", 20, 25)
end)

test.it("the planner opens and turns to the calendar", function()
  load()
  test.ipc("leftbar", "open", "tasks")
  film("leftbar-open", 26)
  test.settle(1500)
  test.ipc("leftbar", "open", "calendar")
  film("leftbar-tab", 20, 25)
end)

test.it("the dashboard opens and changes tab", function()
  load()
  test.ipc("dashboard", "open")
  film("dashboard-open", 26)
  test.settle(1500)
  test.ipc("dashboard", "open", "weather")
  film("dashboard-tab", 20, 25)
  test.settle(1500)
  test.ipc("dashboard", "close")
  film("dashboard-close", 14, 25)
end)

test.it("the bottom tools open and turn", function()
  load()
  test.ipc("bottom", "open", "assistant")
  film("bottom-open", 26)
  test.settle(1500)
  test.ipc("bottom", "open", "drop")
  film("bottom-tab", 20, 25)
end)

test.it("the session menu opens and its focus moves", function()
  load()
  test.ipc("session", "open")
  film("session-open", 24)
  test.settle(1000)
  test.key("Down") test.key("Down")
  film("session-focus", 14, 25)
  test.settle(800)
  test.ipc("session", "close")
  film("session-close", 14, 25)
end)

test.it("the readouts come and go", function()
  load()
  test.ipc("osd", "volume")
  film("osd", 20)
  test.settle(4000)
  film("osd-leave", 10)
end)

test.it("an interrupted drawer turns where it stands", function()
  load()
  test.ipc("sidebar", "open", "settings")
  film("interrupt-open", 6, 25)
  test.ipc("sidebar", "close")
  film("interrupt-close", 8, 25)
  test.ipc("sidebar", "open", "settings")
  film("interrupt-reopen", 16, 25)
end)
