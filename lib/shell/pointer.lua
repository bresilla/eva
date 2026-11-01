-- Where the pointer stands for a tool that covers the screen. A surface hears
-- the pointer only once it moves, so the first position comes from the
-- compositor where it tells: Hyprland's `hyprctl cursorpos`. Sway's seat cursor
-- is not readable, so there it is the middle of the screen until the first
-- motion.
--
--     pointer.start(function(x, y, known) end)   -- surface pixels
--     pointer.to_surface(x, y)                   -- a global point on this screen
--
-- EVA_FAKE_POINTER=x,y stands in for the compositor, in global pixels.
local morf = require("morf")

local M = {}

local function screen() return (morf.screens or {})[1] or {} end

--- Surface pixels to one pixel of the compositor's global layout.
function M.scale()
  local s = screen()
  if s.width and s.logical_width and s.logical_width > 0 then return s.width / s.logical_width end
  return 1
end

--- The global point `x`, `y` in this screen's surface pixels.
function M.to_surface(x, y)
  local s, scale = screen(), M.scale()
  return (x - (s.x or 0)) * scale, (y - (s.y or 0)) * scale
end

--- The two numbers of "12, 34", or nil.
function M.parse(text)
  local x, y = tostring(text or ""):match("(%-?%d+%.?%d*)%s*,%s*(%-?%d+%.?%d*)")
  if x then return tonumber(x), tonumber(y) end
end

--- The middle of this screen, in surface pixels.
function M.middle()
  local s = screen()
  return (s.width or 1920) / 2, (s.height or 1080) / 2
end

-- `x`, `y` on this screen, or nil where they lie on another.
local function here(x, y)
  local s = screen()
  local at_x, at_y = M.to_surface(x, y)
  if at_x < 0 or at_y < 0 or at_x > (s.width or math.huge) or at_y > (s.height or math.huge) then return nil end
  return at_x, at_y
end

--- `done(x, y, known)` once: surface pixels, `known` false for the middle of
--- the screen.
function M.start(done)
  local function answer(x, y)
    if x then x, y = here(x, y) end
    if x then return done(x, y, true) end
    local mid_x, mid_y = M.middle()
    done(mid_x, mid_y, false)
  end
  local fake = morf.env("EVA_FAKE_POINTER")
  if fake and fake ~= "" then return answer(M.parse(fake)) end
  if not morf.env("HYPRLAND_INSTANCE_SIGNATURE") then return answer(nil) end
  morf.process.run({ "hyprctl", "cursorpos" }, {}, function(result)
    if result and result.ok then answer(M.parse(result.stdout)) else answer(nil) end
  end)
end

return M
