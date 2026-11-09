-- The welcome, a Settings page: the kit's onboarding pager with its progress
-- along the top, one short step at a time, and the way on at the foot. Each
-- step leads to the real page for what it is about, and Back returns here.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local widgets = require("themes.kit.widgets")
local M = {}

local RAIL = theme.space.xl
local MODES = { { "dark", "dark_mode", "Dark" }, { "light", "light_mode", "Light" } }

local function get(v) if type(v) == "function" then return v() end return v end

local function rows(prefix, list, inner)
  local out = { width = inner, gap = P.ROW_GAP }
  for index, row in ipairs(list) do
    out[index] = F.fact { id = prefix .. index, width = inner, icon = row[1], title = row[2], subtitle = row[3] }
  end
  return ui.Column(out)
end

-- The steps along the top, one segment each, filled up to the one on show.
local function progress(model, names, w)
  local C, GAP = theme.color, theme.space.xs
  local seg = (get(w) - GAP * (#names - 1)) / math.max(1, #names)
  local row = { id = "welcome-progress", y = math.floor((RAIL - 4) / 2), gap = GAP }
  for i in ipairs(names) do
    row[i] = ui.Rect { width = seg, height = 4, radius = 2,
      color = function() return i <= model.step:get() and C.primary or C.secondaryContainer end,
      behavior = { color = { duration = theme.duration.small } } }
  end
  return ui.Row(row)
end

function M.page(model, settings, w, h)
  local inner = P.inner(w)
  local mode = require("themes.color_mode")
  local guide = require("gesture_guide")
  local function open(key) return function() settings.request(key, "welcome") end end

  local STEPS = {
    look = function(body_w, body_h)
      return P.page { id = "welcome-look", width = body_w, height = body_h,
        P.section { id = "welcome-look-card", width = body_w, title = "Make it yours",
          F.note(inner, "You can change it whenever you like"),
          F.choices { id = "welcome-mode", width = inner, items = MODES, per_row = 2,
            now = function() return require("appearance_model").mode() end, pick = mode.set },
          F.link { id = "welcome-theme", width = inner, icon = "palette", title = "Theme and colours",
            subtitle = "Lule colours, fonts and motion", go = open("theme") },
        } }
    end,
    network = function(body_w, body_h)
      return P.page { id = "welcome-network", width = body_w, height = body_h,
        P.section { id = "welcome-network-card", width = body_w, title = "Get online",
          F.note(inner, "Join a network now, or do it later from Quick settings."),
          F.link { id = "welcome-wifi", width = inner, icon = "wifi",
            title = function() return model.network().title end,
            subtitle = function() return model.network().subtitle end, go = open("network") },
        } }
    end,
    gestures = function(body_w, body_h)
      return P.page { id = "welcome-gestures", width = body_w, height = body_h,
        P.section { id = "welcome-gestures-card", width = body_w, title = "Getting around",
          F.note(inner, "What this device answers to."),
          rows("welcome-gesture-", guide.gestures(), inner),
        } }
    end,
    keys = function(body_w, body_h)
      return P.page { id = "welcome-keys", width = body_w, height = body_h,
        P.section { id = "welcome-keys-card", width = body_w, title = "The keys to know",
          F.note(inner, "The few worth learning first."),
          rows("welcome-key-", guide.keys(), inner),
          F.link { id = "welcome-all-keys", width = inner, icon = "keyboard", title = "See every key",
            subtitle = "Search them all", go = model.all_keys },
        } }
    end,
  }

  local names, pages = model.steps(), {}
  local foot = theme.space.s + P.BUTTON_H
  -- A sheet stands as tall as the longest step, so it does not jump between them.
  local longest = math.max(#guide.gestures(), model.steps()[4] and #guide.keys() + 1 or 0)
  P.report(function()
    return RAIL + P.CAPTION_H + 2 * P.PAD + 2 * L.lh(P.SUB) + longest * (P.ROW_H + P.ROW_GAP) + foot + P.GAP
  end)
  local function pager_h() return get(h) - foot end
  for _, name in ipairs(names) do
    pages[name] = function()
      local function body_h() return pager_h() - RAIL end
      return ui.Item { width = w, height = pager_h, ui.Item { y = RAIL, width = w, height = body_h, STEPS[name](w, body_h) } }
    end
  end
  local stack, nav = widgets.onboarding { id = "welcome-pages", width = w, height = pager_h, mode = "switcher", order = names,
    pages = pages, current = names[1], chrome = false }

  local skip = P.button { id = "welcome-skip", label = "Skip", on_clicked = model.skip, visible = function() return not model.last() end }
  local back = P.button { id = "welcome-back", label = "Back", icon = "arrow_back", on_clicked = model.back, visible = model.can_back }
  local go = P.button { id = "welcome-next", tone = "primary", on_clicked = model.next,
    label = function() return model.last() and "Done" or "Next" end }
  local root = ui.Item { id = "welcome", width = w, height = h,
    stack,
    progress(model, names, w),
    ui.Item { y = function() return pager_h() + theme.space.s end, width = w, height = P.BUTTON_H,
      ui.Row { gap = theme.space.s, align = "center", back, skip },
      ui.Item { anchors = { right = true }, width = function() return go.width end, height = P.BUTTON_H, go } },
  }
  morf.effect("welcome.step", function()
    local name = names[model.step:get()]
    if name then nav.go(name) end
  end, { owner = root })
  return root
end

return M
