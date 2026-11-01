-- What the launcher finds besides apps, after Raycast and Alfred: answers
-- inline as one types, a mode for each kind of thing, and fallbacks at the
-- bottom of every search.
--
--   (nothing)  everything at once (universal.lua), and inline: math "2^10", units
--              "10ft in m", percent "20% off 80", bases "255 in hex", currency
--              "100 usd in eur", an address, a time "time in tokyo"
--   =          the calculator alone
--   $          run a command (Tab: in a terminal, copy it)
--   / or ~     files and folders (Tab completes a path)
--   ?          search the web; a bang picks the engine: ?gh ?yt ?aur ?w ...
--   @          the open windows (Tab: their actions)
--   !          the system (lock, suspend, reboot...) and the shell's drawers
--   :          emoji, copied
--   ;          the clipboard's history, copied back
--   #          a colour, in every notation, copied
--   >          the shell's actions, and every mode by its word: "> timer 5m"
--
-- A mode with a word also answers as the first word of a plain search, beside
-- whatever else that search finds. The rest of the modes live in
-- launcher_modes/ and register themselves (lib/shell/launcher/registry.lua).
--
-- Every row is what lib/shell/launcher/rows.lua says.

local morf = require("morf")
local config = require("config")
local calc = require("calc")
local units = require("lib.shell.launcher.units")
local web = require("web")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")
local pins = require("lib.shell.launcher.pins")

local M = {}

local row, fuzzy, tilde = rows.row, rows.fuzzy, rows.tilde
local copy, browse = run.copy, run.browse

-- Asynchronous answers (files, currency rates) land here and re-run the
-- search.
M.revision = rows.revision
local bump = rows.bump
M.PREFIXES = registry.PREFIXES
M.route = registry.route
M.completing = registry.completing
M.mode_entry = registry.entry

local home = morf.fs.home()

-- ------------------------------------------------------------- inline math --

local function answer_row(question, value_text, material)
  return row {
    id = "answer", name = value_text, question = question,
    description = question .. "  ·  Return copies", material = material or "calculate",
    run = function() return copy(value_text:gsub(",", "")) end,
    actions = {
      { name = "Copy the answer", material = "content_copy", run = function() return copy(value_text:gsub(",", "")) end },
      { name = "Copy question and answer", material = "content_copy",
        run = function() return copy(question .. " = " .. value_text) end },
    },
  }
end

local function percent(q)
  local p, x = q:match("^%s*([%d%.]+)%s*%%%s+of%s+([%d%.]+)%s*$")
  if p then return tonumber(p) / 100 * tonumber(x) end
  p, x = q:match("^%s*([%d%.]+)%s*%%%s+off%s+([%d%.]+)%s*$")
  if p then return tonumber(x) * (1 - tonumber(p) / 100) end
  x, p = q:match("^%s*([%d%.]+)%s*%+%s*([%d%.]+)%s*%%%s*$")
  if x then return tonumber(x) * (1 + tonumber(p) / 100) end
  x, p = q:match("^%s*([%d%.]+)%s*%-%s*([%d%.]+)%s*%%%s*$")
  if x then return tonumber(x) * (1 - tonumber(p) / 100) end
  return nil
end

