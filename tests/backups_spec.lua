-- The Backups page against the stand-in machine (EVA_FAKE_SYSTEM): no real
-- snapper, btrbk or restic runs. `EVA_FAKE_BACKUPS` says which the machine has,
-- host_fake answers them, and under EVA_DRY_RUN what changes the machine is
-- logged, which the spec reads back.
--     tools/test.sh tests/backups_spec.lua
local test = morf.test

local serial = 0
local function load(style, size, tools, settings_text, env)
  serial = serial + 1
  local settings = ("%s/backups-%d.json"):format(morf.env("XDG_CACHE_HOME"), serial)
  morf.fs.write(settings, morf.json.encode(settings_text or {}))
  local vars = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", EVA_FAKE_SYSTEM = "1", EVA_FAKE_BACKUPS = tools or "",
    EVA_SETTINGS = settings, EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do vars[key] = value end
  test.load("../shell/init.lua", { size = size or { 1920, 1080 }, env = vars })
  test.settle(1200)
end
local function open()
  test.ipc("settings", "backups")
  test.settle(900)
end
local function text(id) return test.text_of(test.get(id)) end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end
local function logged(part)
  for _, line in ipairs(test.logs("info")) do
    if tostring(line.message):find(part, 1, true) then return true end
  end
  return false
end
local function clean() test.eq(#test.logs("error"), 0) end

local LIB = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local backups = require("lib.services.backups")
  morf.ipc.snapper = function(text) return backups.parse_snapper(text, "root", "/home") or false end
  morf.ipc.btrbk = function(text) return backups.parse_btrbk(text) end
  morf.ipc.restic = function(text) return backups.parse_restic(text) or false end
  morf.ipc.inside = function(root, base, path) return backups.inside({ root = root, base = base }, path) or false end
]]

test.describe("backups", function()
  test.it("says there is none, and what would do, with nothing to press", function()
    load()
    open()
    test.truthy(test.find { id = "backups-missing", visible = true })
    test.truthy(test.find { id = "backups-need-1", visible = true })
    test.falsy(test.find { id = "backups-make", visible = true })
    test.truthy(text("backups-need-3"):find("restic", 1, true))
    shot("backups-none")
    clean()
  end)

  test.it("on NixOS names the option to set", function()
    load(nil, nil, nil, nil, { EVA_FAKE_SYSTEM = "nixos" })
    open()
    test.truthy(text("backups-need-1"):find("services.snapper.configs", 1, true))
  end)

  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. ": shows snapper's snapshots, newest first, without the live one", function()
      load(style, nil, "snapper")
      open()
      test.falsy(test.find { id = "backups-missing", visible = true })
      test.truthy(text("backups-row-1"):find("timeline", 1, true))
      test.truthy(text("backups-row-1"):find("2026-11-01", 1, true))
      test.truthy(test.find { id = "backups-row-3", visible = true })
      test.falsy(test.find { id = "backups-row-4", visible = true }, "snapshot 0 is the live system")
      shot(style .. "-backups")
      clean()
    end)
  end

  test.it("makes one on a press, and reads the list again", function()
    load(nil, nil, "snapper")
    open()
    test.click("backups-make")
    test.settle(500)
    test.truthy(logged("snapper -c root create -d Made in Settings"), "the command, held by the dry run")
    test.eq(test.text_of(test.get("backups-status")), "Made one.")
    clean()
  end)

  test.it("restores a copy beside the file with no second press", function()
    load(nil, nil, "snapper")
    open()
    test.click("backups-row-1-press") test.settle(300)
    test.truthy(test.find { id = "backups-restore", visible = true })
    test.click("backups-path") test.type("/home/kate/notes.txt") test.settle(100)
    test.click("backups-copy") test.settle(300)
    test.truthy(logged("cp --reflink=auto --no-clobber -- /home/.snapshots/43/snapshot/kate/notes.txt /home/kate/notes.txt.restored"))
    test.truthy(text("backups-said"):find("notes.txt.restored", 1, true))
    clean()
  end)

  test.it("replacing a file takes a second press, and can be called off", function()
    load(nil, nil, "snapper")
    open()
    test.click("backups-row-1-press") test.settle(300)
    test.click("backups-path") test.type("/home/kate/notes.txt") test.settle(100)
    test.click("backups-replace") test.settle(300)
    test.falsy(logged("undochange"), "the first press only asks")
    test.truthy(text("backups-said"):find("overwrites /home/kate/notes.txt", 1, true))
    shot("backups-confirm")
    test.click("backups-keep") test.settle(300)
    test.falsy(logged("undochange"))
    test.click("backups-replace") test.settle(300)
    test.click("backups-replace") test.settle(300)
    test.truthy(logged("snapper -c root undochange 43..0 -- /home/kate/notes.txt"))
    clean()
  end)

  test.it("changing the path or the snapshot takes the question back", function()
    load(nil, nil, "snapper")
    open()
    test.click("backups-row-1-press") test.settle(300)
    test.click("backups-path") test.type("/home/kate/a") test.settle(100)
    test.click("backups-replace") test.settle(300)
    test.click("backups-path") test.type("b") test.settle(100)
    test.click("backups-replace") test.settle(300)
    test.falsy(logged("undochange"), "a new path asks again")
    clean()
  end)

  test.it("refuses a file the snapshot does not hold", function()
    load(nil, nil, "snapper")
    open()
    test.click("backups-row-1-press") test.settle(300)
    test.click("backups-path") test.type("/etc/passwd") test.settle(100)
    test.click("backups-copy") test.settle(300)
    test.truthy(text("backups-said"):find("not under /home", 1, true))
    test.falsy(logged("cp --reflink"))
    clean()
  end)

  test.it("btrbk: asks for no password until a press, and keeps what it would prune", function()
    load(nil, nil, "btrbk")
    open()
    test.truthy(test.find { id = "backups-unlock", visible = true }, "showing the page asks nobody")
    test.click("backups-unlock") test.settle(400)
    test.falsy(test.find { id = "backups-unlock", visible = true })
    test.truthy(text("backups-row-1"):find("2026-11-01 09:00", 1, true))
    test.click("backups-make") test.settle(300)
    test.truthy(logged("pkexec btrbk snapshot --preserve"))
    clean()
  end)

  test.it("restic: says what it lacks, and passes no password on a command line", function()
    load(nil, nil, "restic")
    open()
    test.truthy(text("backups-status"):find("restic repository", 1, true))
    load(nil, nil, "restic", { backups = { restic_repository = "/mnt/backup", restic_password_file = "/run/keys/restic", restic_paths = { "/home/kate" } } })
    open()
    test.truthy(text("backups-row-1"):find("2026-10-31", 1, true))
    test.click("backups-make") test.settle(300)
    test.truthy(logged("restic backup /home/kate"))
    test.falsy(logged("/run/keys/restic"), "not even the file's path is logged")
    test.click("backups-row-1-press") test.settle(300)
    test.click("backups-path") test.type("/home/kate/notes.txt") test.settle(100)
    test.click("backups-copy") test.settle(300)
    test.truthy(logged("restic restore 5e6f7a8b --target /home/kate/.eva-restore-5e6f7a8b --include /home/kate/notes.txt"))
    clean()
  end)

  test.it("offers each tool there is, and remembers the one chosen", function()
    load(nil, nil, "snapper,restic", { backups = { restic_repository = "/r", restic_password_file = "/p" } })
    open()
    test.truthy(test.find { id = "backups-tool-2", visible = true })
    test.click("backups-tool-2-press") test.settle(400)
    test.truthy(text("backups-row-1"):find("/home/kate", 1, true))
    clean()
  end)

  test.it("is found by search, and has its settings page", function()
    load()
    test.ipc("settings", "home") test.settle(900)
    test.type("restore a file") test.settle(300)
    test.truthy(test.find { text = "Restore a file", visible = true })
    test.ipc("settings", "backups/more") test.settle(900)
    test.truthy(test.find { id = "form-backups-more-scroll", visible = true })
  end)

  test.it("fits a phone", function()
    load("tsugumori", { 412, 915 }, "snapper")
    open()
    test.click("backups-row-1-press") test.settle(300)
    shot("phone-backups")
    local box = test.get("backups-scroll")
    test.truthy(box.x >= 0 and box.x + box.width <= 412)
    clean()
  end)
