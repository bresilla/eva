-- What the wallpaper page acts on: where a picture goes, the slideshow, the
-- light and dark pictures and the favourites. State and actions only; the
-- pictures are listed and coloured by the Lule studio.
local morf = require("morf")
local config = require("config")
local wallpaper = require("wallpaper")
local M = {}

M.INTERVALS = { { 60, "1 min" }, { 300, "5 min" }, { 900, "15 min" }, { 1800, "30 min" }, { 3600, "1 hour" },
  { 21600, "6 hours" }, { 86400, "1 day" } }
M.FITS = { { "crop", "Crop" }, { "fit", "Fit" }, { "stretch", "Stretch" } }
M.PARALLAX = { { 0, "Off" }, { 0.05, "Subtle" }, { 0.12, "Clear" }, { 0.2, "Strong" } }

-- Where the next picture goes: "all", "output:NAME" or "workspace:N".
M.target = morf.signal("eva.wallpaper.target", "all")

local function studio() return require("lule_studio") end
local expand = require("lib.integrations.lule").expand

--- The places a picture can go on this machine: `{ id, name }`.
function M.targets()
  morf.window.screens_revision()
  local out = { { id = "all", name = "Everywhere" } }
  for _, screen in ipairs(morf.screens or {}) do
    out[#out + 1] = { id = "output:" .. screen.name, name = screen.name }
  end
  out[#out + 1] = { id = "workspace:" .. wallpaper.workspace(), name = "Workspace " .. wallpaper.workspace() }
  return out
end

--- Whether Lule can make the colours here.
function M.can_color()
  local dry = morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then return false end
  return require("services").installed("lule") == true
end

-- The target's own picture, or the place it would take.
local function place(path, target)
  local kind, name = target:match("^(%a+):(.+)$")
  if kind == "output" then wallpaper.set_output(name, path) return true end
  if kind == "workspace" then wallpaper.set_workspace(tonumber(name) or name, path) return true end
  return false
end

--- `path` on the current target. Everywhere goes through Lule, which makes its
--- colours and runs its hooks, where Lule can; `at` is where the change starts.
function M.choose(path, at)
  wallpaper.origin = at
  if place(path, M.target:get()) then return true end
  if M.can_color() then
    local s = studio()
    if s.select(path) then return s.apply() end
    return false
  end
  wallpaper.set(path)
  return true
end

--- What the target would show of its own ("" when it has none).
function M.assigned(target)
  local kind, name = (target or M.target:get()):match("^(%a+):(.+)$")
  if kind == "output" then
    local own = wallpaper.record("wallpaper.outputs", "output", name)
    return own and own.path or ""
  elseif kind == "workspace" then
    local own = wallpaper.record("wallpaper.workspaces", "workspace", name)
    return own and own.path or ""
  end
  return ""
end

--- The target back to the picture everywhere.
function M.clear() place("", M.target:get()) end

--- Marks `path` for the light (`"day"`) or dark (`"night"`) mode.
function M.set_timed(which, path) config.set("wallpaper." .. which, path or "") end

function M.favourite(path)
  for _, item in ipairs(config.get("wallpaper.favourites")) do if item == path then return true end end
  return false
end
function M.toggle_favourite(path)
  local out, had = {}, false
  for _, item in ipairs(config.get("wallpaper.favourites")) do
    if item == path then had = true else out[#out + 1] = item end
  end
  if not had then out[#out + 1] = path end
  config.set("wallpaper.favourites", out)
  return not had
end

--- What paints the desk, as the page says it.
function M.painter_note()
  local painter = wallpaper.painter()
  if painter == "eva" then return "Eva paints the desktop: transitions, parallax and per-screen pictures work" end
  if painter == "tool" then return "Your wallpaper tool paints the desktop: changes arrive without a transition" end
  return "Nothing paints a picture yet: choose one below"
end

-- -------------------------------------------------------------- slideshow --

--- The folder the pictures come from.
function M.folder()
  local folder = config.get("wallpaper.slideshow.folder")
  if folder == "" then folder = config.get("lule.folder") end
  if folder == "" then folder = morf.env("LULE_W") or "" end
  if folder == "" then folder = wallpaper.current:get():match("^(.*)/") or (morf.fs.home() .. "/Pictures/Wallpapers") end
  return expand(folder)
end

--- The pictures the slideshow may show: paths, in name order.
function M.pictures()
  local files = studio().list(M.folder(), config.get("wallpaper.slideshow.recursive"))
  local out = {}
  local only = config.get("wallpaper.slideshow.favourites")
  for _, file in ipairs(files or {}) do
    if not only or M.favourite(file.path) then out[#out + 1] = file.path end
  end
  return out
end

--- `paths` shuffled so that none repeats until all have shown: takes the next
--- from `bag`, refilling it from `paths` without opening on `last`.
function M.draw(bag, paths, last, roll)
  roll = roll or math.random
  if #bag == 0 then
    for i, path in ipairs(paths) do bag[i] = path end
    for i = #bag, 2, -1 do
      local j = roll(i)
      bag[i], bag[j] = bag[j], bag[i]
    end
    if #bag > 1 and bag[#bag] == last then bag[1], bag[#bag] = bag[#bag], bag[1] end
  end
  return table.remove(bag)
end

local bag = {}

--- The picture `delta` steps from the current one, in the slideshow's order.
function M.neighbour(delta)
  local paths = M.pictures()
  if #paths == 0 then return nil end
  local current = wallpaper.current:get()
  if config.get("wallpaper.slideshow.order") == "shuffle" and delta > 0 then
    local present = {}
    for _, path in ipairs(paths) do present[path] = true end
    for i = #bag, 1, -1 do if not present[bag[i]] then table.remove(bag, i) end end
    return M.draw(bag, paths, current)
  end
  local index = 1
  for i, path in ipairs(paths) do if path == current then index = i break end end
  return paths[(index - 1 + delta) % #paths + 1]
end

-- A slide goes through Lule only when asked: colours take a run of its own.
local function slide(path)
  if not path then return false end
  if config.get("wallpaper.slideshow.colors") and M.can_color() then
    local s = studio()
    if s.select(path) then return s.apply() end
    return false
  end
  wallpaper.set(path)
  return true
end

function M.step(delta) return slide(M.neighbour(delta or 1)) end

--- A random picture of the folder.
function M.random()
  local paths = M.pictures()
  if #paths == 0 then return false end
  return slide(paths[math.random(#paths)])
end

-- The session's lock hint, which the lock sets, from logind. EVA_FAKE_LOCKED
-- stands in for it.
local login
local function locked()
  local fake = morf.env("EVA_FAKE_LOCKED")
  if fake and fake ~= "" then return fake == "1" end
  if login == nil then
    local ok, made = pcall(function() return require("lib.services.logind").connect() end)
    login = ok and made or false
  end
  return login and login.state.session.locked == true or false
end

--- Whether the slideshow is holding: something fullscreen here, or a lock.
function M.held()
  if not config.get("wallpaper.slideshow.pause") then return false end
  if locked() then return true end
  for _, window in ipairs(morf.toplevels and morf.toplevels.list() or {}) do
    if window.fullscreen then return true end
  end
  return false
end

--- Runs the slideshow from the screen that holds the shell's duties.
function M.start()
  local timer
  morf.effect("eva.wallpaper.slideshow", function()
    local on, interval = config.get("wallpaper.slideshow.on"), config.get("wallpaper.slideshow.interval")
    local primary = not morf.window.primary or morf.window.primary()
    if timer then timer:cancel() timer = nil end
    if not on or not primary then return end
    timer = morf.time.timer(math.max(5, interval) * 1000, function()
      if not M.held() then M.step(1) end
    end, true)
  end)
end

-- ------------------------------------------------------------------ hook --

--- Runs `wallpaper.hook` as the picture changes, from the primary screen.
function M.watch_hook()
  local last = wallpaper.current:get()
  morf.effect("eva.wallpaper.hook", function()
    local path = wallpaper.current:get()
    if path == last then return end
    last = path
    if morf.window.primary and not morf.window.primary() then return end
    local dry = morf.env("EVA_DRY_RUN")
    if dry and dry ~= "" and dry ~= "0" then return end
    local argv = {}
    for i, word in ipairs(config.get("wallpaper.hook")) do
      argv[i] = tostring(word):gsub("%$WALLPAPER", (path:gsub("%%", "%%%%"))):gsub("%$OUTPUT", wallpaper.output())
    end
    if #argv > 0 then pcall(morf.process.run, argv, { timeout_ms = 30000, max_output = 4096 }, function() end) end
  end)
end

-- ------------------------------------------------------------------- ipc --

--- `wallpaper [get]`, `set PATH [OUTPUT]`, `next`, `previous`, `random`,
--- `transition KIND`, `draw on|off`, `state`.
function M.verb(how, a, b)
  how = how or "get"
  if how == "get" then return wallpaper.picture() end
  if how == "state" then
    return { current = wallpaper.current:get(), picture = wallpaper.picture(), painter = wallpaper.painter(),
      output = wallpaper.output(), workspace = wallpaper.workspace(), slideshow = config.get("wallpaper.slideshow.on") }
  end
  if how == "set" then
    if not a then error("wallpaper set PATH [OUTPUT]") end
    if b then wallpaper.set_output(b, a) else wallpaper.set(a) end
    return true
  end
  if how == "next" then return M.step(1) end
  if how == "previous" then return M.step(-1) end
  if how == "random" then return M.random() end
  if how == "transition" then return config.set("wallpaper.transition.kind", a) end
  if how == "draw" then return config.set("wallpaper.draw", a == "on") end
  error("`" .. tostring(how) .. "`: get, set, next, previous, random, transition, draw or state")
end

return M
