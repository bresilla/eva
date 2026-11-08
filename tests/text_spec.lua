-- eva-text: every transform against what it must answer, the secrets' fairness and
-- where they may go, the window, and the command line. The same transforms run from
-- a real shell pipe and checked against coreutils are tools/see/text.steps'.
--
--     morf test --no-dbus tests/text_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local PIECES = [[
  local morf = require("morf")
  require("morf.ui").Item { width = 1, height = 1 }
  local transforms = require("apps.text.transforms")
  local codec = require("lib.shell.launcher.codec")
  local password = require("lib.shell.launcher.password")
  local latest = {}
  morf.ipc.latest = function() return latest end
  morf.ipc.run = function(id, text)
    local item = transforms.find(id)
    latest = {}
    transforms.run(item, text or "", function(answer, why) latest.answer, latest.why = answer, why end)
    return latest
  end
  morf.ipc.not_utf8 = function() return codec.upper("ab\xff") == "AB\xff" end
  morf.ipc.counts = function(text) return transforms.counts(text) end
  morf.ipc.lorem = function(count) return codec.lorem(tonumber(count)) end
  morf.ipc.words = function() return password.WORDS end
  -- The transforms that are the launcher's codec itself, by name.
  morf.ipc.shared = function()
    local same = {}
    for _, id in ipairs { "upper", "lower", "title", "sentence", "camel", "pascal", "snake", "kebab", "constant" } do
      same[id] = transforms.find(id).run == codec[id]
    end
    same.hex = transforms.find("hex").run == codec.hex_encode
    same.html = transforms.find("html").run == codec.html_encode
    same.minify = transforms.find("minify").run == codec.json_minify
    return same
  end
  -- The picks these random bytes make, the source back in place after.
  morf.ipc.picks = function(size, bytes, count)
    local queue = {}
    for number in bytes:gmatch("%d+") do queue[#queue + 1] = tonumber(number) end
    local real = password.byte
    password.byte = function() return table.remove(queue, 1) end
    local out = {}
    for index = 1, tonumber(count) do out[index] = password.pick(tonumber(size)) end
    password.byte = real
    return out
  end
  -- How many UUIDs a password of `length` takes from the engine.
  morf.ipc.drawn = function(length)
    local real, calls = morf.encoding.uuid, 0
    morf.encoding.uuid = function() calls = calls + 1 return real() end
    password.generate(tonumber(length))
    morf.encoding.uuid = real
    return calls
  end
  morf.ipc.password = function(length, symbols)
    local options = { symbols = symbols == "yes" }
    return { value = password.generate(tonumber(length), options),
      bits = password.bits(tonumber(length), #password.alphabet(options)) }
  end
  morf.ipc.passphrase = function(count)
    return { value = password.passphrase(tonumber(count)), bits = password.passphrase_bits(tonumber(count)) }
  end
]]

local function fresh(name)
  local state = morf.env("XDG_STATE_HOME") .. "/text-" .. name .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

local function environment(state, style, extra)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  local env = { XDG_STATE_HOME = state, EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule",
    EVA_APPEARANCE = appearance, EVA_DRY_RUN = "1", EVA_TEST_TOOL = "text", EVA_TEST_PAGE = "648x700" }
  for key, value in pairs(extra or {}) do env[key] = value end
  return env
end

local function pieces()
  test.clear_stubs()
  test.load("../shell/init.lua", { source = PIECES, env = environment(fresh("pieces")) })
end

local function run(id, text) return test.ipc("run", id, text).answer end
local function refuse(id, text) return test.ipc("run", id, text).why end

-- ----------------------------------------------------------------------- case --

test.it("changes case, letters past ASCII too", function()
  pieces()
  test.eq(run("upper", "hello ëç"), "HELLO ËÇ")
  test.eq(run("lower", "HELLO ËÇ"), "hello ëç")
  test.eq(run("upper", "straße ÿ"), "STRAßE Ÿ")
  test.eq(run("upper", "привет"), "ПРИВЕТ")
  test.eq(run("title", "the quick-brown fox"), "The Quick-Brown Fox")
  test.eq(run("sentence", "HELLO THERE. HOW ARE YOU? fine"), "Hello there. How are you? Fine")
end)

test.it("leaves bytes that are not UTF-8 alone", function()
  pieces()
  test.truthy(test.ipc("not_utf8"))
end)

test.it("rewrites identifiers", function()
  pieces()
  test.eq(run("camel", "some nice words"), "someNiceWords")
  test.eq(run("pascal", "some_nice-words"), "SomeNiceWords")
  test.eq(run("snake", "someNiceWords"), "some_nice_words")
  test.eq(run("kebab", "HTTPServer error"), "http-server-error")
  test.eq(run("constant", "someNiceWords"), "SOME_NICE_WORDS")
end)

-- ---------------------------------------------------------------------- lines --

test.it("works on lines, keeping a final newline", function()
  pieces()
  test.eq(run("sort", "pear\napple\nmango\n"), "apple\nmango\npear\n")
  test.eq(run("rsort", "a\nc\nb"), "c\nb\na")
  test.eq(run("dedupe", "a\nb\na\nc\nb\n"), "a\nb\nc\n")
  test.eq(run("reverse", "1\n2\n3"), "3\n2\n1")
  test.eq(run("trim", "  one  \n two \t\n\n"), "one\n two")
end)

test.it("counts lines, words, characters and bytes", function()
  pieces()
  test.eq(test.ipc("counts", "ëa b\nc\n"), { lines = 2, words = 3, characters = 7, bytes = 8 })
  test.eq(test.ipc("counts", ""), { lines = 0, words = 0, characters = 0, bytes = 0 })
  test.eq(test.ipc("counts", "no newline").lines, 1)
  test.eq(run("count", "one two"), "1 line · 2 words · 7 characters · 7 bytes")
end)

-- ---------------------------------------------------------------------- codes --

test.it("encodes and decodes", function()
  pieces()
  test.eq(run("base64", "hello"), "aGVsbG8=")
  test.eq(run("unbase64", "aGVsbG8=\n"), "hello")
  test.eq(run("url", "a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9")
  test.eq(run("unurl", "a%20b%26c"), "a b&c")
  test.eq(run("hex", "AZ"), "415a")
  test.eq(run("unhex", "41 5a"), "AZ")
  test.eq(run("html", [[<a href="x">&</a>]]), "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;")
  test.eq(run("html", "it's"), "it&#39;s")
  test.eq(run("unhex", "0x415a"), "AZ")
end)

test.it("runs the launcher's codec itself, with no copy of its own", function()
  pieces()
  local same = test.ipc("shared")
  for id, shared in pairs(same) do test.truthy(shared, id .. " has a copy of its own") end
end)

test.it("says what is not what it decodes", function()
  pieces()
  test.contains(refuse("unbase64", "not base64 !!"), "Base64")
  test.contains(refuse("unhex", "xyz"), "hexadecimal")
end)

-- ----------------------------------------------------------------------- data --

test.it("lays out JSON with its keys in their order and its numbers as written", function()
  pieces()
  test.eq(run("json", '{"zebra":1.50,"apple":[1,{"x":null}],"e":{},"f":[]}'),
    '{\n  "zebra": 1.50,\n  "apple": [\n    1,\n    {\n      "x": null\n    }\n  ],\n  "e": {},\n  "f": []\n}')
  test.eq(run("minify", '{ "zebra" : 1.50,\n "a b" : [ 1 , 2 ] }'), '{"zebra":1.50,"a b":[1,2]}')
end)

test.it("leaves what is inside a JSON string alone", function()
  pieces()
  test.eq(run("minify", '{ "a{ , :" : "b\\" }" }'), '{"a{ , :":"b\\" }"}')
  test.eq(run("json", '["a,b"]'), '[\n  "a,b"\n]')
end)

test.it("says what is not JSON", function()
  pieces()
  test.contains(refuse("json", "{nope"), "not JSON")
end)

test.it("hashes to the published values", function()
  pieces()
  test.eq(run("sha1", "abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
  test.eq(run("sha256", "abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end)

test.it("hashes md5 in the tool, with no program, past what one handler holds", function()
  pieces()
  local function digest(text)
    test.ipc("run", "md5", text)
    return test.wait(function()
      test.advance(5)
      return test.ipc("latest").answer
    end, 8000, "the digest did not come")
  end
  test.eq(digest("abc"), "900150983cd24fb0d6963f7d28e17f72")
  test.eq(digest(string.rep("a", 100000)), "1af6d6f2f682f76f80e606aeaaee1680")
  test.eq(#test.runs(), 0)
  test.eq(#test.logs("error"), 0)
end)

test.it("lays out more JSON than a character at a time could", function()
  pieces()
  local list = string.rep('{"name":"value","list":[1,2,3],"flag":true},', 300)
  local answer = run("json", "[" .. list .. "0]")
  test.contains(answer, '\n    "name": "value",\n    "list": [\n      1,')
  test.eq(run("minify", answer), "[" .. list .. "0]")
end)

test.it("turns epochs into dates and dates into epochs", function()
  pieces()
  test.eq(run("epoch", "1793613600"), "2026-11-02 10:00:00 UTC")
  test.eq(run("epoch", "1793613600000"), "2026-11-02 10:00:00 UTC", "milliseconds")
  test.eq(run("epoch", "2026-11-02T10:00:00Z"), "1793613600")
  test.eq(run("epoch", "0\n86400"), "1970-01-01 00:00:00 UTC\n1970-01-02 00:00:00 UTC")
  test.contains(refuse("epoch", "whenever"), "Not a time")
end)

test.it("writes a colour eva-colorpick's way, every way", function()
  pieces()
  local answer = run("colour", "#3366cc")
  test.contains(answer, "#3366cc\nrgb(51, 102, 204)\nhsl(220, 60%, 50%)\noklch(")
  test.contains(refuse("colour", "not a colour"), "Not a colour")
end)

test.it("writes a number in every base", function()
  pieces()
  test.eq(run("base", "255"), "255\n0xff\n0o377\n0b11111111")
  test.eq(run("base", "0xff"), "255\n0xff\n0o377\n0b11111111")
  test.eq(run("base", "0b101"), "5\n0x5\n0o5\n0b101")
  test.eq(run("base", "0o17"), "15\n0xf\n0o17\n0b1111")
  test.eq(run("base", "0"), "0\n0x0\n0o0\n0b0")
  test.contains(refuse("base", "1.5"), "whole number")
end)

test.it("makes placeholder text by the paragraph", function()
  pieces()
  local _, breaks = test.ipc("lorem", "3"):gsub("\n\n", "")
  test.eq(breaks, 2)
  test.contains(test.ipc("lorem", "1"), "Lorem ipsum dolor sit amet")
end)

-- -------------------------------------------------------------------- secrets --

test.it("throws away the bytes that would favour some choices", function()
  pieces()
  test.eq(test.ipc("picks", "200", "250 5 255 7 201 9", "3"), { 6, 8, 10 }, "only what falls under 200 counts")
end)

test.it("draws two bytes for a choice among more than 256", function()
  pieces()
  test.eq(test.ipc("picks", "700", "255 255 1 44", "1"), { 301 })
end)

test.it("draws from the engine's random source, with no program", function()
  pieces()
  test.truthy(test.ipc("drawn", "24") >= 1)
  test.eq(#test.runs(), 0)
end)

test.it("makes a password from the alphabet asked for, and says its strength", function()
  pieces()
  local made = test.ipc("password", "12", "no")
  test.eq(#made.value, 12)
  test.truthy(made.value:match("^%w+$"))
  test.falsy(made.value:find("[lIO01]"), "no characters that look alike")
  test.eq(made.bits, 69)
  test.eq(test.ipc("password", "24", "yes").bits, 151)
end)

test.it("makes a passphrase of real words", function()
  pieces()
  local made = test.ipc("passphrase", "6")
  local _, dashes = made.value:gsub("%-", "")
  test.eq(dashes, 5)
  local words = {}
  for _, word in ipairs(test.ipc("words")) do words[word] = true end
  for word in made.value:gmatch("[^%-]+") do test.truthy(words[word], word) end
  test.truthy(made.bits >= 55, "at least 55 bits, got " .. made.bits)
end)

test.it("has no word twice, and only plain ones", function()
  pieces()
  local list, seen = test.ipc("words"), {}
  test.truthy(#list >= 512, "got " .. #list)
  for _, word in ipairs(list) do
    test.falsy(seen[word], word .. " is there twice")
    seen[word] = true
    test.truthy(word:match("^%l+$"), word)
  end
end)

-- ------------------------------------------------------------------ the page --

-- The page alone, as the Tools window shows it.
local PAGE = morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua")

local function window(style, extra)
  test.clear_stubs()
  test.load("../shell/init.lua", { env = environment(fresh("window"), style, extra), source = PAGE })
  test.settle(300)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("transforms the pad and undoes it, in " .. style, function()
    window(style)
    test.click("text-pad")
    test.type("hello world")
    test.settle(100)
    test.contains(test.get({ id = "text-counts" }).text, "2 words")
    test.click("text-do-upper")
    test.settle(100)
    test.eq(test.ipc("state").text, "HELLO WORLD")
    test.ipc("undo")
    test.settle(100)
    test.eq(test.ipc("state").text, "hello world")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("says why a transform refused and leaves the pad as it was", function()
  window()
  test.ipc("text", "{nope")
  test.ipc("apply", "json")
  test.settle(100)
  test.eq(test.ipc("state").text, "{nope")
  test.contains(test.ipc("state").message, "not JSON")
  test.eq(test.ipc("state").undo, 0)
end)

test.it("offers every transform on a machine with no programs", function()
  test.clear_stubs()
  test.load("../shell/init.lua", { env = environment(fresh("nomd5"), nil, { PATH = "/nonexistent" }), source = PAGE })
  test.settle(200)
  test.truthy(test.find { id = "text-do-md5-box" })
  test.truthy(test.find { id = "text-do-sha256-box" })
end)

test.it("keeps a generated secret out of its state, on screen only", function()
  window()
  test.ipc("make", "password")
  test.settle(100)
  local secret = test.get({ id = "text-secret" }).text
  test.eq(#secret, 24)
  test.falsy(morf.json.encode(test.ipc("state")):find(secret, 1, true))
  test.contains(test.ipc("state").made, "Password, 151 bits")
  test.truthy(test.ipc("copy_secret"))
end)

test.it("makes a passphrase from the launcher's own list", function()
  window()
  test.ipc("make", "passphrase")
  test.settle(100)
  local _, dashes = test.get({ id = "text-secret" }).text:gsub("%-", "")
  test.eq(dashes, 5)
  test.contains(test.ipc("state").made, "Passphrase, 56 bits")
end)

-- ---------------------------------------------------------- the command line --

local function job(args, input, env)
  local state = fresh("job")
  local out = state .. "/job.out"
  local extra = { EVA_JOB_OUT = out }
  for key, value in pairs(env or {}) do extra[key] = value end
  if input then
    extra.EVA_JOB_IN = state .. "/job.in"
    morf.fs.write(extra.EVA_JOB_IN, input)
  end
  test.load("../apps/text/app.lua", { args = args, env = environment(state, nil, extra) })
  test.advance(100)
  return morf.fs.read(out) or "", extra.EVA_JOB_IN
end

test.it("answers from stdin and lets the file go", function()
  test.clear_stubs()
  local answer, input = job({ "base64" }, "hello")
  test.eq(answer, "0\naGVsbG8=\n")
  test.falsy(morf.fs.exists(input))
end)

test.it("decodes with -d, to the byte", function()
  test.clear_stubs()
  test.eq(job({ "base64", "-d" }, "aGVsbG8="), "0\nhello")
  test.eq(job({ "hex", "-d" }, "4142"), "0\nAB")
end)

test.it("keeps a final newline from doubling", function()
  test.clear_stubs()
  test.eq(job({ "sort" }, "b\na\n"), "0\na\nb\n")
end)

test.it("takes words where nothing is piped in", function()
  test.clear_stubs()
  test.eq(job { "upper", "hello", "there" }, "0\nHELLO THERE\n")
end)

test.it("refuses a transform it does not know, and says where the list is", function()
  test.clear_stubs()
  test.contains(job { "nonsense" }, "1\nunknown transform: nonsense (eva-text list)")
end)

test.it("makes things from nothing", function()
  test.clear_stubs()
  test.matches(job { "uuid" }, "^0\n%x+%-%x+%-%x+%-%x+%-%x+\n$")
  test.contains(job { "lorem" }, "Lorem ipsum")
  test.eq(#job({ "password", "4", "--no-symbols" }), #"0\n" + 4 + 1)
  test.eq(#job({ "password", "1000" }), #"0\n" + 1000 + 1)
end)

test.it("lists what it does, whatever this machine has", function()
  test.clear_stubs()
  test.contains(job { "list" }, "case   upper lower")
  test.contains(job { "list" }, "make   uuid lorem password passphrase")
  test.contains(job({ "list" }, nil, { PATH = "/nonexistent" }), "md5")
end)

test.it("hands what is piped in to the tool, in a file it reads", function()
  test.clear_stubs()
  local log = morf.env("XDG_STATE_HOME") .. "/text-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. morf.env("XDG_STATE_HOME"), "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"),
    "sh", ROOT .. "apps/text/cli", "base64")
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  test.contains(morf.fs.read(log), "text/app.lua -- base64")
end)