local BASES = { hex = 16, bin = 2, oct = 8, dec = 10, binary = 2, octal = 8, decimal = 10, hexadecimal = 16 }
local function in_base(q)
  local number, base = q:match("^%s*(%S+)%s+[it][no]%s+(%a+)%s*$")
  local to = base and BASES[base:lower()]
  if not to then return nil end
  local value = tonumber(number) or (number:match("^0b[01]+$") and tonumber(number:sub(3), 2))
    or (number:match("^0o[0-7]+$") and tonumber(number:sub(3), 8))
  if not value or value ~= math.floor(value) then return nil end
  value = math.floor(value)
  if to == 10 then return tostring(value) end
  if to == 16 then return ("0x%x"):format(value) end
  if to == 8 then return ("0o%o"):format(value) end
  local bits, v = {}, value
  if v == 0 then return "0b0" end
  while v > 0 do bits[#bits + 1] = tostring(v % 2) v = v // 2 end
  return "0b" .. table.concat(bits):reverse()
end

-- Currency: the European Central Bank's rates (frankfurter.dev, keyless),
-- fetched once a day and kept in the cache folder.
local rates, rates_asked
local function currency(q)
  local amount, from, to = q:upper():match("^%s*([%d%.]+)%s*(%a%a%a)%s+[IT][NO]%s+(%a%a%a)%s*$")
  if not amount then return nil end
  if not rates then
    if not rates_asked then
      rates_asked = true
      local file = morf.paths.cache("rates.json")
      local cached = file and select(2, pcall(morf.fs.read, file))
      local today = morf.time.format("%Y-%m-%d")
      local fine, data = pcall(morf.json.decode, type(cached) == "string" and cached or "")
      if fine and type(data) == "table" and data.fetched == today then
        rates = data.rates
      else
        morf.http.get("https://api.frankfurter.dev/v1/latest?base=EUR", { timeout_ms = 10000 }, function(r)
          local good, body = pcall(function() return r.ok and r.json() end)
          if good and type(body) == "table" and type(body.rates) == "table" then
            body.rates.EUR = 1
            rates = body.rates
            if file then pcall(morf.fs.write, file, morf.json.encode { fetched = today, rates = rates }) end
            bump()
          end
        end)
      end
    end
    if not rates then return "…", from, to end
  end
  local a, b = rates[from], rates[to]
  if not (a and b) then return nil end
  return tonumber(amount) / a * b, from, to
end

--- An answer for `q` if it is a sum, a conversion, a percentage, a base, a
--- currency or an address; nil otherwise.
function M.inline(q)
  if q:match("^%s*$") then return nil end
  local p = percent(q)
  if p then return answer_row(q, units.format(p)) end
  local based = in_base(q)
  if based then return answer_row(q, based, "tag") end
  local money, from, to = currency(q)
  if money == "…" then
    return row { id = "answer", name = "Fetching today's rates…", description = q, material = "currency_exchange",
      silent = true, run = function() return "keep" end }
  elseif money then
    return answer_row(q, units.format(money, 8) .. " " .. to, "currency_exchange")
  end
  local converted, unit = units.convert(q)
  if converted then return answer_row(q, units.format(converted) .. " " .. unit, "straighten") end
  local spoken = package.loaded["launcher_modes.dates"] and package.loaded["launcher_modes.dates"].answer(q)
  if spoken then return answer_row(q, spoken, "schedule") end
  -- A sum: something with an operator or a function in it, not a bare
  -- number or a word.
  if q:match("[%+%-%*/%^%%%(]") or q:match("%a+%s*%(") then
    local ok, value, shown, result = pcall(calc.evaluate, q)
    if ok and value then return answer_row(q, result or units.format(value)) end
  end
  if web.is_address(q) then
    return row { id = "address", name = q, description = "Open in the browser", material = "open_in_new",
      pin = "url:" .. web.address(q), run = function() return browse(web.address(q)) end,
      actions = { { name = "Copy the address", material = "content_copy", run = function() return copy(web.address(q)) end } } }
  end
  return nil
end

--- The rows at the foot of every search: the web, and files.
function M.fallbacks(q)
  if q:match("^%s*$") then return {} end
  local e = web.ENGINES[1]
  return {
    row { id = "fallback:web", name = "Search " .. e.name .. " for “" .. q .. "”", description = "?" .. e.bang .. " " .. q,
      material = "travel_explore", run = function() return browse(web.search_url(e, q)) end },
    row { id = "fallback:files", name = "Search files for “" .. q .. "”", description = "/" .. q, material = "folder_open",
      run = function() return "/" .. q end },
  }
end

-- --------------------------------------------------------------------- web --

local function websearch(rest)
  local bang, words = rest:match("^(%S+)%s+(.+)$")
  local engine = bang and web.engine(bang)
  if engine then
    return { row { id = "web:" .. engine.id, name = words, description = "Search " .. engine.name, material = "travel_explore",
      run = function() return browse(web.search_url(engine, words)) end,
      actions = { { name = "Copy the link", material = "content_copy", run = function() return copy(web.search_url(engine, words)) end } } } }
  end
  local out = {}
  if rest ~= "" then
    local e = web.ENGINES[1]
    local completes
    for _, engine_row in ipairs(web.engines()) do
      if engine_row.bang == rest then completes = engine_row break end
      if not completes and engine_row.bang:sub(1, #rest) == rest then completes = engine_row end
    end
    out[1] = row { id = "web", name = rest, description = "Search " .. e.name, material = "travel_explore",
      complete = completes and ("?" .. completes.bang .. " ") or nil,
      run = function() return browse(web.search_url(e, rest)) end }
  end
  for _, e in ipairs(web.engines()) do
    if rest == "" or e.bang:sub(1, #rest) == rest or e.name:lower():find(rest:lower(), 1, true) then
      out[#out + 1] = row { id = "engine:" .. e.id, name = e.name, description = "?" .. e.bang .. " …", material = "language",
        complete = "?" .. e.bang .. " ", run = function() return "?" .. e.bang .. " " end }
    end
  end
  return out
end

-- ------------------------------------------------------------------ system --

-- A second Return confirms what cannot be taken back.
local armed = nil
local function confirmed(id, action)
  return function()
    if armed == id then armed = nil return action() end
    armed = id
    bump()
    return "keep"
  end
end
M.confirmed = confirmed
function M.armed(id) return armed == id end

local function session(name)
  return function()
    local words = config.get("session.commands." .. name)
    if type(words) == "table" and #words > 0 then
      local user = (morf.env and morf.env("USER")) or ""
      local argv = {}
      for i, w in ipairs(words) do argv[i] = tostring(w):gsub("%$USER", user) end
      run.start(argv)
    end
    return "close"
  end
end

local function drawer(name, tab)
  return function()
    local d = require("drawer")[name]
    if tab and name == "sidebar" then require("sidebar").select(tab) end
    if tab and (name == "leftbar" or name == "bottom") then require(name).panel.select(tab) end
    if d then d.set(true) end
    return "close"
  end
end
M.open_drawer = drawer

local function system_entries()
  return {
    { id = "lock", name = "Lock the screen", material = "lock", run = function() run.start { "morf", "lock" } return "close" end },
    { id = "suspend", name = "Suspend", material = "bedtime", run = function() run.start { "systemctl", "suspend" } return "close" end },
    { id = "hibernate", name = "Hibernate", material = "downloading", run = confirmed("hibernate", session("hibernate")) },
    { id = "logout", name = "Log out", material = "logout", run = confirmed("logout", session("logout")) },
    { id = "reboot", name = "Restart", material = "restart_alt", run = confirmed("reboot", session("reboot")) },
    { id = "shutdown", name = "Power off", material = "power_settings_new", run = confirmed("shutdown", session("shutdown")) },
    { id = "dashboard", name = "Dashboard", material = "dashboard", run = drawer("dashboard") },
    { id = "settings", name = "Settings", material = "tune", run = drawer("sidebar", "settings") },
    { id = "notifications", name = "Notifications", material = "notifications", run = drawer("sidebar", "notifications") },
    { id = "capture", name = "Screenshot or record", material = "screenshot_monitor", run = drawer("capture") },
    { id = "assistant", name = "Assistant", material = "auto_awesome", run = drawer("bottom", "assistant") },
    { id = "tasks", name = "Tasks", material = "checklist", run = drawer("leftbar", "tasks") },
    { id = "calendar", name = "Calendar", material = "calendar_month", run = drawer("leftbar", "calendar") },
    { id = "screenshot", name = "Screenshot a region", material = "screenshot_region",
      run = function() require("capture").shoot("region") return "close" end },
    { id = "dnd", name = "Do not disturb", material = "notifications_off",
      run = function() local n = require("notifs") n.dnd:set(not n.dnd:get()) return "close" end },
    { id = "session", name = "Session menu", material = "power", run = drawer("session") },
  }
end

--- The system's rows, matching `term`.
function M.system_rows(term)
  local out = {}
  for _, s in ipairs(fuzzy(system_entries(), term)) do
    out[#out + 1] = row {
      id = "system:" .. s.id, name = s.name, material = s.material, run = s.run, tag = "System",
      pin = "system:" .. s.id, keywords = s.id,
      description = armed == s.id and "Press Return again to confirm" or ("!" .. s.id),
    }
  end
  return out
end

-- ------------------------------------------------------------------- emoji --

local function emoji(term)
  local out, seen = {}, {}
  local function add(e)
    if seen[e.char] then return end
    seen[e.char] = true
    out[#out + 1] = row {
      id = "emoji:" .. e.char, name = e.char .. "   " .. e.name, description = "Return copies it", material = nil,
      glyph = e.char, copy = e.char,
      run = function() return copy(e.char) end,
      actions = {
        { name = "Paste it", material = "content_paste_go", run = function()
          copy(e.char)
          run.paste()
          return "close"
        end },
        { name = "Copy its name", material = "content_copy", run = function() return copy(e.name) end },
      },
    }
  end
  if term == "" then
    local library = require("lib.shell.emoji")
    for _, pick in ipairs(require("apps").history.picks()) do
      local char = pick.id:match("^emoji:(.+)$")
      if char then add { char = char, name = pick.name:gsub("^%S+%s+", "") } end
      if #out >= 12 then break end
    end
    for _, e in ipairs(library.search(term, 60)) do add(e) end
    return out
  end
  for _, e in ipairs(require("lib.shell.emoji").search(term, 60)) do add(e) end
  return out
end

-- --------------------------------------------------------------- clipboard --

local KIND_WORDS = { img = "image", image = "image", images = "image", pic = "image", link = "link", links = "link",
  url = "link", mail = "email", email = "email", colour = "colour", color = "colour", path = "path", file = "path",
  text = "text" }
local KIND_ICONS = { image = "image", link = "link", email = "alternate_email", colour = "palette", path = "draft",
  text = "content_paste" }

local clipboard_ready = false
local function clipboard_store()
  local store = require("lib.shell.clipboard.store")
  if not clipboard_ready then
    clipboard_ready = true
    store.load()
    store.follow()
  end
  return store
end

local function ago(ms)
  if not ms then return "" end
  return require("lib.shell.launcher.dates").relative(ms // 1000)
end

local function clipboard(term)
  local store = clipboard_store()
  local items = store.items:get()
  local only
  local first, rest = term:match("^(%S+)%s*(.*)$")
  if first and KIND_WORDS[first:lower()] then only, term = KIND_WORDS[first:lower()], rest end
  if first == "pinned" or first == "pins" then only, term = "pinned", rest end
  local list = {}
  for i, item in ipairs(items) do
    local kind = store.kind_of(item)
    if not only or kind == only or (only == "pinned" and item.pinned) then
      local text = item.kind == "image" and "Picture" or (item.text or ""):gsub("%s+", " ")
      list[#list + 1] = { item = item, kind = kind, name = text:sub(1, 200), order = i,
        description = kind }
    end
  end
  local out = {}
  for _, c in ipairs(fuzzy(list, term)) do
    local item = c.item
    local id = item.id
    local actions = {
      { name = "Copy it back", material = "content_copy", run = function() store.copy(id) return "close" end },
      { name = "Paste it", material = "content_paste_go", run = function()
        store.copy(id)
        run.paste()
        return "close"
      end },
      { name = item.pinned and "Unpin it" or "Pin it", material = "keep",
        run = function() store.toggle_pin(id) bump() return "keep" end },
      { name = "Delete it", material = "delete", run = function() store.remove(id) bump() return "keep" end },
    }
    if item.kind == "image" then
      actions[#actions + 1] = { name = "Open the picture", material = "image", run = function() return run.open(item.path) end }
    else
      actions[#actions + 1] = { name = "Save as a snippet", material = "note_add", run = function()
        return "> snip add " .. item.text:gsub("%s+", " "):sub(1, 24):gsub(":", "") .. ": " .. item.text
      end }
      if c.kind == "link" then
        actions[#actions + 1] = { name = "Open the link", material = "open_in_new", run = function() return run.browse(item.text) end }
      elseif c.kind == "path" then
        actions[#actions + 1] = { name = "Open the file", material = "open_in_new",
          run = function() return run.open(rows.untilde(item.text)) end }
      end
    end
    actions[#actions + 1] = { name = "Delete the last 5 minutes", material = "history",
      run = function() store.forget_recent(5) bump() return "keep" end }
    actions[#actions + 1] = { name = "Clear everything unpinned", material = "delete_sweep",
      run = confirmed("clip-clear", function() store.clear() bump() return "keep" end) }
    out[#out + 1] = row {
      id = "clip:" .. id, name = c.name,
      description = (item.pinned and "Pinned  ·  " or "") .. c.kind .. "  ·  " .. ago(item.time),
      material = item.kind ~= "image" and (item.pinned and "keep" or KIND_ICONS[c.kind]) or nil,
      image = item.kind == "image" and item.path or nil, swatch = c.kind == "colour" and item.text or nil,
      preview = item.kind == "image" and { path = item.path } or { text = item.text, title = c.kind },
      copy = item.text,
      run = function() store.copy(id) return "close" end,
      actions = actions,
    }
  end
  if #out == 0 then
    out[1] = rows.note("clip", #items == 0 and "Nothing copied yet" or "Nothing like that in the history",
      "It comes from eva-clipboard", "content_paste_off")
  end
  return out
end

-- ------------------------------------------------------------------ colour --

-- Linear light from one sRGB channel.
local function linear(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end

local function oklch(r, g, b)
  local R, G, B = linear(r), linear(g), linear(b)
  local l = (0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B) ^ (1 / 3)
  local m = (0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B) ^ (1 / 3)
  local s = (0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B) ^ (1 / 3)
  local L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  local A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  local C = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  local hue = math.atan(C, A) * 180 / math.pi
  if hue < 0 then hue = hue + 360 end
  return L, math.sqrt(A * A + C * C), hue
end

local function colour(text)
  local ok, c = pcall(morf.color, text:match("^#") and text or ("#" .. text))
  if not ok or not c then ok, c = pcall(morf.color, text) end
  if not ok or not c then
    return { rows.note("colour", "Type a colour", "#7c3aed, rgb(1, 2, 3), hsl(...), a name", "palette") }
  end
  local r, g, b, a = c.r, c.g, c.b, c.a or 1
  local R, G, B = math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local l = (max + min) / 2
  local s, h = 0, 0
  if max ~= min then
    local d = max - min
    s = l > 0.5 and d / (2 - max - min) or d / (max + min)
    if max == r then h = (g - b) / d + (g < b and 6 or 0)
    elseif max == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h * 60
  end
  local hex = c:hex()
  local L, C, H = oklch(r, g, b)
  local forms = {
    { "HEX", hex },
    { "RGB", ("rgb(%d, %d, %d)"):format(R, G, B) },
    { "HSL", ("hsl(%d, %d%%, %d%%)"):format(math.floor(h + 0.5), math.floor(s * 100 + 0.5), math.floor(l * 100 + 0.5)) },
    { "OKLCH", ("oklch(%.3f %.3f %.1f)"):format(L, C, H) },
    { "RGBA", ("rgba(%d, %d, %d, %.2f)"):format(R, G, B, a) },
    { "Float", ("%.3f, %.3f, %.3f"):format(r, g, b) },
  }
  local out = {}
  for _, f in ipairs(forms) do
    out[#out + 1] = row { id = "colour:" .. f[1], name = f[2], description = f[1] .. "  ·  Return copies", swatch = hex,
      copy = f[2], run = function() return copy(f[2]) end }
  end
  return out
end

-- --------------------------------------------------------------- run a line --

local function needs_terminal(line) return line:match("^%s*sudo%s") ~= nil or line:match("^%s*doas%s") ~= nil end

local function command_rows(rest)
  if rest == "" then
    return { rows.note("run", "Type a command", "Return runs it; Tab: in a terminal", "terminal") }
  end
  local function run_it()
    if needs_terminal(rest) then return run.shell_terminal(rest) end
    run.start { "sh", "-c", rest }
    return "close"
  end
  local out = { row {
    id = "run", name = rest, description = needs_terminal(rest) and "Runs in a terminal  ·  Tab for more" or "Run it  ·  Tab for more",
    material = "terminal", pin = "cmd:" .. rest, copy = rest,
    run = run_it,
    actions = {
      { name = "Run it", material = "play_arrow", run = run_it },
      { name = "Run it in a terminal", material = "terminal", run = function() return run.shell_terminal(rest) end },
      { name = "Copy the command", material = "content_copy", run = function() return copy(rest) end },
    },
  } }
  local word = rest:match("^(%S+)$")
  if word then
    local programs = rows.ask_run("path", "all", { "sh", "-c", 'IFS=:; for d in $PATH; do ls "$d" 2>/dev/null; done | sort -u' },
      function(stdout)
        local list = {}
        for name in stdout:gmatch("[^\n]+") do list[#list + 1] = { name = name } end
        return list
      end, { debounce_ms = 0, ttl_ms = 300000 })
    local hits = 0
    for _, hit in ipairs(morf.text.fuzzy(word, programs or {}, { key = "name", limit = 8 })) do
      local name = hit.item.name
      if name ~= word then
        hits = hits + 1
        out[#out + 1] = row { id = "program:" .. name, name = name, description = "On your PATH", material = "terminal",
          complete = "$" .. name .. " ", pin = "cmd:" .. name, copy = name,
          run = function() run.start { name } return "close" end,
          actions = { { name = "Run it in a terminal", material = "terminal", run = function() return run.terminal { name } end } } }
      end
      if hits >= 6 then break end
    end
  end
  return out
end

-- ---------------------------------------------------------------- the modes --

registry.mode { id = "calculator", name = "Calculator", material = "calculate", shape = "diamond", prefix = "=",
  words = { "calculator", "maths" }, bare = false, hint = "2^10  ·  10ft in m  ·  20% off 80  ·  100 usd in eur",
  search = function(rest)
    if rest == "" then
      return { rows.note("calc", "Type a sum, a conversion or a percentage",
        "2^10  ·  10ft in m  ·  20% off 80  ·  100 usd in eur", "calculate") }
    end
    local answer = M.inline(rest)
    if answer then return { answer } end
    local symbolic = package.loaded["launcher_modes.system"] and package.loaded["launcher_modes.system"].qalc(rest)
    if symbolic then return { answer_row(rest, symbolic) } end
    return { rows.note("calc", rest, "Not a sum I can read", "calculate") }
  end }
registry.mode { id = "run", name = "Run", material = "terminal", shape = "square", prefix = "$", words = { "run" },
  bare = false, search = command_rows, hint = "a command, or a program from your PATH" }
registry.mode { id = "web", name = "Web", material = "travel_explore", shape = "soft_burst", prefix = "?", words = { "web", "search" },
  bare = false, search = websearch, hint = "?g words  ·  ?gh repo  ·  ?yt song" }
registry.mode { id = "system", name = "System", material = "settings_power", shape = "sunny", prefix = "!", words = { "system" },
  bare = false, search = M.system_rows, hint = "lock, suspend, restart, the shell's panels" }
registry.mode { id = "emoji", name = "Emoji", material = "mood", shape = "cookie9", prefix = ":", words = { "emoji" },
  bare = false, search = emoji, hint = "a name or an alias; the last ones first" }
registry.mode { id = "clipboard", name = "Clipboard", material = "content_paste", shape = "pill", prefix = ";",
  words = { "clipboard", "clips" }, bare = false, search = clipboard, hint = "; img  ·  ; link  ·  ; pinned" }
registry.mode { id = "colour", name = "Colour", material = "palette", shape = "sunny", prefix = "#", words = { "colour", "color" },
  bare = false, hint = "#7c3aed, rgb(1, 2, 3), a name",
  search = function(_, query) return colour(query) end }

for _, name in ipairs { "files", "windows", "tools", "dates", "system", "net", "time", "web", "text", "shell" } do
  require("launcher_modes." .. name)
end

-- ------------------------------------------------------------------ search --

local function max_results() return config.get("launcher.max_results") end

--- Rows for a query in a mode, and the view to draw them in; nil for a plain
--- query (the launcher's own search goes on).
function M.search(query)
  M.revision:get()
  local mode, rest = registry.route(query)
  if not mode then return nil end
  local found, view = mode.search(rest, query)
  found = found or {}
  for i, r in ipairs(found) do
    r.kind = r.kind or "menu"
    r.id = r.id or (mode.id .. ":" .. i)
    r.section = r.section or mode.name
  end
  found.cap = found.cap or max_results()
  return found, view or "apps"
end

--- The modes, as rows for the `>` list and for a plain search.
function M.mode_rows()
  local out = {}
  for _, mode in ipairs(registry.list()) do
    if not mode.hidden then
      local entry = registry.entry(mode)
      out[#out + 1] = row {
        id = "mode:" .. mode.id, name = mode.name, description = mode.hint or "", material = mode.material,
        keywords = table.concat(mode.words or {}, " "), tag = "Mode", complete = entry, pin = "mode:" .. mode.id,
        run = function() return entry end,
      }
    end
  end
  return out
end

--- The word a row can be pinned by, as a row again; nil when it is gone.
function M.resolve(name)
  local kind, rest = name:match("^(%a+):(.*)$")
  if not kind then return nil end
  if kind == "app" then return require("apps").row(rest) end
  if kind == "file" then
    if not morf.fs.exists(rest) then return nil end
    return rows.file(rest, morf.fs.is_dir(rest))
  end
  if kind == "mode" then
    for _, r in ipairs(M.mode_rows()) do
      if r.pin == name then return r end
    end
    return nil
  end
  if kind == "system" then
    for _, r in ipairs(M.system_rows("")) do
      if r.pin == name then return r end
    end
    return nil
  end
  if kind == "cmd" then return command_rows(rest)[1] end
  if kind == "url" then
    return row { id = name, name = rest, description = "Open in the browser", material = "open_in_new", pin = name,
      run = function() return browse(rest) end }
  end
  local entry = require("lib.shell.launcher.search_index").get(name)
  if entry then return require("universal").entry_row(entry) end
  return nil
end

--- The folder `path` is in, shown in a file manager that says it can, else
--- opened.
local function reveal(path)
  local parent = path:match("^(.*)/[^/]*$") or home
  if parent == "" then parent = "/" end
  if run.dry() then morf.log("info", "eva: launcher (dry run): reveal " .. path) return "close" end
  if not run.has("dbus-send") then return run.open(parent) end
  local uri = "file://" .. path:gsub("[^%w/%._%-~]", function(c) return ("%%%02X"):format(c:byte()) end)
  morf.process.run({ "dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.FileManager1",
    "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", "array:string:" .. uri, "string:" },
    { timeout_ms = 2000 }, function(result)
      if not (result and result.ok) then run.open(parent) end
    end)
  return "close"
end
M.reveal = reveal

--- Everything that can be done to `row`: its own actions, then what any row
--- of its kind offers.
function M.actions_for(target)
  if target.silent then return {} end
  local out = {}
  if target.kind == "app" then
    for _, a in ipairs(require("apps").actions_for(target)) do out[#out + 1] = a end
  end
  for _, a in ipairs(target.actions or {}) do out[#out + 1] = a end
  if target.preview then
    out[#out + 1] = { name = "Quick look", material = "preview",
      run = function() require("launcher").preview_open:set(true) return "keep" end }
  end
  if target.path then
    out[#out + 1] = { name = "Open containing folder", material = "folder_open", run = function() return reveal(target.path) end }
    out[#out + 1] = { name = "Copy the path", material = "content_copy", run = function() return copy(target.path) end }
  end
  if target.pin then
    local pinned = pins.pinned(target.pin)
    out[#out + 1] = { name = pinned and "Unpin from favourites" or "Pin to favourites", material = "keep",
      run = function() pins.toggle(target.pin) bump() return "keep" end }
  end
  local text = target.copy or target.name
  if type(text) == "string" and text ~= "" and not target.private then
    if target.kind ~= "app" then
      out[#out + 1] = { name = "Copy", material = "content_copy", run = function() return copy(text) end }
    end
    out[#out + 1] = { name = "Show in large type", material = "text_fields",
      run = function() require("launcher").large_type:set(text) return "keep" end }
  end
  if target.name and not target.private then
    out[#out + 1] = { name = "Give it an alias…", material = "label",
      run = function() return "> alias add " .. tostring(target.complete or target.name) end }
  end
  return out
end

--- The hint under the field: every prefix.
M.HINT = "apps  ·  = calc  ·  / files  ·  ? web  ·  @ windows  ·  ! system  ·  : emoji  ·  ; clipboard  ·  # colour  ·  $ run  ·  > shell"

return M
