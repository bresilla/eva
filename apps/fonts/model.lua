-- eva-fonts' state: the families of themes/fonts.lua, what a preview of one needs
-- on top of them, and the shell's font set the way the shell's own picker sets
-- it. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local themes = require("themes")
local fonts = require("themes.fonts")

local M = {
  chosen = morf.signal("fonts.chosen", ""),
  sample = morf.signal("fonts.sample", ""),
  size = morf.signal("fonts.size", 3),
  weight = morf.signal("fonts.weight", 400),
  weights = morf.signal("fonts.weights", {}),
  mono_only = morf.signal("fonts.mono-only", false),
  mono = morf.signal("fonts.mono", {}),
  message = morf.signal("fonts.message", ""),
  families = fonts.rows,
  status = fonts.status,
}

M.SIZES = { 12, 16, 24, 36, 48, 72 }
M.WEIGHTS = { 100, 200, 300, 400, 500, 600, 700, 800, 900 }
M.SAMPLES = {
  { name = "Words", text = "The quick brown fox jumps over the lazy dog" },
  { name = "Digits", text = "0123456789 (){}[] 1Il| O0 $€£ +-*/=" },
  { name = "Code", text = "fn main() { let x = a != b && c >= 0; }" },
}
M.ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789"

-- fontconfig's weights, with the CSS weight each is.
local FC_WEIGHTS = { { 0, 100 }, { 40, 200 }, { 50, 300 }, { 55, 300 }, { 75, 400 }, { 80, 400 }, { 100, 500 },
  { 180, 600 }, { 200, 700 }, { 205, 800 }, { 210, 900 }, { 215, 900 } }

M.sample:set(M.SAMPLES[1].text)

local kept = morf.reloadable("eva.fonts.kept", {})

--- The family and news kept across the reload a change of font brings.
function M.restore()
  local held = kept:get()
  if held.message then M.message:set(held.message) end
  if held.chosen then M.choose(held.chosen) end
end

local function say(words)
  M.message:set(words)
  kept:set { chosen = M.chosen:get(), message = words }
end

--- The family as a fontconfig pattern takes it.
function M.pattern(family)
  return ":family=" .. family:gsub("[\\:,%-]", "\\%0")
end

