-- Colours that follow the song: while something plays and the setting is on,
-- the album art's accent is the source. Lule reads the art where it can -- a
-- folder holding only that picture, `colors -g`, which writes nothing and runs
-- no hook -- and the engine's own reading stands in where it cannot.
local morf = require("morf")
local config = require("config")
local M = {}

local function art_path(active)
  local url = active.art_url
  if not url or url == "" then return "" end
  return require("lib.util.remote").file(url)
end

--- The accent of Lule's palette in `text` (`lule colors -g -- json`), or nil.
function M.accent_of(text)
  local first = (text or ""):find("{", 1, true)
  if not first then return nil end
  local ok, data = pcall(morf.json.decode, text:sub(first))
  if not ok or type(data) ~= "table" then return nil end
  local colors = type(data.colors) == "table" and data.colors or {}
  local special = type(data.special) == "table" and data.special or {}
  return colors.color1 or colors[2] or special.cursor
end

local serial = 0

-- Lule's reading of `art`: `done(accent)`, nil when it cannot.
local function ask_lule(art, done)
  local folder = morf.paths.cache("eva-song")
  morf.fs.remove(folder, { recursive = true })
  morf.fs.mkdir(folder, { parents = true })
  local extension = art:match("%.(%w+)$") or "jpg"
  local linked = pcall(morf.fs.symlink, art, folder .. "/art." .. extension)
  if not linked then done(nil) return end
  local started = pcall(morf.process.run, { "lule", "--configs=" .. folder, "--cache=" .. folder, "colors", "-g", "--", "json" },
    { env = { LULE_W = folder }, timeout_ms = 20000, max_output = 65536 }, function(result)
      done(result.ok and M.accent_of(result.stdout) or nil)
    end)
  if not started then done(nil) end
end

-- The engine's reading, where Lule cannot.
local function ask_engine(art, done)
  local ok, queued = pcall(morf.image.palette, art, 6, function(success, colors)
    local first = success and colors and colors[1]
    done(first and morf.color(first):hex():sub(1, 7) or nil)
  end)
  if not ok or not queued then done(nil) end
end

--- Reads `art`, and hands `done` an accent or nil.
function M.read(art, done)
  ask_lule(art, function(accent)
    if accent then done(accent, "lule") return end
    ask_engine(art, function(fallback) done(fallback, fallback and "engine" or nil) end)
  end)
end

--- Follows the player while `theme.follow_song` is on.
function M.start()
  local theme = require("palette")
  local timer
  morf.effect("eva.song.theme", function()
    if timer then timer:cancel() timer = nil end
    serial = serial + 1
    local own = serial
    if not config.get("theme.follow_song") then theme.song:set("") return end
    local active = require("services").player()
    local art = art_path(active)
    if art == "" or active.playing ~= true then theme.song:set("") return end
    -- Skipping through tracks settles on one before anything is read.
    timer = morf.time.timer(500, function()
      timer = nil
      M.read(art, function(accent)
        if own == serial and accent then theme.song:set(accent) end
      end)
    end, false)
  end)
end

return M
