-- The notifications on the lock, as the chosen level allows: cards at `all`, a
-- row per app at `senders`, one line at `count`, nothing at `none`. `dots` is
-- one mark per app. Everything drawn here comes from the model; a sender's
-- icon is never loaded, only the first letter of its name.
local M = {}

local function ago(time, now)
  local seconds = math.max(0, now - (time or 0))
  if seconds < 60 then return "now" end
  if seconds < 3600 then return ("%dm"):format(seconds // 60) end
  if seconds < 86400 then return ("%dh"):format(seconds // 3600) end
  return ("%dd"):format(seconds // 86400)
end

--- `view`: `{ ui, s, C, icon, text }`. `spec`: `model`, `style`, `width`, `rows`
--- (at most this many), `now` (fn), `visible`.
function M.build(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local model, W = spec.model, spec.width
  local function item(i) return model.items()[i] end
  local function badge(i, size)
    return ui.Rect { width = size, height = size, radius = size / 2, color = C.secondaryContainer,
      view.text { anchors = { center_in = true }, font_size = math.floor(size * .46), font_weight = 600,
        color = C.onSecondaryContainer,
        text = function()
          local got = item(i)
          return got and (got.app or "?"):sub(1, 1):upper() or ""
        end } }
  end
  local function card(i)
    local function rich() local got = item(i) return got ~= nil and got.summary ~= nil end
    local H = s(66)
    return ui.Rect {
      id = "lock-notification-" .. i, width = W, radius = s(18),
      height = function() return rich() and H or s(48) end,
      color = function() return C.surfaceContainer:alpha(.82) end,
      visible = function() return item(i) ~= nil end,
      ui.Item { x = s(12), anchors = { vertical_center = true }, width = s(32), height = s(32), badge(i, s(32)) },
      ui.Column { x = s(56), anchors = { vertical_center = true }, gap = 0,
        view.text { id = "lock-notification-app-" .. i, width = W - s(56) - s(60), elide = "right",
          font_size = s(13), color = C.onSurfaceVariant,
          text = function()
            local got = item(i)
            if not got then return "" end
            if rich() then return got.app or "" end
            return (got.app or "") .. ((got.count or 0) > 1 and (" · " .. got.count) or "")
          end },
        view.text { id = "lock-notification-summary-" .. i, width = W - s(68), elide = "right",
          font_size = s(15), font_weight = 600, visible = rich,
          text = function() local got = item(i) return got and got.summary or "" end },
        view.text { id = "lock-notification-body-" .. i, width = W - s(68), elide = "right", font_size = s(14),
          color = C.onSurfaceVariant, visible = rich,
          text = function() local got = item(i) return got and got.body or "" end },
      },
      view.text { anchors = { right = true, right_margin = s(14), top = true, top_margin = s(10) },
        font_size = s(12), color = C.onSurfaceVariant,
        text = function() local got = item(i) return got and ago(got.time, spec.now()) or "" end },
    }
  end
  local column = { id = "lock-notifications", gap = s(6), width = W, align = "center", visible = spec.visible }
  if spec.style == "dots" then
    local dots = { id = "lock-notification-dots", gap = s(6), anchors = { horizontal_center = true } }
    for i = 1, 8 do
      local dot = ui.Item { width = s(28), height = s(28), visible = function() return item(i) ~= nil end, badge(i, s(28)) }
      dots[#dots + 1] = dot
    end
    column[#column + 1] = ui.Row(dots)
  else
    for i = 1, spec.rows do column[#column + 1] = card(i) end
  end
  -- A number and nothing else, where the level is `count` or the list ran out.
  column[#column + 1] = view.text {
    id = "lock-notification-count", horizontal_alignment = "center", width = W, font_size = s(15),
    color = C.onSurfaceVariant,
    visible = function()
      local count, shown = model.count(), #model.items()
      return count > 0 and (shown == 0 or (spec.style ~= "dots" and shown > spec.rows))
    end,
    text = function()
      local count, shown = model.count(), #model.items()
      if shown == 0 or spec.rows == 0 then return count == 1 and "1 notification" or (count .. " notifications") end
      return ("%d more"):format(shown - spec.rows)
    end,
  }
  return ui.Column(column)
end

return M
