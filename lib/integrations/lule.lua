-- lule's colours: what `lule create ... -- set` last generated, kept current.
--
-- lule (a colour generator for terminals and desktops) writes its scheme to
-- `$LULE_A/colors.json` (`~/.cache/lule` by default): the wallpaper it was
-- made from, the theme (dark or light), a background, a foreground and a
-- cursor, and 256 colours. This reads that file and watches it, so a shell
-- re-themes the moment lule runs.
--
--   local lule = require("lib.integrations.lule")
--   local scheme = lule.watch()            -- a signal; nil until lule has run
--   ui.Rect { color = function() local s = scheme:get() return s and s.accent or "#888" end }
--
-- A scheme is `{ accent, background, foreground, cursor, theme, wallpaper,
-- colors }`; `colors` counts from one (colors[1] is colour 0). The accent is
-- colour 1, which lule also gives the cursor.

local morf = require("morf")

local lule = {}
-- Each consumer owns a live watch. Replacing a single module-wide handle
-- lets Lua collect the wallpaper's watch when the Lule drawer subscribes.
local watches = {}

--- Where lule keeps its scheme.
function lule.path()
  local dir = morf.env("LULE_A") or ""
  if dir == "" then dir = morf.fs.join(morf.fs.home(), ".cache/lule") end
  return morf.fs.join(dir, "colors.json")
end

local PICTURES = { png = true, jpg = true, jpeg = true, webp = true, bmp = true, gif = true, avif = true }

local function expand(path)
  if path == "~" then return morf.fs.home() end
  if path:sub(1, 2) == "~/" then return morf.fs.home() .. path:sub(2) end
  return path
end

--- The wallpaper folder: `chosen` (the setting `lule.folder`), then LULE_W,
--- then the folder of `current`, then ~/Pictures/Wallpapers.
function lule.folder(chosen, current)
  local folder = chosen or ""
  if folder == "" then folder = morf.env("LULE_W") or "" end
  if folder == "" then folder = (current or ""):match("^(.*)/") or (morf.fs.home() .. "/Pictures/Wallpapers") end
  return expand(folder)
end

local LIST_DEPTH, LIST_MOST = 4, 4000

--- The pictures in `path`, by name: `{ path, name, modified }` each; with
--- `deep`, its folders' too. Nil and why for a folder that cannot be read.
function lule.pictures(path, deep)
  path = expand(path or "")
  if not morf.fs.is_dir(path) then return nil, "That wallpaper folder does not exist." end
  local files = {}
  local function walk(folder, depth)
    local ok, entries = pcall(morf.fs.list, folder, { follow = true })
    if not ok or type(entries) ~= "table" then return false end
    for _, entry in ipairs(entries) do
      if #files >= LIST_MOST then break end
      if entry.is_file and PICTURES[(entry.extension or ""):lower()] then
        files[#files + 1] = { path = entry.path, name = entry.name, modified = entry.modified }
      elseif deep and entry.is_dir and depth < LIST_DEPTH then
        walk(entry.path, depth + 1)
      end
    end
    return true
  end
  if not walk(path, 1) then return nil, "Cannot read that wallpaper folder." end
  table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
  return files
end

--- The scheme in lule's file, or nil and why.
function lule.read(path)
  path = path or lule.path()
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" or text == "" then return nil, "no lule scheme at " .. path end
  local fine, data = pcall(morf.json.decode, text)
  if not fine or type(data) ~= "table" then return nil, "lule's scheme is not JSON" end
  local special = type(data.special) == "table" and data.special or {}
  local colors = {}
  if type(data.colors) == "table" then
    for i, c in ipairs(data.colors) do colors[i] = c end
  end
  local accent = colors[2] or special.cursor
  if type(accent) ~= "string" then return nil, "lule's scheme has no colours" end
  return {
    accent = accent,
    background = special.background or colors[1],
    foreground = special.foreground or colors[8],
    cursor = special.cursor or accent,
    theme = data.theme == "light" and "light" or "dark",
    wallpaper = type(data.wallpaper) == "string" and data.wallpaper or "",
    colors = colors,
  }
end

--- A signal holding lule's scheme (nil until there is one), kept current
--- as lule writes; `name` names the signal ("lule").
function lule.watch(name)
  name = name or "lule"
  local path = lule.path()
  local signal = morf.signal(name, (lule.read(path)))
  watches[name] = morf.fs.watch(path, function()
    local scheme = lule.read(path)
    if scheme then signal:set(scheme) end
  end)
  return signal
end

--- Generate and apply through lule's own configuration and hooks. No shell
--- interpolation: image paths (including spaces) stay one argument.
--- `image` or `directory`, `theme`, `palette`; optional `configs`, `cache`,
--- `env`, `command`. Completion receives morf.process.run's result.
function lule.generate(opts, done)
  opts = opts or {}
  if not opts.image or opts.image == "" then
    if not opts.directory or opts.directory == "" then return nil, "Choose an image or wallpaper folder first." end
  end
  if opts.theme and opts.theme ~= "dark" and opts.theme ~= "light" then return nil, "Unknown theme." end
  local palettes = { pigment = true, median = true, histogram = true, tonal = true }
  if opts.palette and not palettes[opts.palette] then return nil, "Unknown palette method." end
  local argv = { opts.command or "lule" }
  if opts.configs then argv[#argv + 1] = "--configs=" .. opts.configs end
  if opts.cache then argv[#argv + 1] = "--cache=" .. opts.cache end
  argv[#argv + 1] = "create"
  argv[#argv + 1] = opts.image and opts.image ~= "" and ("--image=" .. opts.image)
    or ("--wallpath=" .. opts.directory)
  if opts.theme then argv[#argv + 1] = "--theme=" .. opts.theme end
  if opts.palette then argv[#argv + 1] = "--palette=" .. opts.palette end
  argv[#argv + 1], argv[#argv + 2] = "--", "set"
  return morf.process.run(argv, { env = opts.env, timeout_ms = 60000, max_output = 65536 }, done)
end

return lule
