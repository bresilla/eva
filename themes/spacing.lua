-- The spacing scale every layout places with: a 4 px grid, the same in both
-- themes, a step tighter or looser with the density preference. `TARGET` is the
-- smallest pressable size for a pointer, `TOUCH` for a finger, which no density
-- takes away.
local DENSITIES = {
  compact = { xxs = 2, xs = 2, s = 4, m = 8, l = 12, xl = 16, xxl = 24, TARGET = 36, TOUCH = 48 },
  normal = { xxs = 2, xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32, TARGET = 40, TOUCH = 48 },
  spacious = { xxs = 4, xs = 8, s = 12, m = 16, l = 24, xl = 32, xxl = 40, TARGET = 44, TOUCH = 48 },
}
local ok, themes = pcall(require, "themes")
local density = ok and themes.preferences and themes.preferences.get("density") or "normal"
return DENSITIES[density] or DENSITIES.normal
