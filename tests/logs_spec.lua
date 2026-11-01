-- eva-logs through the stand-in journalctl of tests/fixtures/bin-see, spawned for
-- real: entries read and followed, the choices narrowing them, the pool and the
-- bound on what is kept, and a machine with no journal. The real journalctl is
-- tools/see/logs.steps'.
--
--     morf test --no-dbus tests/logs_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local JOURNAL = ROOT .. "tests/fixtures/bin-see/journalctl"

local function env(extra)
  local out = { EVA_JOURNALCTL = JOURNAL, EVA_DRY_RUN = "1", EVA_SETTINGS = "/nonexistent/eva.json" }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

local function tool(extra, args)
  test.load("../apps/logs/app.lua", { env = env(extra), args = args })
end

local function arrived(count)
  test.wait(function()
    test.advance(250)
    return test.ipc("state").shown >= count
  end, 6000, "the entries arrived")
  test.settle(100)
end

test.it("reads a line of the journal", function()
  test.load("../apps/logs/app.lua", { env = env(), source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local model = require("model")
    morf.ipc.parse = function(line) return model.parse(line) end
  ]] })
  local entry = test.ipc("parse", '{"__CURSOR":"a","__REALTIME_TIMESTAMP":"1793613600000000","PRIORITY":"3","_SYSTEMD_UNIT":"x.service","_PID":"9","MESSAGE":"hello"}')
  test.eq(entry.key, "a")
  test.eq(entry.priority, 3)
  test.eq(entry.name, "x")
  test.eq(entry.text, "hello")
  test.eq(entry.at, 1793613600)
  local bytes = test.ipc("parse", '{"__CURSOR":"b","MESSAGE":[104,105]}')
  test.eq(bytes.text, "hi")
  test.falsy(test.ipc("parse", "not json"))
end)

test.it("shows the journal, the newest first", function()
  tool()
  arrived(10)
  local state = test.ipc("state")
  test.eq(state.rows[1].name, "blob")
  test.eq(state.rows[1].text, "hi!")
  test.eq(state.rows[2].text, "dhcp4 (wlan0): state changed new lease")
  test.eq(#test.logs("error"), 0)
end)

test.it("follows what comes after, without asking again", function()
  tool { STUB_JOURNAL_PACE = "0.05" }
  arrived(10)
  test.truthy(test.ipc("state").running)
  arrived(12)
  local state = test.ipc("state")
  test.contains(state.rows[1].text, "Followed entry")
  test.ipc("follow", "off")
  test.settle(100)
  test.falsy(test.ipc("state").running)
end)

test.it("narrows by priority, boot, unit and words", function()
  tool()
  arrived(10)
  test.contains(test.ipc("state").argv, "-b0")
  test.ipc("priority", "3")
  arrived(2)
  local state = test.ipc("state")
  test.contains(state.argv, "-p4")
  test.eq(state.shown, 4)
  test.ipc("priority", "1")
  arrived(10)
  test.ipc("unit", "sshd.service")
  arrived(1)
  test.contains(test.ipc("state").argv, "-usshd.service")
  test.eq(test.ipc("state").rows[1].name, "sshd")
  test.ipc("unit", "")
  arrived(10)
  test.ipc("boot", "2")
  arrived(2)
  state = test.ipc("state")
  test.contains(state.argv, "-b-1")
  test.falsy(state.running)
  test.eq(state.shown, 2)
end)

test.it("filters what is kept as it is typed, and asks the journal on Return", function()
  tool()
  arrived(10)
  test.ipc("search", "NVME")
  test.advance(50)
  test.settle(100)
  test.eq(test.ipc("state").shown, 1)
  test.ipc("search")
  test.advance(50)
  test.settle(100)
  test.truthy(test.ipc("state").shown >= 10)
  test.ipc("grep", "Accepted publickey")
  test.wait(function()
    test.advance(250)
    return test.ipc("state").shown == 1
  end, 6000, "the journal searched")
  test.contains(test.ipc("state").argv, "--grep=Accepted publickey")
end)

test.it("opens a unit given to it", function()
  tool(nil, { "sshd.service" })
  arrived(1)
  test.eq(test.ipc("state").unit, "sshd.service")
end)

test.it("shows the chosen entry in full, and copies it dry", function()
  tool()
  arrived(10)
  test.ipc("select", 2)
  test.settle(300)
  test.eq(test.get({ id = "logs-detail-text" }).text, "dhcp4 (wlan0): state changed new lease")
  test.eq(test.get({ id = "logs-detail-priority" }).text, "Debug")
  test.truthy(test.ipc("copy"))
  test.contains(test.ipc("state").message, "dry run")
  test.ipc("close")
  test.settle(300)
  test.falsy(test.find({ id = "logs-sheet" }).visible)
end)

test.it("says so on a machine with no journalctl", function()
  tool { EVA_JOURNALCTL = "/nonexistent/journalctl" }
  test.wait(function()
    test.advance(100)
    local state = test.ipc("state")
    return state.message ~= "" or test.find({ id = "logs-empty" }).visible
  end, 3000, "it said so")
  test.settle(100)
  test.truthy(test.find({ id = "logs-empty" }).visible)
end)

test.it("keeps its bound and its pool, however much comes", function()
  local source = [[
    local morf = require("morf")
    local model = require("model")
    model.LIMIT = 50
    model.FIRST = 50
    morf.ipc.flood = function(count)
      for index = 1, tonumber(count) do
        model.feed(('{"__CURSOR":"f%d","PRIORITY":"6","MESSAGE":"line %d"}'):format(index, index))
      end
      return true
    end
  ]] .. morf.fs.read(ROOT .. "apps/logs/app.lua")
  test.load("../apps/logs/app.lua", { env = env(), source = source })
  arrived(10)
  test.ipc("flood", "500")
  test.wait(function()
    test.advance(250)
    return test.ipc("state").kept == 50 and test.ipc("state").rows[1].text == "line 500"
  end, 6000, "the flood landed")
  local rows = 0
  for _, node in ipairs(test.nodes()) do
    if node.id and node.id:match("^logs%-text%-") then rows = rows + 1 end
  end
  test.truthy(rows > 0 and rows < 40, rows .. " rows built")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " fits a phone", function()
    tool { EVA_STYLE = style }
    test.resize_window("toplevel:Logs", 380, 800)
    arrived(10)
    test.ipc("select", 1)
    test.settle(500)
    local sheet = test.get { id = "logs-sheet" }
    test.truthy(sheet.x >= 0 and sheet.x + sheet.width <= 380, "the sheet runs off the side")
    test.truthy(test.get({ id = "logs-unit" }).x + test.get({ id = "logs-unit" }).width <= 380, "the unit runs off the side")
    test.eq(#test.logs("error"), 0)
  end)
end
