-- eva-large's state: the words, where they came from, and their QR. No nodes.
local morf = require("morf")
local qr = require("lib.util.qr")
local sys = require("common.sys")

local M = {
  text = morf.signal("large.text", ""),
  from = morf.signal("large.from", ""),
  qr = morf.signal("large.qr", ""),
  leaving = morf.signal("large.leaving", false),
}

-- The most characters shown, and the most a QR is made of.
M.LIMIT = 4000
M.QR_LIMIT = 1200
-- How long it takes to go.
M.GONE = 300

local function trim(words) return (tostring(words or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- The theme's dark end and its light end, for the modules and the ground.
local function qr_colours()
  local C = require("theme").color
  local light, dark = C.onSurface, C.surface
  if C.surface:is_light() then light, dark = C.surface, C.onSurface end
  return dark:hex():sub(1, 7), light:hex():sub(1, 7)
end

local function make_qr(words)
  if #words > M.QR_LIMIT then return end
  qr.encode(words, "M", function(code)
    if code then M.qr:set(qr.svg(code, qr_colours())) end
  end)
end

--- Shows `words`, told where they came from.
function M.show(words, from)
  words = trim(words)
  if utf8.len(words) and utf8.len(words) > M.LIMIT then words = words:sub(1, utf8.offset(words, M.LIMIT + 1) - 1) end
  M.text:set(words)
  M.from:set(from)
  if words ~= "" then make_qr(words) end
end

--- Takes the words from the arguments, else the cli's file, else the clipboard.
function M.load()
  local words = table.concat(morf.operands or {}, " ")
  if trim(words) ~= "" then return M.show(words, "arguments") end
  local file = morf.env("EVA_LARGE_FILE")
  if file and file ~= "" then
    local ok, text = pcall(morf.fs.read, file)
    pcall(morf.fs.remove, file)
    if ok and trim(text) ~= "" then return M.show(text, "stdin") end
  end
  sys.run({ "wl-paste", "--no-newline", "--type", "text" }, { read = true, max_output = 4 * M.LIMIT }, function(result)
    M.show(result.ok and result.stdout or "", "clipboard")
  end)
end

--- Springs away and ends.
function M.finish()
  if M.leaving:get() then return end
  M.leaving:set(true)
  morf.time.timer(M.GONE, function() morf.quit() end, false)
end

return M
