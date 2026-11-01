-- Colour schemes people know by name, as sources beside Lule. Each is the
-- published palette: its sixteen terminal colours, background, foreground and
-- accent. `M.roles` lays it over the Material role names every view reads, and
-- `M.tool` gives it the shape a colour tool's palette has.
local morf = require("morf")
local M = {}

-- Each flavour: `ground` to `top` the surfaces, dark to light in a dark scheme,
-- then ink, muted ink, accents and the sixteen.
local function flavour(t) return t end

M.LIST = {
  { id = "catppuccin", name = "Catppuccin",
    dark = flavour { mode = "dark", ground = "#1e1e2e", low = "#181825", mid = "#313244", high = "#45475a", top = "#585b70",
      ink = "#cdd6f4", soft = "#a6adc8", accent = "#cba6f7", second = "#89b4fa", third = "#94e2d5", alert = "#f38ba8",
      colors = { "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
        "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8" } },
    light = flavour { mode = "light", ground = "#eff1f5", low = "#e6e9ef", mid = "#ccd0da", high = "#bcc0cc", top = "#acb0be",
      ink = "#4c4f69", soft = "#6c6f85", accent = "#8839ef", second = "#1e66f5", third = "#179299", alert = "#d20f39",
      colors = { "#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be",
        "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc" } } },
  { id = "gruvbox", name = "Gruvbox",
    dark = flavour { mode = "dark", ground = "#282828", low = "#1d2021", mid = "#3c3836", high = "#504945", top = "#665c54",
      ink = "#ebdbb2", soft = "#bdae93", accent = "#fabd2f", second = "#83a598", third = "#8ec07c", alert = "#fb4934",
      colors = { "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
        "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2" } },
    light = flavour { mode = "light", ground = "#fbf1c7", low = "#f2e5bc", mid = "#ebdbb2", high = "#d5c4a1", top = "#bdae93",
      ink = "#3c3836", soft = "#665c54", accent = "#b57614", second = "#076678", third = "#427b58", alert = "#9d0006",
      colors = { "#fbf1c7", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#7c6f64",
        "#928374", "#9d0006", "#79740e", "#b57614", "#076678", "#8f3f71", "#427b58", "#3c3836" } } },
  { id = "nord", name = "Nord",
    dark = flavour { mode = "dark", ground = "#2e3440", low = "#292e39", mid = "#3b4252", high = "#434c5e", top = "#4c566a",
      ink = "#eceff4", soft = "#d8dee9", accent = "#88c0d0", second = "#81a1c1", third = "#8fbcbb", alert = "#bf616a",
      colors = { "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
        "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4" } },
    light = flavour { mode = "light", ground = "#eceff4", low = "#e5e9f0", mid = "#d8dee9", high = "#c8d0dd", top = "#b8c2d2",
      ink = "#2e3440", soft = "#4c566a", accent = "#5e81ac", second = "#81a1c1", third = "#8fbcbb", alert = "#bf616a",
      colors = { "#3b4252", "#bf616a", "#a3be8c", "#d08770", "#5e81ac", "#b48ead", "#88c0d0", "#e5e9f0",
        "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4" } } },
  { id = "tokyonight", name = "Tokyo Night",
    dark = flavour { mode = "dark", ground = "#1a1b26", low = "#16161e", mid = "#24283b", high = "#292e42", top = "#414868",
      ink = "#c0caf5", soft = "#a9b1d6", accent = "#7aa2f7", second = "#bb9af7", third = "#7dcfff", alert = "#f7768e",
      colors = { "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
        "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5" } },
    light = flavour { mode = "light", ground = "#e1e2e7", low = "#d5d6db", mid = "#c4c8da", high = "#b4b5b9", top = "#a1a6c5",
      ink = "#3760bf", soft = "#6172b0", accent = "#2e7de9", second = "#9854f1", third = "#007197", alert = "#f52a65",
      colors = { "#e9e9ed", "#f52a65", "#587539", "#8c6c3e", "#2e7de9", "#9854f1", "#007197", "#6172b0",
        "#a1a6c5", "#f52a65", "#587539", "#8c6c3e", "#2e7de9", "#9854f1", "#007197", "#3760bf" } } },
  { id = "dracula", name = "Dracula",
    dark = flavour { mode = "dark", ground = "#282a36", low = "#21222c", mid = "#343746", high = "#44475a", top = "#565869",
      ink = "#f8f8f2", soft = "#c8c9c2", accent = "#bd93f9", second = "#ff79c6", third = "#8be9fd", alert = "#ff5555",
      colors = { "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
        "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff" } } },
  { id = "rosepine", name = "Rosé Pine",
    dark = flavour { mode = "dark", ground = "#191724", low = "#1f1d2e", mid = "#26233a", high = "#403d52", top = "#524f67",
      ink = "#e0def4", soft = "#908caa", accent = "#c4a7e7", second = "#ebbcba", third = "#9ccfd8", alert = "#eb6f92",
      colors = { "#26233a", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
        "#6e6a86", "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4" } },
    light = flavour { mode = "light", ground = "#faf4ed", low = "#fffaf3", mid = "#f2e9e1", high = "#dfdad9", top = "#cecacd",
      ink = "#575279", soft = "#797593", accent = "#907aa9", second = "#d7827e", third = "#56949f", alert = "#b4637a",
      colors = { "#f2e9e1", "#b4637a", "#286983", "#ea9d34", "#56949f", "#907aa9", "#d7827e", "#575279",
        "#9893a5", "#b4637a", "#286983", "#ea9d34", "#56949f", "#907aa9", "#d7827e", "#575279" } } },
}
M.BY_ID = {}
for _, scheme in ipairs(M.LIST) do M.BY_ID[scheme.id] = scheme end

