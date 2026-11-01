-- Key remapping: off unless the system says so, what it hands over, the page, and
-- the NixOS service staying narrow. Nothing here starts a remapper: kanata itself
-- runs in nix/tests/windows.py, inside a VM.
--
--     morf test --no-dbus tests/remap_spec.lua

local test = morf.test

local function shell(name, env, size)
  local settings = morf.env("XDG_CACHE_HOME") .. "/remap-" .. name .. ".json"
  morf.fs.remove(settings)
  local values = { EVA_SETTINGS = settings, EVA_DRY_RUN = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do values[key] = value end
  test.load("../shell/init.lua", { source = [[
    require("init")
    local remap = require("remap_model")
    morf.ipc.any = function() return remap.anything() end
    morf.ipc.present = function(key) return require("settings_model").page_present(key) end
    morf.ipc.found = function(word)
      local out = {}
      for _, entry in ipairs(require("settings_registry").search(word)) do out[#out + 1] = entry.name end
      return out
    end
  ]], size = size or { 1920, 1080 }, env = values })
  test.settle(800)
end

test.it("without the system's option it is off, and says what turns it on", function()
  shell("off")
  local state = test.ipc("remap", "state")
  test.eq(state.allowed, false)
  test.contains(state.summary, "Off in the system")
end)

test.it("the defaults remap nothing", function()
  shell("default")
  test.falsy(test.ipc("any"))
  test.eq(test.ipc("remap", "state").choices.caps, "")
end)

test.it("with the option, what is chosen is what is handed over", function()
  local folder = morf.env("XDG_CACHE_HOME") .. "/remap-folder"
  shell("on", { EVA_REMAP = folder })
  test.truthy(test.ipc("remap", "state").allowed)
  test.contains(test.ipc("remap", "state").summary, "nothing reads the keyboards")
  test.ipc("remap", "set", "caps", "tap_escape_hold_control") test.settle(100)
  test.ipc("remap", "set", "home_row", "true") test.settle(100)
  local choices = test.ipc("remap", "state").choices
  test.eq(choices.caps, "tap_escape_hold_control")
  test.eq(choices.home_row, true)
  test.truthy(test.ipc("any"))
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the page is a form like the rest", function()
    shell("page-" .. style, { EVA_STYLE = style })
    test.ipc("utilities", "open") test.settle(600)
    test.ipc("settings", "input") test.settle(900)
    test.truthy(test.find { id = "input-open-remap", visible = true })
    test.ipc("settings", "input/remap") test.settle(900)
    test.truthy(test.find { id = "form-input-remap-scroll", visible = true })
    test.truthy(test.find { id = "form-status", visible = true })
    test.click("form-remap-caps-escape") test.settle(200)
    test.eq(test.ipc("remap", "state").choices.caps, "escape")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a phone has no keyboard to remap, a desk does", function()
  shell("phone", {}, { 412, 915 })
  test.falsy(test.ipc("present", "input/remap"))
  shell("desk")
  test.truthy(test.ipc("present", "input/remap"))
end)

test.it("Settings search finds it", function()
  shell("search")
  test.contains(table.concat(test.ipc("found", "hyper"), ","), "Key remapping")
  test.contains(table.concat(test.ipc("found", "caps lock"), ","), "Caps Lock tap and hold")
end)

test.it("the system's service is off by default, adds nobody to input, and renders only what it knows", function()
  local nix = morf.fs.read("nix/nixos/remap.nix")
  test.contains(nix, "lib.mkEnableOption")
  test.contains(nix, 'lib.mkIf (eva.enable && cfg.enable)')
  test.falsy(nix:find("extraGroups", 1, true), "no one joins a group")
  test.contains(nix, "ExecCondition")
  local script = morf.fs.read("nix/nixos/scripts/remap-render.sh")
  test.falsy(script:find('$(field caps)"$', 1, true))
  test.contains(script, 'case "$(field caps)" in')
  test.falsy(script:find("cmd", 1, true), "no action that runs a command")
end)