--- The CSS weights `lines` of fontconfig's "%{weight}" name, in order; a line
--- may be a range, a variable font's.
function M.parse_weights(lines)
  local found = {}
  for line in tostring(lines or ""):gmatch("[^\r\n]+") do
    local low, high = line:match("^%[?(%d+%.?%d*)%s*(%d*%.?%d*)%]?")
    low = tonumber(low)
    if low then
      high = tonumber(high) or low
      for _, pair in ipairs(FC_WEIGHTS) do
        if pair[1] >= low and pair[1] <= high then found[pair[2]] = true end
      end
    end
  end
  local out = {}
  for _, weight in ipairs(M.WEIGHTS) do
    if found[weight] then out[#out + 1] = weight end
  end
  return out
end

--- The families in sight: themes/fonts.lua's, held to the monospace ones when
--- that filter is on. A tracked read.
function M.shown()
  local rows = fonts.rows:get()
  if not M.mono_only:get() then return rows end
  local mono, out = M.mono:get(), {}
  for _, family in ipairs(rows) do
    if mono[family] then out[#out + 1] = family end
  end
  return out
end

--- Lists the families; `done()` once they are there.
function M.load(done)
  fonts.open()
  if not done then return end
  local heard = false
  morf.effect("fonts.load", function()
    local there = #fonts.rows:get() > 0 or fonts.status:get():find("Could not", 1, true)
    if there and not heard then
      heard = true
      morf.time.timer(1, done, false)
    end
  end)
end

function M.search(query) fonts.filter(query) end

local read_mono = false

--- The monospace filter on or off: `done()` once the set is known.
function M.set_mono(on, done)
  M.mono_only:set(on)
  if not on or read_mono then
    if done then done() end
    return
  end
  read_mono = true
  sys.run({ "fc-list", ":spacing=mono", "--format", "%{family[0]}\n" }, { read = true, timeout_ms = 5000 }, function(result)
    local set = {}
    for family in (result.stdout or ""):gmatch("[^\r\n]+") do set[family:match("^%s*(.-)%s*$")] = true end
    M.mono:set(set)
    if done then done() end
  end)
end

--- Previews `family`, with the weights it comes in.
function M.choose(family)
  if type(family) ~= "string" or family == "" then return end
  M.chosen:set(family)
  kept:set { chosen = family, message = M.message:get() }
  sys.run({ "fc-list", M.pattern(family), "--format", "%{weight}\n" }, { read = true, timeout_ms = 5000 }, function(result)
    if M.chosen:get() ~= family then return end
    local weights = M.parse_weights(result.stdout)
    M.weights:set(weights)
    local held = M.weight:get()
    for _, weight in ipairs(weights) do
      if weight == held then return end
    end
    M.weight:set(weights[1] and (weights[#weights] >= 400 and M.nearest(weights) or weights[1]) or 400)
  end)
end

--- The weight of `weights` nearest regular.
function M.nearest(weights)
  local best = weights[1]
  for _, weight in ipairs(weights) do
    if math.abs(weight - 400) < math.abs(best - 400) then best = weight end
  end
  return best
end

function M.has_weight(weight)
  for _, have in ipairs(M.weights:get()) do
    if have == weight then return true end
  end
  return false
end

-- A family the shell's verb can carry.
local function fit(family)
  return type(family) == "string" and #family <= 200 and not family:find("%c")
end

--- The shell's font, "" for the theme's own: the running shell's where one
--- answers, else the file it starts from.
function M.current(done)
  sys.shell({ "appearance", "state" }, { read = true }, function(reply)
    local ok, state = pcall(morf.json.decode, type(reply) == "table" and reply[1] or "")
    if ok and type(state) == "table" then done(state.font or "", true) return end
    done(themes.preferences.get("font") or "", false)
  end)
end

--- Sets the shell's font, "" for the theme's own. With the shell up its
--- `appearance font:NAME` verb covers the panels and reloads, and the shell
--- writes the file; with it down the file is written here, for its next start.
--- `done(ok, words)`.
function M.apply(family, done)
  local function finish(ok, words)
    say(words)
    if done then done(ok, words) end
  end
  if not fit(family) then finish(false, "That is not a family's name") return end
  local name = family ~= "" and family or "the theme's own font"
  M.current(function(font, up)
    if not up then
      if sys.dry() then finish(true, "Would save " .. name) return end
      themes.preferences.set("font", family)
      themes.preferences.flush()
      finish(true, "Saved " .. name .. ": the shell takes it when it starts")
      return
    end
    if font == family then finish(true, "The shell already uses " .. name) return end
    sys.shell({ "appearance", "font:" .. family }, nil, function(reply, why)
      if type(reply) == "table" and reply[1] == true then
        finish(true, "The shell is changing to " .. name)
      elseif why == "dry run" then
        finish(true, "Would ask the shell for " .. name)
      else
        -- A refusal: the reason is in the shell's state.
        sys.shell({ "appearance", "state" }, { read = true }, function(state)
          local ok, seen = pcall(morf.json.decode, type(state) == "table" and state[1] or "")
          local reason = ok and type(seen) == "table" and seen.message or ""
          finish(false, reason ~= "" and reason or "The shell did not take it")
        end)
      end
    end)
  end)
end

-- Whether `family` is installed, the same test themes/fonts.lua makes.
local function installed(family)
  for _, have in ipairs(fonts.rows:get()) do
    if have == family then return true end
  end
  return false
end

--- Sets the shell's font to a family this machine has, by the command line.
function M.apply_installed(family, done)
  if family ~= "" and not installed(family) then
    done(false, "No family called " .. family)
    return
  end
  M.apply(family, done)
end

--- `eva-fonts`'s command: `done(text, why)`.
function M.job(args, done)
  local how = args[1]
  local function answer(ok, words)
    if ok then done(words) else done(nil, words) end
  end
  if how == "current" then
    M.current(function(font) done(font ~= "" and font or "the theme's own font") end)
  elseif how == "reset" then
    M.apply("", answer)
  elseif how == "list" then
    M.load(function()
      M.set_mono(args[2] == "--mono", function()
        local shown = M.shown()
        if #shown == 0 then done(nil, "No fonts to list") return end
        done(table.concat(shown, "\n"))
      end)
    end)
  elseif how == "set" then
    local words = {}
    for index = 2, #args do words[#words + 1] = args[index] end
    M.load(function() M.apply_installed(table.concat(words, " "), answer) end)
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

return M
