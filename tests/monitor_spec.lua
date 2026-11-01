-- eva-monitor against a machine in a folder: every process listed, searched and
-- sorted, what is asked of the chosen one, TERM then an explicit KILL held back
-- when dry, the pages, and no sampling while hidden. Real /proc and real signals
-- are tools/see/monitor.steps'.
--
--     morf test --no-dbus tests/monitor_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local machine = load(morf.fs.read(ROOT .. "tests/fixtures/fake_machine.lua"))()
local serial = 0

local HOST = [[
  local morf = require("morf")
  require("morf.ui").Item { width = 1, height = 1 }
  local procfs = require("procfs")
  morf.ipc.command = function(text) return procfs.command(text:gsub("~", "\0"), nil) or "" end
  morf.ipc.status = function(text) return procfs.status(text) end
  morf.ipc.io = function(text) return procfs.io(text) end
  morf.ipc.gpu = function(a, b) return procfs.gpu { a, b } end
  morf.ipc.busy = function(a, b, seconds)
    return procfs.gpu_busy(procfs.gpu { a }, procfs.gpu { b }, tonumber(seconds))
  end
  morf.ipc.sockets = function(protocol, text)
    return procfs.sockets(protocol, text, { ["555"] = true }, {})
  end
]]

local function fresh(options)
  serial = serial + 1
  local root = morf.env("XDG_STATE_HOME") .. "/monitor-" .. serial .. "-" .. tostring(morf.time.now_ms())
  return machine.build(root, options)
end

local function env(root, extra)
  local out = { EVA_MONITOR_ROOT = root, EVA_DRY_RUN = "1", EVA_STYLE = "material",
    XDG_STATE_HOME = root .. "/state", EVA_SETTINGS = "/nonexistent/eva.json" }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

local function tool(root, extra, source)
  test.load("../apps/monitor/app.lua", { env = env(root, extra), source = source })
end

-- Two samples, with the machine moved on between them.
local function sampled(root)
  test.advance(2100)
  machine.tick(root, 2)
  test.advance(2100)
  test.settle(200)
end

test.it("reads what /proc says of one process", function()
  test.load("../apps/monitor/app.lua", { source = HOST, env = { EVA_DRY_RUN = "1" } })
  test.eq(test.ipc("command", "/bin/sh~-c~sleep 1~"), "/bin/sh -c sleep 1")
  test.eq(test.ipc("command", ""), "")
  local status = test.ipc("status", "Name:\tsh\nUid:\t1000\t1000\t1000\t1000\nThreads:\t4\nVmSwap:\t8 kB\n")
  test.eq(status.uid, 1000)
  test.eq(status.threads, 4)
  test.eq(status.swap, 8192)
  local io = test.ipc("io", "rchar: 9\nwchar: 9\nread_bytes: 4096\nwrite_bytes: 8192\n")
  test.eq(io.read, 4096)
  test.eq(io.write, 8192)
end)

test.it("reads a DRM client once, however many fds hold it", function()
  test.load("../apps/monitor/app.lua", { source = HOST, env = { EVA_DRY_RUN = "1" } })
  local first = "drm-driver:\tamdgpu\ndrm-client-id:\t7\ndrm-pdev:\t0000:03:00.0\ndrm-engine-gfx:\t1000000000 ns\ndrm-memory-vram:\t1024 KiB\n"
  local again = test.ipc("gpu", first, first)
  test.eq(again.clients, 1)
  test.eq(again.memory, 1048576)
  local later = first:gsub("1000000000", "1500000000")
  test.near(test.ipc("busy", first, later, 1), 50, 0.01)
  local cycles = "drm-driver:\txe\ndrm-client-id:\t3\ndrm-cycles-rcs:\t100\ndrm-total-cycles-rcs:\t1000\n"
  local cycles_later = "drm-driver:\txe\ndrm-client-id:\t3\ndrm-cycles-rcs:\t350\ndrm-total-cycles-rcs:\t2000\n"
  test.near(test.ipc("busy", cycles, cycles_later, 1), 25, 0.01)
end)

