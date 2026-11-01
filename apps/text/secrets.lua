-- Passwords and passphrases, from /dev/urandom through `od`, which writes its bytes
-- as numbers. A byte that would favour some choices over others is thrown away.
local sys = require("common.sys")
local words = require("words")

local M = {}

M.LOWER = "abcdefghijklmnopqrstuvwxyz"
M.UPPER = M.LOWER:upper()
M.DIGITS = "0123456789"
M.SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?"

--- `count` random bytes, a list: `done(bytes)`, nil where there are none.
function M.bytes(count, done)
  sys.run({ "od", "-An", "-tu1", "-N", tostring(count), "/dev/urandom" }, { read = true, timeout_ms = 3000 }, function(result)
    if not result.ok then done(nil) return end
    local out = {}
    for number in result.stdout:gmatch("%d+") do out[#out + 1] = tonumber(number) end
    done(#out == count and out or nil)
  end)
end

--- The bits a choice of one in `size`, made `count` times, holds.
function M.entropy(size, count) return math.floor(count * math.log(size, 2)) end

--- Picks `count` indexes below `size`, `width` bytes to each: `done(list)`.
function M.choices(size, count, width, done)
  local room = 256 ^ width
  local fair = math.floor(room / size) * size
  local out = {}
  local function more()
    M.bytes((count - #out) * width * 2, function(bytes)
      if not bytes then done(nil) return end
      for at = 1, #bytes - width + 1, width do
        local value = 0
        for offset = 0, width - 1 do value = value * 256 + bytes[at + offset] end
        if value < fair and #out < count then out[#out + 1] = value % size end
      end
      if #out < count then more() else done(out) end
    end)
  end
  more()
end

--- A password `length` long: `done(password, bits)`.
function M.password(length, symbols, done)
  local alphabet = M.LOWER .. M.UPPER .. M.DIGITS .. (symbols and M.SYMBOLS or "")
  M.choices(#alphabet, length, 1, function(list)
    if not list then done(nil) return end
    local out = {}
    for index, value in ipairs(list) do out[index] = alphabet:sub(value + 1, value + 1) end
    done(table.concat(out), M.entropy(#alphabet, length))
  end)
end

--- A passphrase of `count` words: `done(phrase, bits)`.
function M.passphrase(count, done)
  M.choices(#words, count, 2, function(list)
    if not list then done(nil) return end
    local out = {}
    for index, value in ipairs(list) do out[index] = words[value + 1] end
    done(table.concat(out, "-"), M.entropy(#words, count))
  end)
end

return M
