-- Passwords and passphrases from the system's random source. Bytes come from
-- `morf.encoding.uuid`, skipping the bits a UUID fixes, and every choice is made
-- by rejection.

local morf = require("morf")

local M = {}

M.SETS = {
  lower = "abcdefghijkmnopqrstuvwxyz",
  upper = "ABCDEFGHJKLMNPQRSTUVWXYZ",
  digits = "23456789",
  symbols = "!@#$%^&*()-_=+[]{};:,.?",
}

M.WORDS = {
  "able", "acid", "aged", "also", "amber", "apple", "arch", "area", "army", "aunt", "away", "axis", "baby", "back",
  "bake", "ball", "band", "bank", "barn", "base", "bath", "beam", "bear", "beat", "bell", "belt", "bend", "bike", "bird",
  "blue", "boat", "body", "bold", "bolt", "bone", "book", "boot", "born", "bowl", "brass", "bread", "brick", "brook",
  "bulb", "bull", "burn", "bush", "cabin", "cake", "calm", "camp", "cane", "cape", "card", "care", "cart", "case",
  "cash", "cast", "cave", "cedar", "chalk", "chart", "chef", "chess", "chin", "city", "clay", "clip", "cloth", "cloud",
  "clove", "club", "coal", "coast", "coat", "code", "coil", "cold", "comb", "cook", "cool", "coral", "cord", "cork",
  "corn", "cove", "crab", "crane", "crew", "crop", "crow", "cube", "curl", "dale", "dark", "dawn", "deck", "deep",
  "deer", "desk", "dial", "dish", "dock", "dome", "door", "dove", "down", "draw", "drum", "duck", "dune", "dusk",
  "dust", "each", "earl", "east", "echo", "edge", "elm", "ember", "epic", "even", "face", "fair", "fall", "farm",
  "fawn", "feet", "fern", "ferry", "field", "film", "fine", "fire", "firm", "fish", "flag", "flat", "flax", "flint",
  "flock", "flow", "foam", "fog", "fold", "folk", "food", "foot", "ford", "fork", "form", "fort", "fox", "frog", "frost",
  "fuel", "gale", "game", "gate", "gear", "gift", "glad", "glen", "glow", "gold", "golf", "good", "gown", "grain",
  "grape", "grass", "gray", "green", "grove", "gulf", "hail", "hall", "hand", "hare", "harp", "hawk", "hazel", "heat",
  "herb", "hero", "hill", "hive", "holly", "home", "honey", "hook", "hope", "horn", "hose", "hour", "hull", "hunt",
  "iron", "island", "ivory", "ivy", "jade", "jazz", "jelly", "jolly", "judge", "juice", "jump", "june", "keel", "kelp",
  "kettle", "kite", "kiwi", "knee", "knob", "knot", "lace", "lake", "lamb", "lamp", "land", "lane", "lark", "lava",
  "lawn", "leaf", "lemon", "lens", "lily", "lime", "line", "lion", "loaf", "lock", "loft", "log", "loom", "lotus",
  "lunar", "lute", "maize", "mango", "maple", "marsh", "mast", "meadow", "melon", "mesa", "mild", "mill", "mint",
}

local pool, used = "", 0

local function take()
  if used >= #pool then
    local hex = morf.encoding.uuid():gsub("-", "")
    pool, used = hex:sub(1, 12) .. hex:sub(21, 32), 0
  end
  local byte = tonumber(pool:sub(used + 1, used + 2), 16)
  used = used + 2
  return byte
end

--- A number from 1 to `n` (at most 256), every one as likely.
function M.pick(n)
  local limit = 256 - 256 % n
  while true do
    local byte = take()
    if byte < limit then return byte % n + 1 end
  end
end

--- The characters `options` allow. `options`: `symbols` (true), `digits`
--- (true), `upper` (true).
function M.alphabet(options)
  options = options or {}
  local out = M.SETS.lower
  if options.upper ~= false then out = out .. M.SETS.upper end
  if options.digits ~= false then out = out .. M.SETS.digits end
  if options.symbols ~= false then out = out .. M.SETS.symbols end
  return out
end

--- A password `length` long, with one of each kind of character it may hold.
function M.generate(length, options)
  options = options or {}
  length = math.max(4, math.min(256, math.floor(length or 20)))
  local alphabet = M.alphabet(options)
  local chars = {}
  for i = 1, length do
    local at = M.pick(#alphabet)
    chars[i] = alphabet:sub(at, at)
  end
  local slots = {}
  for i = 1, length do slots[i] = i end
  local function place(set)
    local at = M.pick(#slots)
    local slot = table.remove(slots, at)
    local index = M.pick(#set)
    chars[slot] = set:sub(index, index)
  end
  place(M.SETS.lower)
  if options.upper ~= false then place(M.SETS.upper) end
  if options.digits ~= false then place(M.SETS.digits) end
  if options.symbols ~= false then place(M.SETS.symbols) end
  return table.concat(chars)
end

--- `count` random words, joined by `separator`.
function M.passphrase(count, separator)
  count = math.max(3, math.min(16, math.floor(count or 6)))
  local words = {}
  for i = 1, count do words[i] = M.WORDS[M.pick(#M.WORDS)] end
  return table.concat(words, separator or "-")
end

--- About how many bits a password of `length` from `size` characters holds.
function M.bits(length, size) return math.floor(length * math.log(size, 2)) end

--- About how many bits a passphrase of `count` words holds.
function M.passphrase_bits(count) return math.floor(count * math.log(#M.WORDS, 2)) end

--- Words for a strength of `bits`.
function M.strength(bits)
  if bits >= 128 then return "Very strong" end
  if bits >= 80 then return "Strong" end
  if bits >= 50 then return "Fair" end
  return "Weak"
end

return M
