-- What every tool of apps/ asks of the machine, each behind one door that
-- honours EVA_DRY_RUN: running a program, a file of JSON in eva's state folder,
-- the clipboard, a notification, which compositor this is. No nodes.
local morf = require("morf")

local M = {}

--- Whether actions on the machine are held back.
function M.dry()
  local value = morf.env("EVA_DRY_RUN")
  return value ~= nil and value ~= "" and value ~= "0"
end

--- eva's state folder, or a path under it.
function M.state(...)
  local root = (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva"
  local parts = { root, ... }
  return table.concat(parts, "/")
end

--- `path` as JSON, or `default` where it is missing or broken.
function M.load(path, default)
  local ok, value = pcall(function() return morf.json.decode(morf.fs.read(path)) end)
  if ok and value ~= nil then return value end
  return default
end

--- Writes `value` to `path` as JSON, atomically; `mode` is the file's (private
--- by default).
function M.save(path, value, mode)
  return morf.fs.write(path, morf.json.encode(value), { atomic = true, parents = true, mode = mode or 384 })
end

--- Whether `program` is on PATH.
function M.has(program)
  for dir in ((morf.env("PATH") or "") .. ":/usr/bin:/usr/local/bin"):gmatch("[^:]+") do
    if morf.fs.exists(dir .. "/" .. program) then return true end
  end
  return false
end

--- Runs `argv`, `done(result)` after it. Dry, an action is logged and `done`
--- hears `{ ok = false, dry = true }`; `read = true` in `options` marks a
--- command that only reads, which runs even then.
function M.run(argv, options, done)
  options = options or {}
  local read = options.read
  local run_options = {}
  for key, value in pairs(options) do
    if key ~= "read" then run_options[key] = value end
  end
  if M.dry() and not read then
    morf.log("info", "eva: " .. table.concat(argv, " ") .. " (dry run)")
    if done then done { ok = false, dry = true, stdout = "", stderr = "" } end
    return nil
  end
  return morf.process.run(argv, run_options, done or function() end)
end

--- Starts `argv` to outlive this tool.
function M.detach(argv)
  if M.dry() then
    morf.log("info", "eva: " .. table.concat(argv, " ") .. " (dry run)")
    return
  end
  morf.process.detach(argv)
end

--- `text` on the clipboard.
function M.copy(text)
  if M.dry() then return end
  morf.clipboard.set(text)
end

--- A notification, through the server the shell runs.
function M.notify(summary, body, urgency)
  local argv = { "notify-send", "--app-name=eva", "--urgency=" .. (urgency or "normal"), summary }
  if body and body ~= "" then argv[#argv + 1] = body end
  M.run(argv)
end

--- Which compositor this session has: "hyprland", "sway" or "other".
function M.compositor()
  if morf.env("HYPRLAND_INSTANCE_SIGNATURE") then return "hyprland" end
  if morf.env("SWAYSOCK") then return "sway" end
  return "other"
end

--- Calls `verb` of the running shell: `done(reply, why)`, `reply` nil where no
--- shell answers. `options.read` marks a verb that changes nothing.
function M.shell(words, options, done)
  local argv = { "env", "-u", "MORF_APP", morf.env("MORF") or "morf", "ipc", "call" }
  for _, word in ipairs(words) do argv[#argv + 1] = tostring(word) end
  M.run(argv, { read = options and options.read, timeout_ms = 3000 }, function(result)
    if not done then return end
    if not result.ok then done(nil, result.dry and "dry run" or "The shell is not running") return end
    local ok, reply = pcall(morf.json.decode, result.stdout or "")
    if ok and type(reply) == "table" and reply.result ~= nil then done(reply.result) return end
    done(ok and reply or true)
  end)
end

return M
