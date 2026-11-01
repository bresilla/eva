-- Window rules: the spelling sent to Hyprland, the rules kept, the pages that edit
-- them, and dimming. A stand-in compositor here; nix/tests/windows.py opens real
-- windows under the same rules on Hyprland 0.55.4.
--
--     morf test --no-dbus tests/window_rules_spec.lua

local test = morf.test

local function load(name, style, size)
  local settings = morf.env("XDG_CACHE_HOME") .. "/window-rules-" .. name .. ".json"
  morf.fs.remove(settings)
  test.load("../shell/init.lua", { source = [[
    require("init")
    local lib = require("lib.services.window_rules")
    local rules = require("window_rules_model")
    morf.ipc.sent = function()
      local out = {}
      for _, line in ipairs(require("lib.services.host_fake").last_hyprland.sent) do out[#out + 1] = line end
      return out
    end
    morf.ipc.fire = function() require("lib.services.host_fake").last_hyprland.fire("configreloaded") return true end
    morf.ipc.draft = function() return rules.draft:get() end
    morf.ipc.message = function() return rules.message:get() end
    morf.ipc.edit = function(json) rules.edit(morf.json.decode(json)) return true end
    morf.ipc.exact = function(text) return lib.exact(text) end
    morf.ipc.present = function(key) return require("settings_model").page_present(key) end
    morf.ipc.found = function(word)
      local out = {}
      for _, entry in ipairs(require("settings_registry").search(word)) do out[#out + 1] = entry.name end
      return out
    end
    morf.ipc.chunk = function(json) return lib.plan({ morf.json.decode(json) }, {}) end
    morf.ipc.refused = function(json) return lib.refused(morf.json.decode(json)) or "" end
  ]], size = size or { 1920, 1080 }, env = { EVA_STYLE = style or "material", EVA_SETTINGS = settings, EVA_DRY_RUN = "1",
    EVA_FAKE_SYSTEM = "1", EVA_FAKE_WINDOWS = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(800)
end

local function sent_with(word)
  local n = 0
  for _, line in ipairs(test.ipc("sent")) do if line:find(word, 1, true) then n = n + 1 end end
  return n
end

local FLOAT = morf.json.encode { class = "^foot$", layout = "float", size = "400 300" }

test.it("a rule is spelled as Hyprland 0.55.4 took it", function()
  load("spell")
  local plan = test.ipc("chunk", morf.json.encode { id = "r1", class = "^foot$", title = "^x$", layout = "float", size = "400 300",
    move = "30 40", center = true, workspace = "3", silent = true, monitor = "DP-1", opacity = .8, pin = true, no_blur = true })
  local chunk = plan[1].eval
  test.contains(chunk, 'match = { class = "^foot$", title = "^x$" }')
  test.contains(chunk, "float = true")
  test.contains(chunk, 'size = "400 300"')
  test.contains(chunk, 'move = "30 40"')
  test.contains(chunk, 'workspace = "3 silent"')
  test.contains(chunk, 'monitor = "DP-1"')
  test.contains(chunk, 'opacity = "0.80"')
  test.contains(chunk, "center = true")
  test.contains(chunk, "pin = true")
  test.contains(chunk, "no_blur = true")
end)

test.it("a rule that says nothing, or something dangerous, is refused", function()
  load("refuse")
  test.contains(test.ipc("refused", morf.json.encode { layout = "float" }), "class or a title")
  test.contains(test.ipc("refused", morf.json.encode { class = "x" }), "something to do")
  test.contains(test.ipc("refused", morf.json.encode { class = "x", size = "400" }), "two numbers")
  test.contains(test.ipc("refused", morf.json.encode { class = "x", workspace = '1" }) os.execute("x' }), "no workspace")
  test.contains(test.ipc("refused", morf.json.encode { class = "x", size = '1 2") bad("' }), "two numbers")
  -- Quoting keeps a pattern a string.
  local plan = test.ipc("chunk", morf.json.encode { id = "r1", class = 'a") bad("', layout = "float" })
  test.contains(plan[1].eval, [[class = "a\") bad(\""]])
end)

test.it("a class becomes a pattern matching just it", function()
  load("exact")
  test.eq(test.ipc("exact", "org.gnome.Nautilus"), "^org\\.gnome\\.Nautilus$")
end)

test.it("a saved rule is sent, an edit replaces it, a delete switches it off", function()
  load("crud")
  local id = test.ipc("rules", "add", FLOAT)
  test.eq(id, "r1")
  test.settle(100)
  test.eq(sent_with('size = "400 300"'), 1)
  local rule = test.ipc("rules", "list")[1]
  rule.size = "500 350"
  test.ipc("rules", "set", morf.json.encode(rule)) test.settle(100)
  test.eq(sent_with('size = "500 350"'), 1)
  test.eq(sent_with("enabled = false"), 1, "the old form is switched off")
  test.ipc("rules", "remove", "r1") test.settle(100)
  test.eq(sent_with("enabled = false"), 2)
  test.eq(test.ipc("rules", "list"), {})
end)

test.it("a reload forgets rules, so they are sent again", function()
  load("reload")
  test.ipc("rules", "add", FLOAT) test.settle(100)
  test.ipc("fire") test.settle(100)
  test.eq(sent_with('size = "400 300"'), 2)
end)

test.it("a rule off stays kept, and is not sent", function()
  load("off")
  test.ipc("rules", "add", FLOAT) test.settle(100)
  test.ipc("rules", "off", "r1") test.settle(100)
  test.eq(test.ipc("rules", "list")[1].enabled, false)
  test.eq(sent_with("enabled = false"), 1)
  test.ipc("fire") test.settle(100)
  test.eq(sent_with('size = "400 300"'), 1)
end)

test.it("a running window fills the draft", function()
  load("from")
  local windows = test.ipc("windows")
  local nautilus
  for _, w in ipairs(windows) do if w.class == "org.gnome.Nautilus" then nautilus = w end end
  local draft = test.ipc("rules", "from", nautilus.address)
  test.eq(draft.class, "^org\\.gnome\\.Nautilus$")
  test.eq(draft.layout, "float")
  test.eq(draft.size, "720 480")
  test.eq(draft.workspace, "3")
end)

test.it("dimming is left alone until it is turned on, and sent again after a reload", function()
  load("dim")
  test.eq(sent_with("dim_inactive"), 0, "the default touches nothing")
  test.ipc("rules", "dim", "on", "0.35") test.settle(100)
  test.eq(sent_with("dim_inactive = true"), 1)
  test.truthy(sent_with("dim_strength = 0.35") >= 1)
  test.ipc("fire") test.settle(100)
  test.eq(sent_with("dim_inactive = true"), 2)
  test.ipc("rules", "dim", "off") test.settle(100)
  test.eq(sent_with("dim_inactive = false"), 1)
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the pages list, edit and delete a rule", function()
    load("pages-" .. style, style)
    test.ipc("rules", "add", FLOAT) test.settle(100)
    test.ipc("utilities", "open") test.settle(600)
    test.ipc("settings", "windows") test.settle(900)
    test.truthy(test.find { id = "windows-rules", visible = true })
    test.truthy(test.find { id = "windows-dim-inactive", visible = true })
    test.ipc("settings", "windows/rules") test.settle(900)
    test.truthy(test.find { id = "rule-1", visible = true })
    test.truthy(test.find { id = "rule-from-1", visible = true }, "a running window is offered")
    test.click("rule-1-press") test.settle(900)
    test.truthy(test.find { id = "rule-scroll", visible = true })
    test.eq(test.ipc("draft").id, "r1")
    test.click("rule-delete") test.settle(900)
    test.eq(test.ipc("rules", "list"), {})
    test.truthy(test.find { id = "rules-scroll", visible = true })
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a rule that cannot be sent stays on the page, and says why", function()
  load("save")
  test.ipc("utilities", "open") test.settle(600)
  test.ipc("edit", morf.json.encode { class = "x" }) test.settle(900)
  test.click("rule-save") test.settle(300)
  test.contains(test.ipc("message"), "something to do")
  test.truthy(test.find { id = "rule-scroll", visible = true })
end)

test.it("a phone has no rules page or dimming, a tablet has both", function()
  load("phone", "material", { 412, 915 })
  test.falsy(test.ipc("present", "windows/rules"))
  test.ipc("utilities", "open") test.settle(600)
  test.ipc("settings", "windows") test.settle(900)
  test.falsy(test.find { id = "windows-rules", visible = true })
  test.falsy(test.find { id = "windows-dim-inactive", visible = true })
  test.ipc("settings", "home") test.settle(900)
  test.type("dim inactive") test.settle(300)
  test.falsy(test.find { text = "Dim inactive windows", visible = true }, "search does not offer what a phone hides")
end)

test.it("Settings search finds them", function()
  load("search")
  test.contains(table.concat(test.ipc("found", "opacity"), ","), "Window rules")
  test.contains(table.concat(test.ipc("found", "dim inactive"), ","), "Dim inactive windows")
end)