end)

test.describe("what the tools print", function()
  test.before_each(function() test.load("../shell/init.lua", { source = LIB, size = { 200, 200 }, env = { EVA_DRY_RUN = "1" } }) end)

  test.it("reads snapper's JSON", function()
    local rows = test.ipc("snapper", morf.json.encode { root = { { number = 0, type = "single", description = "current" },
      { number = 7, type = "single", date = "2026-01-02 03:04:05", description = "Before the update" } } })
    test.eq(#rows, 1)
    test.eq(rows[1].id, "7")
    test.eq(rows[1].title, "Before the update")
    test.eq(rows[1].base, "/home/.snapshots/7/snapshot")
    test.eq(test.ipc("snapper", "not json"), false)
  end)

  test.it("reads btrbk's raw lines, the stamp from the name", function()
    local rows = test.ipc("btrbk", "snapshot_subvolume='/mnt/s/home.20260102T0304' source_subvolume='/home'\nnoise\n")
    test.eq(#rows, 1)
    test.eq(rows[1].when, "2026-01-02 03:04")
    test.eq(rows[1].root, "/home")
  end)

  test.it("reads restic's JSON", function()
    local rows = test.ipc("restic", morf.json.encode { { short_id = "abcd1234", time = "2026-01-02T03:04:05.5Z", paths = { "/a", "/b" }, hostname = "h" } })
    test.eq(rows[1].id, "abcd1234")
    test.eq(rows[1].when, "2026-01-02 03:04")
    test.eq(rows[1].title, "/a, /b")
  end)

  test.it("finds a file inside a snapshot, and only under what it holds", function()
    test.eq(test.ipc("inside", "/home", "/s/1", "/home/kate/a b.txt"), "/s/1/kate/a b.txt")
    test.eq(test.ipc("inside", "/", "/.snapshots/2/snapshot", "/etc/hosts"), "/.snapshots/2/snapshot/etc/hosts")
    test.eq(test.ipc("inside", "/home", "/s/1", "/homely/a"), false)
  end)
end)
