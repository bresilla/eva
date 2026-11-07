-- Every way to a tool now that its page is in the Tools window, or Settings':
-- the launcher's search, a link, a notification's action, a tile and a bar
-- module, `eva open`, each `eva-NAME` alone and with words, and an overlay's
-- page starting its program. The menu keeps two of eva's entries, and nothing
-- of a tool loads before its page opens.
--
--     morf test --no-dbus tests/tools_routes_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local host = assert(load(morf.fs.read(ROOT .. "tests/fixtures/launcher_host.lua")))()

local EXTRA = [[
  morf.ipc.q_loaded = function(prefix)
    local out = {}
    for name in pairs(package.loaded) do
      if name:sub(1, #prefix) == prefix then out[#out + 1] = name end
    end
    table.sort(out)
    return out
  end
  morf.ipc.q_open_tool = function(name, word)
    return require("lib.services.host").open_tool(name, word and { word } or nil)
  end
  morf.ipc.q_bar = function(id)
    for _, module in ipairs(require("bar").model.modules) do
      if module.id == id then module.press() return true end
    end
    return false
  end
  morf.ipc.q_tile = function(id)
    local settings = require("utilities")
    settings.CONTROLS[id].set(true)
    return true
  end
  morf.ipc.q_settings = function()
    local settings = require("utilities")
    return { open = settings.opened:get(), page = settings.detail:get() }
  end
]]

local function shell(options)
  options = options or {}
  options.source_extra = EXTRA
  host.load(options)
  test.ipc("launcher", "close")
  test.settle(400)
end

local function tools() return test.ipc("tools", "state") end

test.it("loads nothing of a tool at start, and builds Tools' content only once it opens", function()
  shell()
  test.eq(test.ipc("q_loaded", "apps."), {})
  test.falsy(test.find { id = "tools-window-content" })
  test.ipc("tools", "clock") test.settle(1200)
  test.contains(test.ipc("q_loaded", "apps."), "apps.clock.page")
  test.eq(#test.logs("error"), 0)
end)

test.it("finds a tool by its name, a thing it holds, and its words, and opens its page", function()
  shell()
  test.ipc("launcher", "open") test.settle(600)
  host.search("monitor")
  local row = host.row("Monitor")
  test.truthy(row, "no tool found by its name")
  test.eq(row.tag, "Tool")
  host.search("stopwatch")
  test.truthy(host.row("Stopwatch"), "no tool found by what it holds")
  host.search("eyedropper")
  test.truthy(host.row("Colour picker"), "no tool found by its words")
  test.eq(test.ipc("chosen"), "Colour picker")
  test.key("Return") test.settle(1200)
  test.eq(tools(), { open = true, page = "colorpick" })
  test.falsy(test.ipc("state").open, "the launcher stayed open")
end)

test.it("a link to a text opens its thread, and to a number has it typed", function()
  shell { env = { EVA_FAKE_MODEM = "1" } }
  test.truthy(test.ipc("q_open_tool", "messages", "sms:+3161234"))
  test.settle(1200)
  test.eq(tools(), { open = true, page = "messages" })
  test.eq(test.ipc("tool", "messages", "state").open, "+3161234")
  test.truthy(test.ipc("q_open_tool", "phone", "tel:+3112345"))
  test.settle(1200)
  test.eq(test.ipc("tool", "phone", "state").number, "+3112345")
  test.eq(#test.logs("error"), 0)
end)

test.it("a tool that became a Settings page opens there", function()
  shell()
  test.truthy(test.ipc("q_open_tool", "keys"))
  test.settle(1200)
  test.eq(test.ipc("q_settings"), { open = true, page = "input/shortcuts" })
  test.truthy(test.ipc("q_open_tool", "breaks"))
  test.settle(1200)
  test.eq(test.ipc("q_settings"), { open = true, page = "breaks" })
  test.falsy(tools().open)
end)

test.it("the quick tiles and the bar's modules open the tools' pages", function()
  shell()
  test.ipc("q_tile", "clock") test.settle(1200)
  test.eq(tools(), { open = true, page = "clock" })
  test.ipc("tools", "close") test.settle(600)
  test.ipc("q_bar", "clipboard") test.settle(1200)
  test.eq(tools(), { open = true, page = "clipboard" })
  test.ipc("q_bar", "keybinds") test.settle(1200)
  test.eq(test.ipc("q_settings"), { open = true, page = "input/shortcuts" })
  test.falsy(tools().open, "Tools stayed open under Settings")
end)

test.it("an overlay's page shuts the window and starts its program", function()
  shell()
  local function started(tool, verb, words, ...)
    test.ipc("tools", tool) test.settle(1200)
    test.clear_logs()
    test.ipc("tool", tool, verb, ...)
    test.advance(800)
    test.falsy(tools().open, tool .. ": Tools stayed open over the screen")
    test.truthy(host.logged("open " .. tool .. words), tool .. " did not start: " .. words)
  end
  test.ipc("tools", "find") test.settle(1200)
  test.ipc("tool", "find", "mode", "crosshairs")
  started("find", "start", " --crosshairs")
  started("ruler", "start", " spacing")
  started("draw", "start", " start")
  started("colorpick", "pick", " --pick")
  started("zoom", "lens", " lens")
  test.ipc("tools", "large") test.settle(1200)
  test.ipc("tool", "large", "words", "hello there")
  started("large", "show", " hello there")
  test.ipc("tools", "screenshot") test.settle(1200)
  test.ipc("tool", "screenshot", "choose", "after", "copy")
  started("screenshot", "shoot", " region --copy")
  test.eq(#test.logs("error"), 0)
end)

test.it("leaves no tool's page behind once Tools has shut", function()
  shell()
  for _, tool in ipairs { "clock", "clipboard", "text", "logs" } do
    test.ipc("tools", tool) test.settle(900)
    test.truthy(test.find { id = "tools-detail-" .. tool, visible = true }, tool)
  end
  test.ipc("tools", "close")
  test.advance(1600) test.settle(400)
  for _, tool in ipairs { "clock", "clipboard", "text", "logs" } do
    test.falsy(test.find { id = "tools-detail-" .. tool }, tool .. "'s page stayed built")
  end
  test.ipc("tools", "clock") test.settle(1200)
  test.truthy(test.find { id = "tools-detail-clock", visible = true }, "it did not come back")
  test.eq(#test.logs("error"), 0)
end)

-- ---------------------------------------------------------- the command line --

-- Runs `argv` with the stand-in morf, the shell up or not; what it was asked.
local function cli(argv, up)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/tools-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local full = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "EVA_DRY_RUN=1" }
  if up then full[#full + 1] = "STUB_UP=1" end
  for _, word in ipairs(argv) do full[#full + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(full))
  test.wait(function() return test.ipc("result") end, 8000, "the command answered")
  return morf.fs.read(log) or "", test.ipc("result")
end

test.it("each tool's command alone opens its page", function()
  local pages = { clock = "tools clock", clipboard = "tools clipboard", monitor = "tools monitor", logs = "tools logs",
    disk = "tools disk", phone = "tools phone", messages = "tools messages", pomodoro = "tools pomodoro",
    qr = "tools qr", text = "tools text", translate = "tools translate", webapp = "tools webapp",
    colorpick = "tools colorpick", zoom = "tools zoom", draw = "tools draw", find = "tools find",
    ruler = "tools ruler", kill = "tools kill", screenshot = "tools screenshot",
    keys = "settings input/shortcuts", breaks = "settings breaks" }
  for tool, call in pairs(pages) do
    test.contains(cli({ "sh", ROOT .. "apps/" .. tool .. "/cli" }, true), "ipc call " .. call, tool)
  end
  test.contains(cli({ "sh", ROOT .. "apps/bin/eva-record" }, true), "ipc call tools screenshot")
end)

test.it("with words a tool's command does what it did", function()
  test.contains(cli({ "sh", ROOT .. "apps/disk/cli", "/" }, true), "ipc call tools disk /")
  test.contains(cli({ "sh", ROOT .. "apps/logs/cli", "sshd.service" }, true), "ipc call tools logs sshd.service")
  test.contains(cli({ "sh", ROOT .. "apps/messages/cli", "sms:+31" }, true), "ipc call tools messages sms:+31")
  test.contains(cli({ "sh", ROOT .. "apps/draw/cli", "start" }, true), "app " .. ROOT .. "apps/draw/app.lua")
  test.contains(cli({ "sh", ROOT .. "apps/find/cli", "--spotlight" }, true), "app " .. ROOT .. "apps/find/app.lua")
  test.contains(cli({ "sh", ROOT .. "apps/colorpick/cli", "--pick" }, true), "apps/colorpick/app.lua -- --pick")
  test.contains(cli({ "sh", ROOT .. "apps/clipboard/cli", "--watch" }, true), "apps/clipboard/app.lua -- --watch")
  test.contains(cli({ "sh", ROOT .. "apps/kill/cli", "--pick" }, true), "ipc call kill_mode")
end)

test.it("with no shell, an overlay's command alone draws as it did, and a page's says why not", function()
  test.contains(cli { "sh", ROOT .. "apps/draw/cli" }, "app " .. ROOT .. "apps/draw/app.lua")
  test.contains(cli { "sh", ROOT .. "apps/ruler/cli" }, "app " .. ROOT .. "apps/ruler/app.lua")
  local _, result = cli { "sh", ROOT .. "apps/monitor/cli" }
  test.falsy(result.ok)
  test.contains(result.stderr, "Tools is a part of it")
end)

test.it("`eva open` reaches Tools and a tool's page", function()
  test.contains(cli({ "sh", ROOT .. "apps/bin/eva", "open", "tools" }, true), "ipc call tools home")
  test.contains(cli({ "sh", ROOT .. "apps/bin/eva", "open", "tools/translate" }, true), "ipc call tools translate")
  test.contains(cli({ "sh", ROOT .. "apps/bin/eva", "open", "monitor" }, true), "ipc call tools monitor")
  local _, panel = cli({ "sh", ROOT .. "apps/bin/eva", "open", "capture" }, true)
  test.contains(panel.stderr, "dry run: capture open")
end)

-- -------------------------------------------------------------------- the menu --

test.it("the menu holds two of eva's entries; the rest are links, hidden", function()
  local shown, hidden = {}, {}
  for _, folder in ipairs(morf.fs.list(ROOT .. "apps")) do
    local name = tostring(type(folder) == "table" and folder.name or folder)
    for _, entry in ipairs(morf.fs.list(ROOT .. "apps/" .. name) or {}) do
      local file = tostring(type(entry) == "table" and entry.name or entry)
      if file:match("%.desktop$") then
        local text = morf.fs.read(ROOT .. "apps/" .. name .. "/" .. file)
        if text:find("\nNoDisplay=true", 1, true) then
          hidden[#hidden + 1] = file
          test.truthy(text:find("\nMimeType=", 1, true), file .. " is hidden for no handler")
        else shown[#shown + 1] = file end
      end
    end
  end
  table.sort(shown)
  table.sort(hidden)
  test.eq(shown, { "eva-settings.desktop", "eva-tools.desktop" })
  test.eq(hidden, { "eva-disk.desktop", "eva-messages.desktop", "eva-phone.desktop" })
end)
