-- patty's files and rules: the kind and wrong tries a screen reads from
-- /var/lib/patty (EVA_PATTY_DIR elsewhere), and which digits go on the grid.
local morf = require("morf")

local M = { DIR = "/var/lib/patty", TRIES = 5, PAUSE = 300, MIN = 4, MAX = 16 }

local KINDS = { grid = true, keypad = true }

function M.dir()
  local named = morf.env("EVA_PATTY_DIR")
  if named and named ~= "" then return named end
  return M.DIR
end

function M.user_ok(user)
  return type(user) == "string" and #user >= 1 and #user <= 32 and user:match("^[a-z_][a-z0-9_-]*$") ~= nil
end

local function read(path)
  local ok, text = pcall(morf.fs.read, path)
  if ok and type(text) == "string" then return text end
  return nil
end

local function first_word(text)
  local word = text and text:match("^%s*(%a+)")
  if word and KINDS[word] then return word end
  return nil
end

--- "grid", "keypad" or nil: `<user>.kind`, then the first word of `<user>`.
function M.kind(user, options)
  options = options or {}
  if not M.user_ok(user) then return nil end
  local dir = options.dir or M.dir()
  local said = first_word(read(dir .. "/" .. user .. ".kind"))
  if said or options.kind_only then return said end
  return first_word(read(dir .. "/" .. user))
end

--- `{ count, until_at }` from `<user>.fails`, or nil.
function M.fails(user, options)
  options = options or {}
  if not M.user_ok(user) then return nil end
  local text = read((options.dir or M.dir()) .. "/" .. user .. ".fails")
  if not text then return nil end
  local count, until_at = text:match("^%s*(%d+)%s+(%d+)")
  return { count = tonumber(count) or 0, until_at = tonumber(until_at) or 0 }
end

--- Seconds still `locked`, tries `left` and `used`, at epoch second `now`.
function M.standing(fails, now)
  if not fails then return { locked = 0, left = M.TRIES, used = 0 } end
  local locked = math.max(0, math.floor(fails.until_at - now))
  local used = locked > 0 and M.TRIES or math.min(M.TRIES, fails.count)
  return { locked = locked, left = M.TRIES - used, used = used }
end

function M.minutes(seconds) return math.max(1, math.ceil(seconds / 60)) end

function M.neighbours(a, b)
  if a < 1 or a > 9 or b < 1 or b > 9 or a == b then return false end
  local dr, dc = (a - 1) // 3 - (b - 1) // 3, (a - 1) % 3 - (b - 1) % 3
  return dr * dr <= 1 and dc * dc <= 1
end

--- Whether `digits` go on the grid, else false and the first step that breaks it.
function M.drawable(digits)
  local seen, last = {}, nil
  for i = 1, #digits do
    local d = tonumber(digits:sub(i, i))
    if not d then return false, "only digits" end
    if d == 0 then return false, "0 is not on the grid" end
    if seen[d] then return false, d .. " is used twice" end
    if last and not M.neighbours(last, d) then return false, last .. " to " .. d .. " is not a neighbour" end
    seen[d], last = true, d
  end
  return true
end

function M.kind_of(digits) return M.drawable(digits) and "grid" or "keypad" end

function M.valid(digits)
  return type(digits) == "string" and #digits >= M.MIN and #digits <= M.MAX and digits:match("^%d+$") ~= nil
end

return M
