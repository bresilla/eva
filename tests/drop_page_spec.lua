-- The Drop page over a stand-in for the `drop` CLI. The real one is never run
-- here: any subcommand of it makes a key on a machine that has none.
--     morf test --no-dbus tests/drop_page_spec.lua
local test = morf.test
local ROOT = morf.env("PWD")
local BIN = ROOT .. "/tests/fixtures/bin-stand-in"
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  local drop = require("lib.integrations.drop")
  drop.env = { XDG_CONFIG_HOME = morf.env("XDG_CONFIG_HOME"), STUB_LOG = morf.env("STUB_LOG"),
    DROP_FAKE_SERVING = morf.env("DROP_FAKE_SERVING") or nil, DROP_FAKE_EMPTY = morf.env("DROP_FAKE_EMPTY") or nil }
  local model = require("drop_model")
  local shown = morf.signal("drop.spec.shown", false)
  local active = function() return shown:get() end
  ui.Item { width = W, height = H,
    require("themes.layouts.page").frame { id = "page-drop", width = W, height = function() return H end,
      title = "Drop", titled = true, active = active,
      build = function(bw, bh) return require("drop").build({ active = active }, bw, bh) end } }
  morf.ipc.show = function(on) shown:set(on == "yes") end
  local function rows(list)
    local out = {}
    for i = 1, list:len() do out[i] = list:get(i) end
    return out
  end
  morf.ipc.state = function()
    return { stage = model.stage(), serving = model.serving:get(), identity = model.identity:get(), said = model.said:get(),
      selected = model.selected:get(), reach = model.reach:get(), pending = model.pending:get(), folder = model.folder:get(),
      people = rows(model.people), machines = rows(model.machines), targets = rows(model.targets), topics = rows(model.topics),
      nearby = rows(model.nearby), asking = rows(model.asking), remote = rows(model.remote), files = rows(model.files),
      log = rows(model.log), transfers = rows(model.transfers), received = rows(model.received), code = model.code:get(),
      conversations = rows(model.conversations) }
  end
  morf.ipc.select = model.select
  morf.ipc.send = function(path) return model.send { path } end
  morf.ipc.message = model.message
  morf.ipc.browse = model.browse
  morf.ipc.open_file = function(index) model.open_file(model.files:get(tonumber(index))) end
  morf.ipc.up = model.up
  morf.ipc.set_up = model.set_up
  morf.ipc.start = model.start_serve
  morf.ipc.pair = model.pair
  morf.ipc.decide = function(name, yes) return model.decide(name, yes == "yes") end
  morf.ipc.check_all = model.check_all
  morf.ipc.add_topic = model.add_topic
  morf.ipc.offer = model.offer_code
  morf.ipc.stop_offer = model.stop_offer
  morf.ipc.take_code = model.take_code
]]

local count = 0
local scratch, log
local function prepare(identified)
  count = count + 1
  scratch = ("%s/drop-spec-%d-%d"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(scratch .. "/config/drop")
  log = scratch .. "/calls.log"
  morf.fs.write(log, "")
  if identified then morf.fs.write(scratch .. "/config/drop/badge", "") end
end
local function load(style, env, size)
  local w, h = (size or { 1500, 610 })[1], (size or { 1500, 610 })[2]
  local all = { EVA_STYLE = style or "material", EVA_SETTINGS = scratch .. "/eva.json", XDG_CONFIG_HOME = scratch .. "/config",
    STUB_LOG = log, PATH = BIN .. ":" .. morf.env("PATH"), TEST_WIDTH = tostring(w), TEST_HEIGHT = tostring(h), EVA_DRY_RUN = "0" }
  for name, value in pairs(env or {}) do all[name] = value end
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = all })
  test.advance(50)
end
local function show() test.ipc("show", "yes") end
local function state() return test.ipc("state") end
local function calls() return morf.fs.read(log) end
local function until_(check, what)
  return test.wait(function() test.advance(30) local s = state() return check(s) and s end, 6000, what)
