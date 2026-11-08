-- The Pattern page's state: what patty holds for this account, and a new
-- pattern entered twice and handed to `pkexec patty set` on its stdin, or
-- `pkexec patty clear`. The entries stay locals; signals carry only counts.
local morf = require("morf")
local host = require("lib.services.host")
local patty = require("lib.shell.auth.patty")

local M = {
  state = morf.signal("eva.pattern.state", { installed = false, kind = "", used = 0, left = patty.TRIES, locked = 0, until_at = 0 }),
  step = morf.signal("eva.pattern.step", "first"),
  typed = morf.signal("eva.pattern.typed", 0),
  busy = morf.signal("eva.pattern.busy", false),
  said = morf.signal("eva.pattern.said", { text = "", bad = false }),
  trace = require("models.pattern_trace").new("eva.pattern"),
}

local first, typing = nil, ""

function M.user()
  local me = require("lib.services.accounts").me()
  return me and me.name or ""
end

--- patty's full path (EVA_PATTY names one), or nil where it is not installed.
function M.program()
  local named = morf.env("EVA_PATTY")
  if named and named ~= "" then return named end
  if host.fake() then return host.installed("patty") and "patty" or nil end
  for dir in ((morf.env("PATH") or "") .. ":/run/current-system/sw/bin:/usr/bin:/usr/local/bin"):gmatch("[^:]+") do
    if morf.fs.exists(dir .. "/patty") then return dir .. "/patty" end
  end
  return nil
end

function M.refresh()
  local user = M.user()
  local fails = patty.fails(user)
  local standing = patty.standing(fails, morf.time.now())
  M.state:set { installed = M.program() ~= nil, kind = patty.kind(user) or "", used = standing.used,
    left = standing.left, locked = standing.locked, until_at = fails and fails.until_at or 0 }
end

local function say(text, bad) M.said:set { text = text or "", bad = bad == true } end

--- Back to the first entry, both forgotten.
function M.reset()
  first, typing = nil, ""
  M.typed:set(0)
  M.trace.clear()
  M.step:set("first")
end

local function save(second)
  local program, given = M.program(), first
  M.reset()
  if not program then say("patty is not installed on this machine", true) return end
  M.busy:set(true)
  say("Asking for permission…")
  local argv = { morf.env("EVA_PKEXEC") or "pkexec", program, "set", M.user() }
  host.act(argv, function(out, why)
    M.busy:set(false)
    M.refresh()
    if out then
      say(("Saved. The screens show a %s"):format(patty.kind_of(given)))
    else
      say(M.why(why), true)
    end
    given = nil
  end, { stdin = given .. "\n" .. second .. "\n", timeout_ms = 120000, max_output = 4096 })
end

--- One entry, drawn or typed: the first, then the same again.
function M.enter(digits)
  M.trace.clear()
  typing = ""
  M.typed:set(0)
  if M.busy:get() then return end
  if not patty.valid(digits) then
    say(#digits < patty.MIN and "At least 4 digits, or 4 dots" or "At most 16 digits", true)
    return
  end
  if not first then
    first = digits
    M.step:set("again")
    say(patty.drawable(digits) and "A grid pattern. Once more to be sure" or "A keypad pattern. Once more to be sure")
  elseif digits ~= first then
    M.reset()
    say("The two differ. Start again", true)
  else
    save(digits)
  end
end

--- What the digits field holds now; Enter takes it.
function M.typing(text)
  typing = tostring(text or ""):gsub("%D", ""):sub(1, patty.MAX)
  M.typed:set(#typing)
  if #typing > 0 then M.trace.clear() end
end
function M.accept() M.enter(typing) end
--- A stroke begins: what was said goes.
function M.started() say("") end

function M.clear()
  local program = M.program()
  if not program or M.busy:get() then return end
  M.reset()
  M.busy:set(true)
  say("Asking for permission…")
  host.act({ morf.env("EVA_PKEXEC") or "pkexec", program, "clear", M.user() }, function(out, why)
    M.busy:set(false)
    M.refresh()
    if out then say("Cleared. Only the password opens the screens") else say(M.why(why), true) end
  end, { timeout_ms = 120000, max_output = 4096 })
end

--- What a failed `pkexec patty` says, in words.
function M.why(why)
  why = tostring(why or "")
  if why == "126" or why:find("dismissed", 1, true) then return "Not changed: permission was not given" end
  if why == "127" or why:find("Not authorized", 1, true) then return "Not changed: not allowed here" end
  local said = why:match("patty:%s*(.-)%s*$")
  return said and said ~= "" and ("Not changed: " .. said) or ("Not changed: " .. why)
end

return M
