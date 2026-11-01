-- What the keyboard keeps from a locked screen, and from the disk. The lock and
-- the greeter share themes/keyboard.lua's panel with the shell, so nothing that
-- reads the clipboard or learns may reach that panel. Window and preview only:
-- no PAM or greetd.
local test = morf.test

for _, style in ipairs { "material", "tsugumori" } do
  for _, part in ipairs { "lock", "greet" } do
    test.it(style .. " " .. part .. " shows the keys alone: no strip, no clipboard, no learning", function()
      test.load("../" .. part .. "/init.lua", { size = { 868, 1932 },
        args = part == "lock" and { "window", "preview" } or { "preview" },
        env = { EVA_STYLE = style, EVA_DRY_RUN = "1" }, source = [[
          package.loaded["lib.services.keyboards"] = { attached = function() return false end }
          require("init")
          morf.ipc.loaded = function()
            local out = {}
            for _, name in ipairs { "keyboard", "keyboard_clips", "keyboard_learn", "keyboard_predict",
              "keyboard_model", "keyboard_strip", "lib.shell.clipboard.store", "lib.shell.words" } do
              if package.loaded[name] then out[#out + 1] = name end
            end
            return out
          end
        ]] })
      test.advance(100) test.ipc("stage", "sheet") test.advance(2500)
      test.eq(test.ipc("loaded"), {}, "the " .. part .. " scene loaded what reads the clipboard or learns")
      local keys = 0
      for _, node in ipairs(test.nodes()) do
        local id = node.id or ""
        test.falsy(id:find("eva.keyboard.", 1, true), id .. " reached the " .. part .. " scene")
        if id:find("key.full.letters.", 1, true) then keys = keys + 1 end
      end
      test.truthy(keys > 20, "the " .. part .. " scene has no keys")
      test.eq(#test.logs("error"), 0)
    end)
  end
end

local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 400, height = 300 }
  local lock = morf.signal("lock.state", "unlocked")
  morf.lock = { state = lock }
  local store = require("lib.shell.clipboard.store")
  local clips = require("keyboard_clips")
  morf.fs.mkdir(store.folder(), { parents = true })
  morf.fs.write(store.index(), morf.json.encode { { id = "1", kind = "text", text = "the secret plan" } })
  morf.ipc.lock = function(state) lock:set(state) end
  morf.ipc.read = function() clips.follow(false) clips.follow(true) return clips.items:get() end
]]

test.it("the clipboard is not read while the session is locked", function()
  test.load("../shell/init.lua", { source = HOST, size = { 400, 300 },
    env = { EVA_SETTINGS = morf.paths.state("keyboard-private.json") } })
  test.eq(test.ipc("read")[1].text, "the secret plan")
  test.ipc("lock", "locked")
  test.eq(test.ipc("read"), {}, "a locked session read the clipboard")
  test.ipc("lock", "unlocked")
  test.eq(#test.ipc("read"), 1)
end)
