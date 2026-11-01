-- The launcher's plain tools: QR codes, passwords, encodings, dates, ssh hosts,
-- recent files.
--
--     morf test --no-dbus tests/launcher_tools_spec.lua

local test = morf.test

local HOST = [==[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local qr = require("lib.shell.launcher.qr")
  local password = require("lib.shell.launcher.password")
  local codec = require("lib.shell.launcher.codec")
  local dates = require("lib.shell.launcher.dates")
  local ssh = require("lib.shell.launcher.sshconfig")
  local recent = require("lib.shell.launcher.recent")
  morf.ipc.qr_size = function(text)
    local code, why = qr.encode(text)
    if not code then return why end
    return code.size .. "/" .. code.level
  end
  morf.ipc.qr_finder = function(text)
    local code = qr.encode(text)
    local row = {}
    for x = 0, 6 do row[#row + 1] = code.dark(x, 0) and "1" or "0" end
    return table.concat(row)
  end
  local code
  morf.ipc.qr_encode = function(text) code = qr.encode(text) return code ~= nil end
  morf.ipc.qr_pgm = function(path)
    local scale, quiet = 4, 4
    local side = (code.size + 2 * quiet) * scale
    local white = string.rep("\255", side)
    local lines = {}
    for _ = 1, quiet * scale do lines[#lines + 1] = white end
    for y = 0, code.size - 1 do
      local cells = { string.rep("\255", quiet * scale) }
      for x = 0, code.size - 1 do cells[#cells + 1] = string.rep(code.dark(x, y) and "\0" or "\255", scale) end
      cells[#cells + 1] = string.rep("\255", quiet * scale)
      local line = table.concat(cells)
      for _ = 1, scale do lines[#lines + 1] = line end
    end
    for _ = 1, quiet * scale do lines[#lines + 1] = white end
    morf.fs.write(path, ("P5\n%d %d\n255\n"):format(side, side) .. table.concat(lines))
    return true
  end
  morf.ipc.has_zbar = function() return require("lib.shell.launcher.run").has("zbarimg") end
  local read
  morf.ipc.zbar = function(path)
    read = nil
    morf.process.run({ "zbarimg", "-q", "--raw", "-Sbinary", path }, {}, function(result)
      read = (result.stdout or ""):gsub("\n$", "")
    end)
    return true
  end
  morf.ipc.zbar_read = function() return read end
  morf.ipc.password = function(length)
    local a = password.generate(tonumber(length))
    return a, password.generate(tonumber(length))
  end
  morf.ipc.password_kinds = function(length, plain)
    local p = password.generate(tonumber(length), plain == "plain" and { symbols = false, digits = false } or nil)
    return { lower = p:find("%l") ~= nil, upper = p:find("%u") ~= nil, digit = p:find("%d") ~= nil,
      symbol = p:find("%p") ~= nil, length = #p }
  end
  morf.ipc.spread = function()
    local seen = {}
    for _ = 1, 4000 do local n = password.pick(10) seen[n] = (seen[n] or 0) + 1 end
    local low, high = math.huge, 0
    for i = 1, 10 do low, high = math.min(low, seen[i] or 0), math.max(high, seen[i] or 0) end
    return { low = low, high = high }
  end
  morf.ipc.passphrase = function(n) return password.passphrase(tonumber(n)) end
  morf.ipc.bits = function(n, size) return password.bits(tonumber(n), tonumber(size)) end
  morf.ipc.md5 = function(text) return codec.md5(text) end
  morf.ipc.hex = function(text) return codec.hex_encode(text), codec.hex_decode(codec.hex_encode(text)) end
  morf.ipc.html = function(text) return codec.html_encode(text), codec.html_decode(codec.html_encode(text)) end
  morf.ipc.rot13 = function(text) return codec.rot13(text) end
  morf.ipc.cases = function(text)
    local out = {}
    for _, c in ipairs(codec.cases(text)) do out[c[1]] = c[2] end
    return out
  end
  morf.ipc.jwt = function(token) return codec.jwt(token) end
  morf.ipc.json = function(text) return codec.json(text) end
  morf.ipc.points = function(text) return codec.code_points(text) end
  morf.ipc.duration = function(text) local s, rest = dates.duration(text) return s, rest end
  morf.ipc.span = function(n) return dates.span(tonumber(n)) end
  morf.ipc.clock = function(text) local h, m, rest = dates.clock(text) return h, m, rest end
  morf.ipc.zone = function(name) return dates.zone(name) end
  morf.ipc.parse = function(text, now)
    return dates.parse(text, tonumber(now))
  end
  morf.ipc.format = function(t, zone) return morf.time.format("%Y-%m-%d %H:%M", tonumber(t), zone and { tz = zone } or nil) end
  morf.ipc.relative = function(t, now) return dates.relative(tonumber(t), tonumber(now)) end
  morf.ipc.days = function(now, t) return dates.days_between(tonumber(now), tonumber(t)) end
  morf.ipc.ssh = function(path) return ssh.hosts(path) end
  morf.ipc.known = function(text) return ssh.known(text) end
  morf.ipc.recent = function(text, limit) return recent.parse(text, tonumber(limit)) end
]==]

local function load() test.load { source = HOST } end

test.describe("qr", function()
  test.it("picks the smallest code that holds the text, and says when none will", function()
    load()
    test.eq(test.ipc("qr_size", "HELLO"), "21/M")
    test.eq(test.ipc("qr_size", string.rep("a", 100)), "41/M")
    test.eq(test.ipc("qr_size", string.rep("a", 400)), "77/M")
    test.matches(test.ipc("qr_size", string.rep("a", 401)), "too long")
    test.matches(test.ipc("qr_size", ""), "nothing")
  end)
  test.it("draws the finder pattern", function()
    load()
    test.eq(test.ipc("qr_finder", "HELLO"), "1111111")
  end)
  -- A code proves itself by being read: zbarimg decodes what was encoded.
  test.it("reads back through a real decoder", function()
    load()
    local has = test.ipc("has_zbar")
    if not has then test.note("no zbarimg here: nothing read the code back") return end
    for i, text in ipairs {
      "HELLO", "https://example.org/a/path?with=query&and=more", "héllo wörld, ünicode ✓",
      string.rep("0123456789", 12), string.rep("The launcher makes this. ", 16),
    } do
      local path = morf.env("XDG_STATE_HOME") .. "/qr" .. i .. ".pgm"
      test.truthy(test.ipc("qr_encode", text))
      test.ipc("qr_pgm", path)
      test.ipc("zbar", path)
      local read = test.wait(function() return test.ipc("zbar_read") end, 5000, "zbarimg did not answer")
      test.eq(read, text)
    end
  end)
end)

test.describe("passwords", function()
  test.it("gives a different password each time, of the length asked", function()
    load()
    local a, b = test.ipc("password", "24")
    test.eq(#a, 24)
    test.ne(a, b)
  end)
  test.it("holds one of each kind of character it may", function()
    load()
    for _ = 1, 30 do
      local kinds = test.ipc("password_kinds", "8")
      test.truthy(kinds.lower and kinds.upper and kinds.digit and kinds.symbol)
    end
    local plain = test.ipc("password_kinds", "16", "plain")
    test.falsy(plain.digit or plain.symbol)
  end)
  test.it("favours no value", function()
    load()
    local spread = test.ipc("spread")
    test.truthy(spread.low > 300 and spread.high < 500, "picks skewed")
  end)
  test.it("gives passphrases and a count of bits", function()
    load()
    local _, dashes = test.ipc("passphrase", "6"):gsub("-", "")
    test.eq(dashes, 5)
    test.eq(test.ipc("bits", "16", "64"), 96)
  end)
end)

test.describe("codec", function()
  test.it("digests as md5sum does", function()
    load()
    test.eq(test.ipc("md5", ""), "d41d8cd98f00b204e9800998ecf8427e")
    test.eq(test.ipc("md5", "The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
    test.eq(test.ipc("md5", string.rep("a", 120)), "5f61c0ccad4cac44c75ff505e1f1e537")
  end)
  test.it("round-trips hex and html", function()
    load()
    local hex, back = test.ipc("hex", "héllo")
    test.eq(hex, "68c3a96c6c6f")
    test.eq(back, "héllo")
    local html, plain = test.ipc("html", [[<a href="x">&</a>]])
    test.eq(html, "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;")
    test.eq(plain, [[<a href="x">&</a>]])
    test.eq(test.ipc("rot13", "Hello"), "Uryyb")
  end)
  test.it("writes every naming style", function()
    load()
    local cases = test.ipc("cases", "launcherActionPanel")
    test.eq(cases["snake_case"], "launcher_action_panel")
    test.eq(cases["kebab-case"], "launcher-action-panel")
    test.eq(cases["camelCase"], "launcherActionPanel")
    test.eq(cases["PascalCase"], "LauncherActionPanel")
    test.eq(cases["CONSTANT_CASE"], "LAUNCHER_ACTION_PANEL")
    test.eq(test.ipc("cases", "hello big world")["Title Case"], "Hello Big World")
  end)
  test.it("reads a token and JSON, and refuses what is neither", function()
    load()
    local token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2ln"
    local header, payload = test.ipc("jwt", token)
    test.matches(header, "HS256")
    test.matches(payload, "1234")
    test.falsy(test.ipc("jwt", "not a token"))
    local pretty, line = test.ipc("json", '{"b":[1,2],"a":true}')
    test.matches(pretty, '"a": true')
    test.matches(pretty, '\n  "b": %[\n    1,')
    test.truthy(#line < #pretty)
    test.falsy(test.ipc("json", "{nope"))
  end)
  test.it("names code points", function()
    load()
    test.eq(test.ipc("points", "é"), { { "é", "U+00E9" } })
  end)
end)

test.describe("dates", function()
  -- Sunday 1 November 2026, 12:00 UTC.
  local NOW = "1793534400"
  test.it("reads durations", function()
    load()
    test.eq(test.ipc("duration", "5m"), 300)
    test.eq(test.ipc("duration", "1h 30m"), 5400)
    test.eq(test.ipc("duration", "90 seconds"), 90)
    test.eq(test.ipc("duration", "1:30"), 90)
    test.eq(test.ipc("duration", "10"), 600)
    local seconds, rest = test.ipc("duration", "12 min pasta water")
    test.eq(seconds, 720)
    test.eq(rest, "pasta water")
    test.falsy(test.ipc("duration", "soon"))
    test.eq(test.ipc("span", "5400"), "1h 30m")
    test.eq(test.ipc("span", "45"), "45s")
  end)
  test.it("reads clocks", function()
    load()
    local h, m = test.ipc("clock", "10am")
    test.eq({ h, m }, { 10, 0 })
    h, m = test.ipc("clock", "2:15pm")
    test.eq({ h, m }, { 14, 15 })
    h, m = test.ipc("clock", "12am")
    test.eq({ h, m }, { 0, 0 })
    local _, _, rest = test.ipc("clock", "15:30 utc in tokyo")
    test.eq(rest, "utc in tokyo")
    test.falsy(test.ipc("clock", "25:00"))
  end)
  test.it("knows zones by city and by abbreviation", function()
    load()
    test.eq(test.ipc("zone", "utc"), "UTC")
    test.eq(test.ipc("zone", "pst"), "America/Los_Angeles")
    test.eq(test.ipc("zone", "nowhere at all"), nil)
  end)
  test.it("reads dates as people say them", function()
    test.load { source = HOST, env = { TZ = "UTC" } }
    test.eq(test.ipc("parse", "1700000000", NOW), 1700000000)
    test.eq(test.ipc("parse", "1700000000000", NOW), 1700000000)
    test.eq(test.ipc("format", test.ipc("parse", "2026-12-25", NOW)):sub(1, 10), "2026-12-25")
    test.eq(test.ipc("parse", "soon", NOW), nil)
    test.eq(test.ipc("relative", "1793534500", NOW), "in 1 min")
    test.eq(test.ipc("relative", "1793520000", NOW), "4 h ago")
  end)
  test.it("counts days, moves in weeks, and rolls a past date to next year", function()
    load()
    local base = 1793534400
    test.eq(test.ipc("days", tostring(base), tostring(base + 3 * 86400)), 3)
    local moved = test.ipc("parse", "in 3 weeks", NOW)
    test.eq(moved - base, 21 * 86400)
    local gone = test.ipc("parse", "3 days ago", NOW)
    test.eq(base - gone, 3 * 86400)
    local past = test.ipc("parse", "1 jan", NOW)
    test.truthy(past > base, "1 Jan should be next year's")
  end)
end)

test.describe("ssh", function()
  test.it("lists named hosts and follows includes, and skips patterns", function()
    load()
    local root = morf.env("XDG_STATE_HOME") .. "/ssh"
    morf.fs.mkdir(root, { parents = true })
    morf.fs.write(root .. "/extra", "Host included\n  HostName 10.0.0.9\n")
    morf.fs.write(root .. "/config", table.concat({
      "# a comment", "Host *", "  ForwardAgent no", "Host box web", "  HostName example.org", "  User me", "  Port 2222",
      "Host jump-?", "  User nope", "Match host x", "  User nope", "Include " .. root .. "/extra", "" }, "\n"))
    local hosts = test.ipc("ssh", root .. "/config")
    test.eq(#hosts, 3)
    test.eq(hosts[1].alias, "box")
    test.eq(hosts[1].hostname, "example.org")
    test.eq(hosts[1].user, "me")
    test.eq(hosts[1].port, "2222")
    test.eq(hosts[2].alias, "web")
    test.eq(hosts[3].alias, "included")
    test.eq(hosts[3].hostname, "10.0.0.9")
  end)
  test.it("reads known hosts, not hashed ones or bare addresses", function()
    load()
    local names = test.ipc("known", "github.com,140.82.1.1 ssh-ed25519 AAAA\n|1|hash= ssh-rsa AAAA\n[gitlab.io]:2222 ssh-rsa AAA\n10.0.0.1 ssh-rsa AAA\n")
    test.eq(names, { "github.com", "gitlab.io" })
  end)
  test.it("answers with nothing for a file that is not there", function()
    load()
    test.eq(test.ipc("ssh", "/nonexistent/config"), {})
  end)
end)

test.describe("recent files", function()
  test.it("reads local files, newest first, decoded", function()
    load()
    local xbel = [[
<xbel version="1.0">
  <bookmark href="file:///home/me/old.txt" added="2020-01-01T00:00:00Z" modified="2020-01-01T00:00:00Z" visited="2020-01-01T00:00:00Z">
    <info><metadata><mime:mime-type type="text/plain"/></metadata></info>
  </bookmark>
  <bookmark href="https://example.org/skip" added="2026-01-01T00:00:00Z" visited="2026-01-01T00:00:00Z"></bookmark>
  <bookmark href="file:///home/me/a%20new%20one.pdf" added="2026-01-01T00:00:00Z" modified="2026-01-02T00:00:00Z" visited="2026-01-03T00:00:00Z">
  </bookmark>
</xbel>]]
    local files = test.ipc("recent", xbel)
    test.eq(#files, 2)
    test.eq(files[1].path, "/home/me/a new one.pdf")
    test.eq(files[2].mime, "text/plain")
    test.eq(#test.ipc("recent", xbel, "1"), 1)
  end)
end)