test.it("reads sockets by their inode, in both families", function()
  test.load("../apps/monitor/app.lua", { source = HOST, env = { EVA_DRY_RUN = "1" } })
  local v4 = "   0: 0100007F:0277 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 555 1\n"
    .. "   1: 0100007F:0278 0101A8C0:01BB 01 00000000:00000000 00:00000000 00000000  1000 0 666 1\n"
  local rows = test.ipc("sockets", "tcp", v4)
  test.eq(#rows, 1)
  test.eq(rows[1].here, "127.0.0.1:631")
  test.eq(rows[1].state, "Listening")
  local v6 = "   0: 00000000000000000000000001000000:0277 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000 0 555 1\n"
  test.eq(test.ipc("sockets", "tcp6", v6)[1].here, "[::1]:631")
  local mapped = "   0: 0000000000000000FFFF00000100007F:0277 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000  1000 0 555 1\n"
  local open = test.ipc("sockets", "udp6", mapped)[1]
  test.eq(open.here, "[::ffff:127.0.0.1]:631")
  test.eq(open.protocol, "udp")
  test.eq(open.state, "Open")
end)

test.it("lists every process, beyond the dashboard's few", function()
  local root = fresh { processes = 30 }
  tool(root)
  sampled(root)
  local state = test.ipc("state")
  test.eq(state.count, 35)
  test.eq(state.shown, 35)
  test.eq(#test.logs("error"), 0)
end)

test.it("shows a full command line and the owner", function()
  local root = fresh()
  tool(root)
  sampled(root)
  local firefox
  for _, row in ipairs(test.ipc("state").rows) do
    if row.name == "firefox" then firefox = row end
  end
  test.eq(firefox.command, "/usr/bin/firefox --new-window https://example.test")
  test.eq(firefox.user, "ada")
  local kernel
  for _, row in ipairs(test.ipc("state").rows) do
    if row.name == "kthreadd" then kernel = row end
  end
  test.eq(kernel.command, "[kthreadd]")
  test.eq(kernel.user, "root")
end)

test.it("searches names, commands, users and numbers", function()
  local root = fresh { processes = 3 }
  tool(root)
  sampled(root)
  local function count(words)
    test.ipc("search", words)
    test.settle(100)
    return test.ipc("state").shown
  end
  test.eq(count("firefox"), 1)
  test.eq(count("example.test"), 1)
  test.eq(count("ROOT"), 2)
  test.eq(count("701"), 1)
  test.eq(count("worker id"), 3)
  test.eq(count("nothing-like-this"), 0)
  test.truthy(test.find({ id = "monitor-empty" }).visible)
end)

test.it("sorts by CPU, memory, name and PID", function()
  local root = fresh()
  tool(root)
  test.advance(2100)
  machine.process(root, { pid = 701, name = "Zed", command = "zed", ticks = 900, pages = 40000 })
  machine.tick(root, 2)
  test.advance(2100)
  test.settle(200)
  local function first()
    test.settle(100)
    return test.ipc("state").rows[1].name
  end
  test.eq(first(), "Zed")
  test.ipc("sort", "memory")
  test.eq(first(), "firefox")
  test.ipc("sort", "name")
  test.eq(first(), "alacritty")
  test.ipc("sort", "pid")
  test.eq(first(), "systemd")
  test.falsy(test.ipc("sort", "colour"))
end)

test.it("follows the chosen process as the rows move", function()
  local root = fresh()
  tool(root)
  sampled(root)
  test.ipc("select", 702)
  test.settle(200)
  test.eq(test.ipc("state").selected, 702)
  test.truthy(test.find({ id = "monitor-sheet" }).visible)
  test.eq(test.get({ id = "monitor-detail-name" }).text, "alacritty")
  test.ipc("sort", "pid")
  test.settle(200)
  test.eq(test.ipc("state").selected, 702)
  test.eq(test.get({ id = "monitor-detail-name" }).text, "alacritty")
  test.ipc("select", 0)
  test.settle(400)
  test.falsy(test.find({ id = "monitor-sheet" }).visible)
end)

test.it("asks the chosen process for its disk, GPU and connections only", function()
  local root = fresh()
  machine.io(root, 700, 1000, 2000)
  machine.fd(root, 700, 3, "socket:[555]")
  machine.fd(root, 700, 4, "socket:[777]")
  machine.fd(root, 700, 5, "/dev/dri/renderD128")
  machine.fd(root, 700, 6, "/home/ada/file")
  machine.fdinfo(root, 700, 5, "drm-driver:\tamdgpu\ndrm-client-id:\t9\ndrm-pdev:\t0000:03:00.0\ndrm-engine-gfx:\t1000000000 ns\ndrm-memory-vram:\t2048 KiB\n")
  machine.sockets(root, 700, "tcp", "   0: 0100007F:0277 0101A8C0:01BB 01 00000000:00000000 00:00000000 00000000  1000 0 555 1\n")
  machine.sockets(root, 700, "tcp6", "")
  machine.sockets(root, 700, "udp", "")
  machine.sockets(root, 700, "udp6", "")
  tool(root)
  sampled(root)
  test.ipc("select", 700)
  test.advance(2100)
  test.settle(200)
  machine.io(root, 700, 5000, 2000)
  machine.fdinfo(root, 700, 5, "drm-driver:\tamdgpu\ndrm-client-id:\t9\ndrm-pdev:\t0000:03:00.0\ndrm-engine-gfx:\t1500000000 ns\ndrm-memory-vram:\t2048 KiB\n")
  test.advance(2100)
  test.settle(200)
  local detail = test.ipc("state").detail
  test.eq(detail.read_total, 5000)
  test.truthy(detail.read_rate > 1000, "read " .. tostring(detail.read_rate))
  test.eq(detail.write_rate, 0)
  test.eq(detail.sockets, 2)
  test.eq(#detail.connections, 1)
  test.eq(detail.connections[1].there, "192.168.1.1:443")
  test.eq(detail.connections[1].state, "Established")
  test.eq(detail.gpu.clients, 1)
  test.eq(detail.gpu.memory, 2097152)
  test.truthy(detail.gpu.busy > 10, "busy " .. tostring(detail.gpu.busy))
  test.contains(test.get({ id = "monitor-detail-connections" }).text, "1 open")
end)

test.it("says what it cannot read of a process", function()
  local root = fresh()
  tool(root)
  sampled(root)
  test.ipc("select", 701)
  test.advance(2100)
  test.settle(200)
  test.eq(test.get({ id = "monitor-detail-total" }).text, "Not readable")
  test.eq(test.get({ id = "monitor-detail-gpu" }).text, "No GPU client")
end)

test.it("holds back TERM and KILL when dry, and KILL until TERM", function()
  local root = fresh()
  tool(root)
  sampled(root)
  test.ipc("select", 700)
  test.settle(100)
  test.falsy(test.ipc("kill", 700))
  test.eq(test.ipc("state").message, "End it first")
  test.truthy(test.find({ id = "monitor-term" }))
  test.truthy(test.ipc("term", 700))
  test.contains(test.ipc("state").message, "dry run")
  test.truthy(test.ipc("kill", 700))
  local sent = test.ipc("state").sent
  test.eq(sent[1].signal, "KILL")
  test.eq(sent[2].signal, "TERM")
  test.eq(sent[2].pid, 700)
  test.falsy(test.ipc("term", 1))
end)

test.it("signals for real when it is not dry", function()
  local root = fresh()
  local source = morf.fs.read(ROOT .. "apps/monitor/app.lua") .. [[
    morf.process.kill = function(pid, signal)
      morf.log("info", "kill " .. pid .. " " .. signal)
      return true
    end
  ]]
  tool(root, { EVA_DRY_RUN = "0" }, source)
  sampled(root)
  test.truthy(test.ipc("term", 700))
  test.truthy(test.ipc("kill", 700))
  local seen = {}
  for _, line in ipairs(test.logs("info")) do seen[#seen + 1] = line.message end
  test.contains(seen, "kill 700 TERM")
  test.contains(seen, "kill 700 KILL")
end)

test.it("walks the list by the keys", function()
  local root = fresh()
  tool(root)
  sampled(root)
  test.ipc("sort", "pid")
  test.settle(200)
  test.click { id = "monitor-search" }
  test.key("Down")
  test.settle(100)
  test.key("Down")
  test.settle(100)
  test.truthy(test.ipc("state").selected > 0, "the arrows chose nothing")
  test.key("Delete")
  test.settle(100)
  local sent = test.ipc("state").sent
  test.eq(sent[#sent].signal, "TERM", "Delete did not end the chosen process")
  test.key("Escape")
  test.settle(100)
  test.eq(test.ipc("state").selected, 0)
end)

test.it("samples only what the page shows, and nothing when paused or away", function()
  local root = fresh()
  tool(root)
  sampled(root)
  local running = test.ipc("sampling")
  test.contains(running, "processes")
  test.ipc("tab", "resources")
  test.advance(6500)
  running = test.ipc("sampling")
  test.contains(running, "cpu")
  test.contains(running, "gpu")
  test.falsy(table.concat(running, " "):find("processes"), table.concat(running, " "))
  test.ipc("pause", "on")
  test.advance(9000)
  test.eq(#test.ipc("sampling"), 0)
  test.ipc("pause", "off")
  test.advance(3000)
  test.truthy(#test.ipc("sampling") > 0)
  test.ipc("away", "on")
  test.advance(9000)
  test.eq(#test.ipc("sampling"), 0)
  test.eq(#test.logs("error"), 0)
end)

test.it("stops when the compositor says it is minimised", function()
  local root = fresh()
  local source = [[
    local morf = require("morf")
    local hidden = morf.signal("spec.hidden", false)
    morf.toplevels = { list = function()
      return { { app_id = "eva.monitor", minimized = hidden:get() } }
    end }
    morf.ipc.hidden = function(how) hidden:set(how == "on") return true end
  ]] .. morf.fs.read(ROOT .. "apps/monitor/app.lua")
  tool(root, nil, source)
  sampled(root)
  test.truthy(#test.ipc("sampling") > 0)
  test.truthy(test.ipc("state").live)
  test.ipc("hidden", "on")
  test.advance(9000)
  test.falsy(test.ipc("state").live)
  test.eq(#test.ipc("sampling"), 0)
  test.ipc("hidden", "off")
  test.advance(3000)
  test.truthy(#test.ipc("sampling") > 0)
end)

test.it("keeps a pool of rows, however long the list", function()
  local root = fresh { processes = 300 }
  tool(root)
  sampled(root)
  test.eq(test.ipc("state").count, 305)
  local rows = 0
  for _, node in ipairs(test.nodes()) do
    if node.id and node.id:match("^monitor%-name%-") then rows = rows + 1 end
  end
  test.truthy(rows > 0 and rows < 40, rows .. " rows built")
end)

test.it("shows the machine's totals and each core", function()
  local root = fresh()
  tool(root)
  test.ipc("tab", "resources")
  test.advance(2100)
  machine.tick(root, 2)
  test.advance(2100)
  test.settle(300)
  test.truthy(test.find { id = "monitor-core-2" })
  test.falsy(test.find { id = "monitor-core-3" })
  test.contains(test.get({ id = "monitor-cpu-name" }).text, "i7-11800H")
  test.contains(test.get({ id = "monitor-tile-gpu" }) and test.text_of(test.get({ id = "monitor-tile-gpu" })), "42")
  test.contains(test.text_of(test.get({ id = "monitor-tile-swap" })), "977 MiB")
  test.truthy(test.find { id = "monitor-device-drive:nvme0n1" })
  test.truthy(test.find { id = "monitor-device-net:eth0" })
  test.truthy(test.find { id = "monitor-device-gpu:card0" })
  test.eq(#test.logs("error"), 0)
end)

test.it("reads temperatures and fans, and hides a machine with neither", function()
  local root = fresh()
  tool(root)
  test.ipc("tab", "sensors")
  test.advance(6000)
  test.settle(300)
  test.eq(test.get({ id = "monitor-sensor-value-temp:coretemp/Package id 0" }).text, "61.0 °C")
  test.eq(test.get({ id = "monitor-sensor-value-fan:dell_smm/Processor Fan" }).text, "3200 RPM")
  test.falsy(test.find({ id = "monitor-sensors-empty" }).visible)

  local bare = fresh { sensors = false }
  tool(bare)
  test.ipc("tab", "sensors")
  test.advance(6000)
  test.settle(300)
  test.truthy(test.find({ id = "monitor-sensors-empty" }).visible)
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " fits a phone, the sheet inside the window", function()
    local root = fresh { processes = 12 }
    tool(root, { EVA_STYLE = style })
    test.resize_window("toplevel:Monitor", 380, 800)
    sampled(root)
    test.ipc("select", 700)
    test.settle(600)
    local sheet = test.get { id = "monitor-sheet" }
    test.truthy(sheet.x >= 0 and sheet.x + sheet.width <= 380, "the sheet runs off the side")
    test.truthy(sheet.y + sheet.height <= 800, "the sheet runs off the foot")
    test.ipc("select", 0)
    test.ipc("tab", "resources")
    test.advance(4300)
    test.settle(500)
    test.truthy(test.find { id = "monitor-core-1" })
    test.ipc("tab", "sensors")
    test.advance(4300)
    test.settle(500)
    test.eq(#test.logs("error"), 0)
  end)
end
