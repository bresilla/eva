-- Passwords and passphrases from the kernel's random source, in the handler that
-- asks. Bytes come from `morf.encoding.uuid`, skipping the bits a UUID fixes, and
-- every choice is made by rejection. The launcher and eva-text both call these.

local morf = require("morf")

local M = {}

M.SETS = {
  lower = "abcdefghijkmnopqrstuvwxyz",
  upper = "ABCDEFGHJKLMNPQRSTUVWXYZ",
  digits = "23456789",
  symbols = "!@#$%^&*()-_=+[]{};:,.?",
}

M.WORDS = require("lib.shell.launcher.passphrase_words")

local pool, used = "", 0

--- The next random byte.
function M.byte()
  if used >= #pool then
    local hex = morf.encoding.uuid():gsub("-", "")
    pool, used = hex:sub(1, 12) .. hex:sub(21, 32), 0
  end
  local byte = tonumber(pool:sub(used + 1, used + 2), 16)
  used = used + 2
  return byte
end

--- A number from 1 to `n` (at most 65536), every one as likely.
function M.pick(n)
  local width = n > 256 and 2 or 1
  local room = 1 << (8 * width)
  local limit = room - room % n
  while true do
    local value = 0
    for _ = 1, width do value = value * 256 + M.byte() end
    if value < limit then return value % n + 1 end
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
  length = math.max(4, math.min(1024, math.floor(length or 20)))
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
  count = math.max(2, math.min(32, math.floor(count or 6)))
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