end
local function loaded(serving)
  prepare(true)
  load(nil, { DROP_FAKE_SERVING = serving == false and "" or "1" })
  show()
  return until_(function(s) return #s.targets > 0 and #s.topics > 0 and s.serving ~= "unknown" end, "the lists")
end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end

test.describe("drop page", function()
  test.it("runs no drop command at all on a machine that has never run it", function()
    prepare(false)
    load()
    show()
    test.advance(1500)
    test.eq(state().stage, "first-run")
    test.eq(calls(), "", "a page was looked at and drop ran")
    test.falsy(morf.fs.exists(scratch .. "/config/drop/badge"), "looking at a page made a key")
    test.truthy(test.get("drop-placeholder").visible)
    test.truthy(test.find { text = "Drop has no identity on this machine" })
    test.falsy(test.get("drop-scroll").visible)
  end)

  test.it("makes the identity only on a press, then reads", function()
    prepare(false)
    load()
    show()
    test.advance(100)
    test.click("drop-set-up")
    local s = until_(function(x) return x.stage == "ready" and #x.targets > 0 end, "set up")
    test.truthy(calls():find("MINTED me id", 1, true))
    test.truthy(s.identity:find("tron", 1, true))
    test.truthy(test.get("drop-scroll").visible)
  end)

  test.it("says when drop is not installed", function()
    prepare(false)
    load(nil, { PATH = "/nonexistent" })
    show()
    test.advance(300)
    test.eq(state().stage, "missing")
    test.truthy(test.find { text = "drop is not installed" })
    test.falsy(test.get("drop-set-up").visible)
    test.eq(calls(), "")
  end)

  test.it("says when drop serve is not running, and offers to start it", function()
    local s = loaded(false)
    test.eq(s.serving, "no")
    test.truthy(test.find { text = "drop serve is not running" })
    test.truthy(test.get("drop-start-serve").visible)
    test.eq(#s.nearby, 0)
    test.ipc("start")
    s = until_(function(x) return x.serving == "yes" end, "serve up")
    test.truthy(calls():find("drop serve --quiet", 1, true))
    test.falsy(test.get("drop-start-serve").visible)
    test.truthy(test.find { text = "drop serve is running" })
  end)

  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. " lists people, machines, topics and what is nearby", function()
      prepare(true)
      load(style, { DROP_FAKE_SERVING = "1" })
      show()
      local s = until_(function(x) return #x.targets > 0 and #x.nearby > 0 and #x.topics > 0 end, "the lists")
      test.eq(s.identity:find("tron  ·  ", 1, true), 1)
      test.eq(s.people[1].me, true)
      test.eq(s.people[2].name, "bob")
      test.eq(s.people[2].trusted, true)
      test.eq(s.people[2].machines, { "laptop", "phone" })
      test.eq(s.people[3].trusted, false)
      test.eq(s.targets[1].address, "orin")
      test.eq(s.targets[2].address, "bob:laptop")
      test.eq(s.machines[1].here, true)
      test.eq(s.topics[1].kind, "inbox")
      test.eq(s.topics[1].path, "/inbox")
      test.eq(s.topics[2].kind, "chat")
      test.eq(s.nearby[1].name, "lab-printer")
      test.eq(s.asking[1].name, "phone-of-dana")
      test.eq(s.asking[1].check, "4821")
      test.truthy(s.received[1].name == "agenda.pdf", "the inbox folder's files are listed")
      test.truthy(test.find { id = "drop-person-bob-laptop" })
      shot(style .. "-drop")
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("says who answers and what they offer", function()
    loaded()
    test.ipc("select", "bob:laptop")
    local s = until_(function(x) return x.reach["bob:laptop"] == "yes" and #x.remote > 0 end, "bob's topics")
    test.eq(s.remote[3].kind, "folder")
    test.eq(s.remote[3].path, "/papers")
    test.ipc("select", "carol:desk")
    s = until_(function(x) return x.reach["carol:desk"] == "no" end, "carol's machine")
    test.eq(#s.remote, 0)
    test.truthy(test.find { text = "Not reachable now" })
  end)

  test.it("sends a file to the person on show, over /inbox", function()
    loaded()
    test.ipc("select", "bob:laptop")
    test.ipc("send", "/tmp/report.pdf")
    local s = until_(function(x) return #x.transfers > 0 and x.transfers[1].state == "Sent" end, "sent")
    test.eq(s.transfers[1].name, "report.pdf")
    test.truthy(calls():find("drop connect bob:laptop:/inbox /tmp/report.pdf", 1, true))
  end)

  test.it("says what a failed send said", function()
    loaded()
    test.ipc("select", "carol:desk")
    test.ipc("send", "/tmp/report.pdf")
    local s = until_(function(x) return #x.transfers > 0 and x.transfers[1].state ~= "Sending…" end, "failed")
    test.eq(s.transfers[1].state, "desk is off")
  end)

  test.it("holds a dropped file until somebody is pressed", function()
    loaded()
    test.ipc("send", "/tmp/held.txt")
    test.eq(state().pending, "held.txt")
    test.eq(#state().transfers, 0)
    test.falsy(calls():find("held.txt", 1, true))
    test.ipc("select", "bob:laptop")
    until_(function(x) return #x.transfers > 0 and x.transfers[1].state == "Sent" end, "sent")
    test.eq(state().pending, "")
    test.truthy(calls():find("drop connect bob:laptop:/inbox /tmp/held.txt", 1, true))
  end)

  test.it("walks a shared folder and fetches a file", function()
    loaded()
    test.ipc("select", "bob:laptop")
    until_(function(x) return #x.remote > 0 end, "topics")
    test.ipc("browse", "/papers")
    local s = until_(function(x) return #x.files > 0 end, "files")
    test.eq(s.files[1].name, "deep")
    test.eq(s.files[1].folder, true)
    test.eq(s.files[2].name, "thesis.pdf")
    test.eq(s.files[2].size, "2.1 MB")
    test.ipc("open_file", 1)
    s = until_(function(x) return x.folder == "/papers/deep" and #x.files == 1 end, "the deeper folder")
    test.eq(s.files[1].name, "inner.txt")
    test.ipc("up")
    until_(function(x) return x.folder == "/papers" and #x.files == 2 end, "back up")
    test.ipc("open_file", 2)
    until_(function(x) return #x.transfers > 0 and x.transfers[1].state == "Fetched" end, "fetched")
    test.truthy(calls():find("drop file get bob:laptop:/papers/thesis.pdf", 1, true))
    test.ipc("up")
    test.eq(state().folder, "")
  end)

  test.it("shows a conversation and says something in it", function()
    loaded()
    test.ipc("select", "bob:laptop")
    local s = until_(function(x) return #x.log > 0 end, "the log")
    test.truthy(s.log[1].text:find("are you around later", 1, true))
    test.eq(#s.log, 3, "the waiting line is not a message")
    test.ipc("message", "on my way")
    test.wait(function() test.advance(30) return calls():find("connect bob:laptop:/chat on my way", 1, true) end, 3000, "said")
  end)

  test.it("pairs with what is nearby, and answers who asks", function()
    loaded()
    test.ipc("pair", "lab-printer")
    test.wait(function() test.advance(30) return calls():find("nearby pair lab-printer", 1, true) end, 3000, "pair")
    test.ipc("decide", "phone-of-dana", "yes")
    test.wait(function() test.advance(30) return calls():find("nearby yes phone-of-dana", 1, true) end, 3000, "yes")
  end)

  test.it("shows this machine's code while it is offered", function()
    loaded()
    test.ipc("offer")
    local s = until_(function(x) return x.code ~= "" end, "the code")
    test.eq(s.code, "brisk-lantern-42")
    test.ipc("stop_offer")
    until_(function(x) return x.code == "" end, "the code taken down")
  end)

  test.it("takes a code somebody shows", function()
    loaded()
    test.ipc("take_code", "other-code-7")
    test.wait(function() test.advance(30) return calls():find("person add other-code-7", 1, true) end, 3000, "code")
  end)

  test.it("adds a topic, refusing a name that is not one word", function()
    loaded()
    test.falsy(test.ipc("add_topic", "two words", "folder", "me"))
    test.truthy(state().said:find("one word", 1, true))
    test.ipc("add_topic", "work", "folder", "paired")
    test.wait(function() test.advance(30) return calls():find("topic add work folder --for paired", 1, true) end, 3000, "topic")
  end)

  test.it("says nobody is known yet, and offers a way in", function()
    prepare(true)
    load(nil, { DROP_FAKE_SERVING = "1", DROP_FAKE_EMPTY = "1" })
    show()
    local s = until_(function(x) return #x.machines > 0 and #x.people > 0 end, "the lists")
    test.eq(#s.targets, 1, "only this user's other machine")
    test.truthy(test.get("drop-offer").visible)
  end)

  test.it("stacks on a phone, the person on show on top", function()
    prepare(true)
    load("material", { DROP_FAKE_SERVING = "1" }, { 390, 780 })
    show()
    until_(function(x) return #x.targets > 0 end, "the lists")
    test.ipc("select", "bob:laptop")
    test.advance(100)
    test.truthy(test.get("drop-selected").y < test.get("drop-status").y)
    test.eq(test.get("drop-selected").width, 390)
    shot("phone-drop")
  end)

  test.it("stops polling when the page goes", function()
    loaded()
    test.ipc("show", "no")
    test.advance(100)
    local before = select(2, calls():gsub("\n", "\n"))
    test.advance(25000)
    test.eq(select(2, calls():gsub("\n", "\n")), before)
  end)
end)
