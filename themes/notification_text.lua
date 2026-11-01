-- Presentation helpers shared by notification views.
local morf = require("morf")
local M = {}
function M.plain(value)
  return (tostring(value or ""):gsub("<[^>]->", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end

--- A sender's body for a Text's `markup`: the spec's tags, less its pictures,
--- which a card draws apart. Unknown tags fall away in the engine.
function M.markup(value)
  return (tostring(value or ""):gsub("<%s*[iI][mM][gG][^>]*>", ""))
end

local SAFE_LINK = { http = true, https = true, mailto = true }
--- Whether `href` may be opened: the web and mail, nothing on this machine.
function M.safe_link(href)
  local scheme = tostring(href or ""):match("^(%a[%w+.-]*):")
  return scheme ~= nil and SAFE_LINK[scheme:lower()] == true
end

--- Hands a safe link to the desktop; dry, it logs.
function M.open_link(href)
  if not M.safe_link(href) then
    morf.log("info", "eva: refused a notification link")
    return false
  end
  local dry = morf.env and morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then
    morf.log("info", "eva: open link (dry run): " .. href)
    return true
  end
  morf.process.run({ "xdg-open", href }, {}, function() end)
  return true
end

local function local_picture(src)
  src = tostring(src or "")
  if src:sub(1, 1) == "/" or src:match("^file://") then return src end
end

--- The picture a notification carries: raw pixels, a path, a picture in its
--- body. "" for none.
function M.image_of(x)
  if not x then return "" end
  if x.image_source and x.image_source ~= "" then return x.image_source end
  if x.image and x.image ~= "" then return x.image end
  local src = tostring(x.body or ""):match("<%s*[iI][mM][gG][^>]-[sS][rR][cC]%s*=%s*[\"']([^\"']+)[\"']")
  return local_picture(src) or ""
end

local CODE_WORDS = { "code", "otp", "passcode", "pin", "verification", "verify", "2fa", "one-time", "token",
  "security", "login", "sign-in" }
--- The one-time code in a notification, or nil.
function M.otp(x)
  if not x then return nil end
  local text = M.plain(tostring(x.summary or "") .. " " .. tostring(x.body or ""))
  local lower, wanted = text:lower(), false
  for _, word in ipairs(CODE_WORDS) do wanted = wanted or lower:find(word, 1, true) ~= nil end
  if not wanted then return nil end
  local a, b = text:match("%f[%w](%d%d%d)[%- ](%d%d%d)%f[%W]")
  if a then return a .. b end
  for digits in text:gmatch("%f[%w](%d%d%d%d%d?%d?%d?%d?)%f[%W]") do
    local year = #digits == 4 and tonumber(digits) >= 1900 and tonumber(digits) <= 2100
    if not year then return digits end
  end
  return text:match("%f[%w](%u%-%d%d%d%d+)%f[%W]")
end

--- The first web link in a notification, or nil.
function M.link(x)
  if not x then return nil end
  local body = tostring(x.body or "")
  local href = body:match("<%s*[aA][^>]-[hH][rR][eE][fF]%s*=%s*[\"']([^\"']+)[\"']")
  if href and M.safe_link(href) then return href end
  local url = M.plain(body):match("https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+")
  return url and (url:gsub("[%.,;:!%?%)]+$", "")) or nil
end

local TRANSPORT = {
  { "previous", "skip_previous", { "media-skip-backward", "media-previous", "media-seek-backward", "previous", "prev" } },
  { "play", "play_arrow", { "media-playback-start", "play", "media-play" } },
  { "pause", "pause", { "media-playback-pause", "pause", "media-pause" } },
  { "toggle", "play_pause", { "media-playback-toggle", "playpause", "play-pause", "play_pause", "toggle" } },
  { "next", "skip_next", { "media-skip-forward", "media-next", "media-seek-forward", "next" } },
  { "stop", "stop", { "media-playback-stop", "stop" } },
}
local TRANSPORT_OF = {}
for _, row in ipairs(TRANSPORT) do
  for _, key in ipairs(row[3]) do TRANSPORT_OF[key] = row end
end

--- A media card's controls, from the actions its sender offers.
function M.transport(x)
  local out = {}
  for _, action in ipairs(x and x.actions or {}) do
    local row = TRANSPORT_OF[tostring(action.key):lower()]
    if row then out[#out + 1] = { key = action.key, icon = row[2], name = action.label ~= "" and action.label or row[1] } end
  end
  return out
end

--- The buttons a card draws: everything but the body's own click and the media
--- controls. `inline-reply` is the Reply button.
function M.buttons(x)
  local out = {}
  if not x or x.no_buttons then return out end
  for _, action in ipairs(x.actions or {}) do
    local key = tostring(action.key)
    if key == "inline-reply" then
      out[#out + 1] = { key = key, label = (action.label ~= "" and action.label) or "Reply", reply = true }
    elseif key ~= "default" and not TRANSPORT_OF[key:lower()] and (action.label or "") ~= "" then
      out[#out + 1] = { key = key, label = action.label }
    end
  end
  return out
end

--- What the reply field asks for.
function M.reply_prompt(x)
  local hints = x and x.hints or {}
  local hint = hints["x-kde-reply-placeholder-text"]
  if type(hint) == "string" and hint ~= "" then return hint end
  return "Reply"
end

--- The rich face a card takes: "call", "media", "progress", "message", "image"
--- or "plain".
function M.style(x)
  if not x then return "plain" end
  local category = tostring(x.category or "")
  if category:match("^call") then return "call" end
  if #M.transport(x) > 0 or category:match("music") or category:match("^x%-gnome%.music") then return "media" end
  if M.progress(x) then return "progress" end
  if category:match("^im") then return "message" end
  if M.image_of(x) ~= "" then return "image" end
  return "plain"
end

--- A length of time, short.
function M.span(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  if seconds < 60 then return ("%d s"):format(seconds) end
  if seconds < 3600 then return ("%d min"):format(seconds // 60) end
  return ("%d h %d min"):format(seconds // 3600, seconds % 3600 // 60)
end

--- A job's line: how far it is, and how long is left where that is known.
function M.progress_line(x)
  local v = M.progress(x) or 0
  local line = ("%d%% done · %d%% left"):format(math.floor(v * 100 + .5), math.floor((1 - v) * 100 + .5))
  if x and x.eta and x.eta > 0 then return ("%d%% done · %s left"):format(math.floor(v * 100 + .5), M.span(x.eta)) end
  return line
end
function M.ago(time)
  morf.time.minute_clock:get()
  local seconds = math.max(0, morf.time.now() - (time or 0))
  if seconds < 60 then return "now" end
  if seconds < 3600 then return ("%dm"):format(seconds // 60) end
  if seconds < 86400 then return ("%dh"):format(seconds // 3600) end
  return ("%dd"):format(seconds // 86400)
end

-- What a notification reads as, for the status cards: critical is an
-- alert, trouble a warning, success ok, anything else info.
local function has(text, words)
  for _, w in ipairs(words) do
    if text:find("%f[%a]" .. w) then return true end
  end
  return false
end
function M.kind(x)
  if not x then return "info" end
  if (x.urgency or 1) >= 2 then return "alert" end
  local text = (tostring(x.summary or "") .. " " .. tostring(x.body or "")):lower()
  if has(text, { "fail", "error", "warn", "low", "denied", "lost", "disconnect", "unable", "cannot", "crash" }) then
    return "warn"
  end
  if (x.urgency or 1) == 0 or has(text, { "complete", "done", "success", "finish", "saved", "connected",
    "ready", "installed", "updated", "copied", "sent", "passed" }) then
    return "ok"
  end
  return "info"
end
--- A notification's progress (0..1) when its sender gave one (`value`).
function M.progress(x)
  local hints = x and x.hints
  local v = type(hints) == "table" and tonumber(hints.value) or nil
  if not v then return nil end
  return math.max(0, math.min(1, v / 100))
end
-- The plain words for each kind: a theme may say them its own way through
-- L.term ("notice.<kind>", "notice.verdict.<kind>").
M.WORDS = { alert = "Urgent", warn = "Warning", ok = "Done", info = "Info" }
M.VERDICT = {
  alert = "Needs your attention",
  warn = "Worth a look",
  ok = "Nothing to do",
  info = "For your information",
}
--- The kind's word and verdict in the theme's voice.
function M.word(kind)
  local L = require("themes.layouts.parts")
  return L.term("notice." .. kind, M.WORDS[kind])
end
function M.verdict(kind)
  local L = require("themes.layouts.parts")
  return L.term("notice.verdict." .. kind, M.VERDICT[kind])
end
return M
