-- The shell's side of eva-screenshot: asking it, and showing what it says. The
-- panel, the selection, the editor and the recorder are the tool's, in a
-- process of its own (apps/screenshot). It publishes its state to a file; the
-- signals here follow that file.
local morf = require("morf")
local config = require("config")
local M = {
  panel = morf.signal("eva.capture.panel", false),
  editing = morf.signal("eva.capture.editing", false),
  phase = morf.signal("eva.capture.phase", "ready"),
  recording = morf.signal("eva.capture.recording", false),
  elapsed = morf.signal("eva.capture.elapsed", 0),
  target = morf.signal("eva.capture.target", "region"),
}
local started, pid, ticker = 0, nil, nil

local function dry_run()
  local v = morf.env("EVA_DRY_RUN")
  return v and v ~= "" and v ~= "0"
end

-- The tool's front door: `EVA_SCREENSHOT_TOOL`, beside the shell in a checkout,
-- else on PATH.
local function front_door()
  local named = morf.env("EVA_SCREENSHOT_TOOL")
  if named and named ~= "" then return { named } end
  local beside = morf.paths.shell() .. "/../apps/screenshot/cli"
  if morf.fs.exists(beside) then return { "sh", beside } end
  return { "eva-screenshot" }
end

--- Tells the tool a verb, starting it when it is not running.
function M.ask(...)
  local words = { ... }
  if dry_run() then
    morf.log("info", "eva: capture " .. table.concat(words, " ") .. " (dry run)")
    return true
  end
  local argv = front_door()
  argv[#argv + 1] = "--ask"
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  local ok, why = pcall(morf.process.detach, argv)
  if not ok then morf.log("warn", "eva: capture tool: " .. tostring(why)) end
  return ok
end

local function busy()
  local phase = M.phase:get()
  return phase ~= "ready" and phase ~= "error"
end

local function checked(what)
  if what ~= nil and what ~= "region" and what ~= "window" and what ~= "screen" then
    error("Choose region, window or screen")
  end
end

--- A running panel or editor let go; false when there is none.
function M.cancel()
  if not M.editing:get() and not busy() then return false end
  M.ask("capture-editor", "cancel")
  return true
end

function M.shoot(what, quick)
  checked(what)
  if busy() then return "busy" end
  local words = { "screenshot" }
  if what then words[#words + 1] = what end
  if quick then words[#words + 1] = "quick" end
  M.ask(table.unpack(words))
  return what or M.target:get()
end

function M.record(what)
  checked(what)
  if busy() and not M.recording:get() then return "busy" end
  if what then M.ask("record", what) else M.ask("record") end
  return M.recording:get() and "stopped" or what or M.target:get()
end

-- What the shell's callers hold of the panel and the editor.
M.drawer = {
  open = M.panel,
  set = function(on)
    if on then M.ask("capture", "open")
    elseif M.panel:get() then M.ask("capture", "close") end
  end,
  toggle = function() M.ask("capture", "toggle") end,
  is_open = function() return M.panel:get() end,
}
M.editor = {
  active = M.editing,
  running = function() return M.editing:get() end,
}

local state_path = require("capture_state").path

local function alive()
  return pid ~= nil and morf.fs.is_dir("/proc/" .. tostring(pid))
end

local function count()
  M.elapsed:set(math.max(0, (morf.time.now_ms() - started) // 1000))
end

local function apply(state)
  pid = state and state.pid or nil
  if not alive() then state = {} end
  started = state.started or 0
  M.panel:set(state.panel == true)
  M.editing:set(state.editing == true)
  M.phase:set(state.phase or "ready")
  M.target:set(state.target or M.target:get())
  M.recording:set(state.recording == true)
end

local function read()
  local ok, text = pcall(morf.fs.read, state_path())
  if not ok or type(text) ~= "string" then apply(nil) return end
  local fine, state = pcall(morf.json.decode, text)
  apply(fine and type(state) == "table" and state or nil)
end

M.watch = morf.fs.watch(state_path(), read)
read()

-- The clock while a recording runs, and the tool's going noticed.
morf.effect("eva.capture.clock", function()
  if M.recording:get() then
    count()
    if not ticker then
      ticker = morf.time.timer(1000, function()
        if alive() then count() else apply(nil) end
      end, true)
    end
  elseif ticker then
    ticker:cancel() ticker = nil
    M.elapsed:set(0)
  end
end)

require("lib.shell.capture.hotkey").follow(config)

-- On a real session the tool hears the shell is here, and is ready ahead of the
-- first key, a moment after the shell has come up.
local session = not dry_run() and not (morf.capabilities and morf.capabilities.headless)
if session and (not morf.window.primary or morf.window.primary()) then
  morf.fs.write(require("capture_state").shell_path(), tostring(morf.process_id), { atomic = true, parents = true })
  morf.time.timer(2500, function() M.ask("standby") end, false)
end

return M
