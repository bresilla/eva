-- How things move reaches every role: the shell's choice is in the shared file,
-- and the lock, the greeter and the tools take it from there.
--
--     morf test --no-dbus tests/motion_reach_spec.lua
local test = morf.test

local PROBE = [[
  local ui = require("morf.ui")
  local before = ui.spring
  local motion = require("themes.motion_style")
  local spy = {}
  ui.spring = function(spec)
    spy[#spy + 1] = spec.damping
    return before(spec)
  end
  motion.install()
  morf.ipc.m_style = function() return motion.style() end
  morf.ipc.m_reduced = function() return motion.reduced() end
  morf.ipc.m_damping = function()
    spy = {}
    ui.spring { stiffness = 400, damping = 20 }
    return spy[1]
  end
  morf.ipc.m_lands = function()
    local spring = ui.spring { stiffness = 400, damping = 20 }
    return type(spring) == "table" and spring.duration
  end
  return ui.Item { width = 10, height = 10 }
]]

local serial = 0
local function appearance(values)
  serial = serial + 1
  local path = morf.env("XDG_CACHE_HOME") .. "/motion-reach-" .. serial .. ".json"
  morf.fs.write(path, morf.json.encode(values))
  return path
end

test.describe("the shared file", function()
  test.it("hears the shell's settings, and any role reads them back", function()
    local path = appearance {}
    test.load("../shell/init.lua", { source = [[
      local config = require("config")
      morf.ipc.m_set = function(key, value) return config.set(key, value) end
      morf.ipc.m_flush = function() end
      local ui = require("morf.ui")
      return ui.Item { width = 10, height = 10 }
    ]], env = { EVA_APPEARANCE = path, EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/motion-reach-settings.json" } })
    test.ipc("m_set", "appearance.motion", "playful")
    test.ipc("m_set", "appearance.reduce_motion", true)
    test.advance(16)
    local saved = morf.json.decode(morf.fs.read(path))
    test.eq(saved.motion, "playful")
    test.eq(saved.reduce_motion, true)
  end)

  test.it("brings across a style set before the file held it", function()
    local path = appearance {}
    local settings = morf.env("XDG_CACHE_HOME") .. "/motion-reach-old.json"
    morf.fs.write(settings, morf.json.encode { appearance = { motion = "calm" } })
    test.load("../shell/init.lua", { source = [[
      local config = require("config")
      morf.ipc.m_get = function() return config.get("appearance.motion") end
      return require("morf.ui").Item { width = 10, height = 10 }
    ]], env = { EVA_APPEARANCE = path, EVA_SETTINGS = settings } })
    test.eq(test.ipc("m_get"), "calm")
  end)
end)

test.describe("a role without the shell's theme", function()
  test.it("takes the style in its springs", function()
    test.load("../lock/init.lua", { source = PROBE, env = { EVA_APPEARANCE = appearance { motion = "balanced" } } })
    local balanced = test.ipc("m_damping")
    test.load("../lock/init.lua", { source = PROBE, env = { EVA_APPEARANCE = appearance { motion = "calm" } } })
    local calm = test.ipc("m_damping")
    test.load("../lock/init.lua", { source = PROBE, env = { EVA_APPEARANCE = appearance { motion = "playful" } } })
    local playful = test.ipc("m_damping")
    test.eq(balanced, 20)
    test.truthy(calm > balanced, "calm is no calmer")
    test.truthy(playful < balanced, "playful is no livelier")
  end)

  test.it("lands everything under Reduce motion", function()
    test.load("../lock/init.lua", { source = PROBE, env = { EVA_APPEARANCE = appearance { reduce_motion = true } } })
    test.truthy(test.ipc("m_reduced"))
    test.eq(test.ipc("m_lands"), 0, "a spring still travels")
  end)
end)

test.describe("the greeter, which has no home of the user's", function()
  local shared = morf.env("XDG_CACHE_HOME") .. "/motion-reach-shared.json"
  local empty = morf.env("XDG_CACHE_HOME") .. "/motion-reach-no-personal.json"

  test.it("hears the shell's choices through the file the scale shares", function()
    morf.fs.remove(shared)
    test.load("../shell/init.lua", { source = [[
      local config = require("config")
      morf.ipc.m_set = function(key, value) return config.set(key, value) end
      morf.ipc.m_mode = function(value) require("themes.color_mode").set(value) end
      return require("morf.ui").Item { width = 10, height = 10 }
    ]], env = { EVA_SCALE_FILE = shared, EVA_APPEARANCE = appearance {},
      EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/motion-reach-share-settings.json" } })
    test.ipc("m_set", "appearance.motion", "calm")
    test.ipc("m_set", "appearance.reduce_motion", true)
    test.ipc("m_mode", "light")
    local kept = morf.json.decode(morf.fs.read(shared))
    test.eq(kept.motion, "calm")
    test.eq(kept.reduce_motion, true)
    test.eq(kept.mode, "light")
  end)

  test.it("lands everything from that file alone", function()
    morf.fs.write(shared, morf.json.encode { zoom = 0, reduce_motion = true, motion = "calm", mode = "light" })
    morf.fs.remove(empty)
    test.load("../greet/init.lua", { source = PROBE, env = { EVA_SCALE_FILE = shared, EVA_APPEARANCE = empty } })
    test.truthy(test.ipc("m_reduced"), "the greeter did not hear Reduce motion")
    test.eq(test.ipc("m_style"), "calm")
  end)

  test.it("keeps the scale when it shares, and the shares when the scale moves", function()
    morf.fs.write(shared, morf.json.encode { zoom = 0.25, motion = "playful" })
    test.load("../shell/init.lua", { source = [[
      local config = require("config")
      morf.ipc.m_set = function(key, value) return config.set(key, value) end
      return require("morf.ui").Item { width = 10, height = 10 }
    ]], env = { EVA_SCALE_FILE = shared, EVA_APPEARANCE = appearance {},
      EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/motion-reach-share2-settings.json" } })
    test.ipc("m_set", "appearance.density", "compact")
    test.ipc("m_set", "appearance.zoom", 0.5)
    local kept = morf.json.decode(morf.fs.read(shared))
    test.eq(kept.zoom, 0.5)
    test.eq(kept.motion, "playful")
    test.eq(kept.density, "compact")
  end)

  test.it("yields to a person's own file", function()
    morf.fs.write(shared, morf.json.encode { motion = "calm" })
    test.load("../greet/init.lua", { source = PROBE, env = { EVA_SCALE_FILE = shared, EVA_APPEARANCE = appearance { motion = "playful" } } })
    test.eq(test.ipc("m_style"), "playful")
  end)
end)

for _, role in ipairs { "lock", "greet" } do
  test.describe("the " .. role, function()
    test.it("builds whole under Reduce motion and under each style", function()
      for _, values in ipairs { { reduce_motion = true }, { motion = "calm" }, { motion = "playful" } } do
        test.load("../" .. role .. "/init.lua", { args = role == "lock" and { "window", "preview" } or { "preview" },
          env = { EVA_APPEARANCE = appearance(values), EVA_STYLE = "tsugumori" } })
        test.advance(400)
        test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
      end
    end)
  end)
end

test.describe("a tool", function()
  test.it("rebuilds when the shared motion changes", function()
    local path = appearance { motion = "balanced" }
    test.load("../apps/colorpick/app.lua", { source = [[
      local reloads = 0
      morf.reload = function() reloads = reloads + 1 end
      morf.ipc.m_reloads = function() return reloads end
      morf.ipc.m_change = function(value)
        local kept = require("themes").preferences
        kept.set("motion", value)
      end
      require("common.frame").open { id = "probe", title = "Probe", width = 400, height = 400,
        build = function() return require("morf.ui").Item {} end }
    ]], env = { EVA_APPEARANCE = path, EVA_DRY_RUN = "1" } })
    test.advance(100)
    test.eq(test.ipc("m_reloads"), 0)
    test.ipc("m_change", "playful")
    test.advance(100)
    test.truthy(test.ipc("m_reloads") >= 1, "a tool ignored the new style")
  end)
end)