--- Whether `source` names a scheme.
function M.is(source) return M.BY_ID[source] ~= nil end

--- The flavour of `id` for `mode`: a scheme with one flavour keeps it.
function M.flavour(id, mode)
  local scheme = M.BY_ID[id]
  if not scheme then return nil end
  return scheme[mode] or scheme.dark
end

local function on(color)
  return morf.color(color):is_light() and morf.color("#101014") or morf.color("#fbfbfd")
end

--- The Material roles for scheme `id` in `mode`.
function M.roles(id, mode)
  local f = M.flavour(id, mode)
  if not f then return nil end
  local c = function(hex) return morf.color(hex) end
  local accent, second, third, alert = c(f.accent), c(f.second), c(f.third), c(f.alert)
  local ground = c(f.ground)
  local function tint(color, amount) return ground:mix(color, amount, "oklab") end
  return {
    primary = accent, onPrimary = on(f.accent), primaryContainer = tint(accent, 0.3), onPrimaryContainer = c(f.ink),
    inversePrimary = tint(accent, 0.6), primaryFixed = accent, primaryFixedDim = tint(accent, 0.8),
    onPrimaryFixed = on(f.accent), onPrimaryFixedVariant = c(f.ink),
    secondary = second, onSecondary = on(f.second), secondaryContainer = tint(second, 0.3), onSecondaryContainer = c(f.ink),
    secondaryFixed = second, secondaryFixedDim = tint(second, 0.8), onSecondaryFixed = on(f.second), onSecondaryFixedVariant = c(f.ink),
    tertiary = third, onTertiary = on(f.third), tertiaryContainer = tint(third, 0.3), onTertiaryContainer = c(f.ink),
    tertiaryFixed = third, tertiaryFixedDim = tint(third, 0.8), onTertiaryFixed = on(f.third), onTertiaryFixedVariant = c(f.ink),
    error = alert, onError = on(f.alert), errorContainer = tint(alert, 0.3), onErrorContainer = c(f.ink),
    background = ground, onBackground = c(f.ink), surface = ground, onSurface = c(f.ink),
    surfaceVariant = c(f.mid), onSurfaceVariant = c(f.soft), surfaceDim = c(f.low), surfaceBright = c(f.high),
    surfaceTint = accent, inverseSurface = c(f.ink), inverseOnSurface = ground,
    surfaceContainerLowest = c(f.low), surfaceContainerLow = tint(c(f.mid), 0.4), surfaceContainer = c(f.mid),
    surfaceContainerHigh = c(f.high), surfaceContainerHighest = c(f.top),
    outline = c(f.soft), outlineVariant = c(f.high), shadow = c("#000000"), scrim = c("#000000"),
  }
end

--- Scheme `id` as a colour tool's palette (shell/terminal_colors.lua's shape).
function M.tool(id, mode)
  local f = M.flavour(id, mode)
  if not f then return nil end
  local palette = { background = f.ground, foreground = f.ink, cursor = f.accent }
  for i = 0, 15 do palette["color" .. i] = f.colors[i + 1] end
  return { accent = f.accent, mode = f.mode, palette = palette }
end

return M
