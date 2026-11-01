-- A phone's part of the lock. A locked session shows only the lock's surfaces,
-- so the lock hosts the call screen, the SIM's prompt and emergency dialling
-- over its own scene. The shell stays the owner of calls: it rings, logs and
-- routes the sound; this process watches the same modem and only shows and acts.
--
--   local scene = require(visual.lock)(ctx)(width, height, name)
--   require("themes.phone_lock").host(scene, { C = C, text = ctx.text, icon = ctx.icon,
--     visual = visual, width = width, height = height })
--   return scene
--
-- It goes inside `scene`, whose opaque Rect stays the root. Nothing here is built
-- until a modem that can call is there, however late. The shell writes what the
-- lock cannot read itself to `phone/lock.json` in the state folder.
local morf = require("morf")
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = { open_emergency = morf.signal("eva.lock.emergency", false) }

local BUTTON_W = 136

local function settings()
  local dir = (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/phone/lock.json"
  local ok, text = pcall(morf.fs.read, dir)
  local fine, value = pcall(morf.json.decode, ok and text or "")
  return fine and type(value) == "table" and value or {}
end

--- The modem, the book and the models, once for the process; nil without a
--- modem that can call.
function M.session()
  if M.started ~= nil then return M.started or nil end
  local ok, mobile, standin = pcall(function() return require("lib.services.modem").session() end)
  if not ok or not mobile or not mobile.voice then
    M.started = false
    return nil
  end
  local saved = settings()
  local book = require("lib.services.contacts").open {
    folder = morf.env("EVA_CONTACTS") or saved.contacts, country = saved.country,
  }
  M.started = {
    mobile = mobile, book = book, standin = standin, medical = saved.medical or "",
    phone = require("models.phone_calls").new { mobile = mobile, book = book, owner = false },
    sim = require("models.phone_sim").new { mobile = mobile },
  }
  return M.started
end

local function look_of(spec)
  local tsugumori = spec.visual and spec.visual.id == "tsugumori"
  return {
    C = spec.C, text = spec.text, icon = spec.icon, action = ui.MouseArea,
    round = function(r) return tsugumori and 0 or r end,
    bounce = { duration = 300, easing = "out_back" },
  }
end

--- Puts the phone's surfaces over `scene`, `spec` as the header says.
function M.host(scene, spec)
  local session = M.session()
  if not session then return end
  local phone, sim, mobile = session.phone, session.sim, session.mobile
  local look = look_of(spec)
  local function width() return spec.width end
  local function height() return spec.height end
  local function calling() return phone.stage:get() ~= "idle" end
  local function surfaces()
    return ui.Item { width = spec.width, height = spec.height,
      ui.Item { id = "lock-emergency-button", z = 40,
        x = S.xl, y = spec.height - S.TOUCH - S.xl, width = BUTTON_W, height = S.TOUCH,
        visible = function() return not calling() and not sim.asking() end,
        look.action { id = "lock-emergency", accessible_name = "Emergency call", anchors = { fill = true },
          cursor = "pointer", on_clicked = function() M.open_emergency:set(true) end,
          ui.Rect { anchors = { fill = true }, radius = look.round(S.TOUCH / 2),
            color = function() return spec.C.surface:alpha(0.56) end },
          ui.Row { anchors = { center_in = true }, gap = S.xs, align = "center",
            look.icon("emergency", S.l + S.xxs, function() return spec.C.error end),
            look.text { text = "Emergency", font_size = S.m + S.xxs,
              color = function() return spec.C.onSurface end } } },
      },
      ui.Item { id = "lock-sim", z = 50, width = spec.width, height = spec.height,
        visible = function() return sim.asking() and not calling() end,
        require("themes.sim_prompt").build { sim = sim, look = look, width = width, height = height },
      },
      ui.Item { id = "lock-emergency-pad", z = 60, width = spec.width, height = spec.height,
        visible = function() return M.open_emergency:get() and not calling() end,
        require("themes.emergency_pad").build { phone = phone, book = session.book, look = look,
          medical = session.medical, width = width, height = height, open = M.open_emergency },
      },
      ui.Item { id = "lock-call", z = 70, width = spec.width, height = spec.height, visible = calling,
        require("themes.call_screen").build { phone = phone, look = look, width = width, height = height,
          held_open = true },
      },
    }
  end
  local built = false
  morf.effect("eva.lock.voice", function()
    if mobile.voice.present:get() and not built then
      built = true
      ui.reparent(surfaces(), scene)
    end
  end, { owner = scene })
  if session.standin then
    morf.ipc.phone = function(what, ...)
      local act = session.standin[what]
      if act then return act(...) end
      if what == "state" then return { stage = phone.stage:get(), sim = sim.asking() } end
      if what == "emergency" then M.open_emergency:set(true) return true end
    end
  end
end

return M
