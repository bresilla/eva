-- Segment digits, 3 x 5 px of 1 px strokes 4 px apart, as path data.
local SEGMENTS = {
  a = { 0, .5, 3, .5 }, g = { 0, 2.5, 3, 2.5 }, d = { 0, 4.5, 3, 4.5 },
  f = { .5, 0, .5, 3 }, b = { 2.5, 0, 2.5, 3 }, e = { .5, 2, .5, 5 }, c = { 2.5, 2, 2.5, 5 },
}
local LIT = { ["0"] = "abcdef", ["1"] = "bc", ["2"] = "abged", ["3"] = "abgcd", ["4"] = "fgbc",
  ["5"] = "afgcd", ["6"] = "afgedc", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abcdfg" }
local D = { ADVANCE = 4 }

--- Appends to `out` the strokes of `text` (digits) from `x`, `y`.
function D.put(out, text, x, y)
  for i = 1, #text do
    for s in (LIT[text:sub(i, i)] or ""):gmatch(".") do
      local v = SEGMENTS[s]
      out[#out + 1] = ("M%g %g L%g %g "):format(x + v[1], y + v[2], x + v[3], y + v[4])
    end
    x = x + D.ADVANCE
  end
  return out
end

--- How wide `text` is drawn.
function D.width(text) return #text * D.ADVANCE - 1 end

return D
