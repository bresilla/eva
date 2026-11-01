-- What a launcher row does to the machine: starts a program detached from the
-- shell, opens a target, copies text, runs something in a terminal. With
-- EVA_DRY_RUN set each of them logs what it would do instead.
--
-- A run returns what the launcher does next: "close", "keep", or a new query.

local morf = require("morf")

local M = {}

--- Whether nothing may reach the machine.
function M.dry()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return (v and v ~= "" and v ~= "0") and true or false
end

local function logged(what, words)
  morf.log("info", "eva: launcher (dry run): " .. what .. " " .. table.concat(words, " "))
end

--- Starts `argv` detached, its output on /dev/null.
function M.start(argv)
  if M.dry() then logged("start", argv) return end
  local detached = { "setsid", "-f", "sh", "-c", 'exec "$@" </dev/null >/dev/null 2>&1', "sh" }
  for _, word in ipairs(argv) do detached[#detached + 1] = word end
  morf.process.run(detached, {}, function(result)
    if result and not result.ok then
      morf.log("warn", "eva: could not start " .. tostring(argv[1]) .. ": " .. tostring(result.stderr or result.code))
    end
  end)
end

--- Whether `program` is on PATH.
function M.has(program)
  local path = (morf.env and morf.env("PATH")) or ""
  for folder in path:gmatch("[^:]+") do
    if morf.fs.is_file(folder .. "/" .. program) then return true end
  end
  return false
end

-- Terminals that run their arguments as they stand; the others take `-e`.
local BARE = { kitty = true, foot = true }
local KNOWN = { "kitty", "foot", "alacritty", "wezterm", "ghostty", "xterm" }

--- The terminal: the setting `launcher.terminal` (a list of words), then
--- $TERMINAL, then the first one installed.
function M.terminal_words()
  local ok, words = pcall(function() return require("config").get("launcher.terminal") end)
  if ok and type(words) == "table" and #words > 0 then return words end
  local name = morf.env and morf.env("TERMINAL")
  if name and name ~= "" then return { name } end
  for _, known in ipairs(KNOWN) do
    if M.has(known) then return { known } end
  end
  return { "kitty" }
end

--- Runs `argv` in a terminal, or a bare terminal without one; `cwd` is
--- where it starts. Returns "close".
function M.terminal(argv, cwd)
  local words = M.terminal_words()
  local cmd = {}
  for i, w in ipairs(words) do cmd[i] = w end
  local base = tostring(words[1]):match("([^/]+)$")
  local inner = argv or {}
  if cwd then
    inner = { "sh", "-c", 'cd "$1" && shift; [ "$#" -gt 0 ] && exec "$@"; exec "${SHELL:-sh}"', "sh", cwd,
      table.unpack(argv or {}) }
  end
  if #inner > 0 then
    if not BARE[base] then cmd[#cmd + 1] = "-e" end
    for _, w in ipairs(inner) do cmd[#cmd + 1] = w end
  end
  M.start(cmd)
  return "close"
end

--- Runs a line of shell in a terminal, which stays up until a key.
function M.shell_terminal(line)
  return M.terminal { "sh", "-c", line .. '; printf "\\n[done] "; read _' }
end

--- Puts `text` on the clipboard. Returns "close".
function M.copy(text)
  pcall(morf.clipboard.set, tostring(text))
  return "close"
end

--- Puts a secret on the clipboard, marked as a password manager marks it so
--- no history keeps it. It travels on stdin, never in an argument.
function M.copy_secret(text)
  if M.dry() then morf.log("info", "eva: launcher (dry run): copied a secret") return "close" end
  if M.has("wl-copy") then
    morf.process.run({ "wl-copy", "--sensitive" }, { stdin = tostring(text) }, function() end)
  else
    pcall(morf.clipboard.set, tostring(text))
  end
  return "close"
end

--- Opens `target` with its default application. Returns "close".
function M.open(target)
  M.start { "xdg-open", target }
  return "close"
end

--- Opens `url` in $BROWSER. Returns "close".
function M.browse(url)
  M.start { require("web").browser(), url }
  return "close"
end

--- The focused application given Ctrl+V once the launcher has let the
--- keyboard go.
function M.paste()
  if M.dry() then morf.log("info", "eva: launcher (dry run): paste") return end
  morf.time.timer(120, function()
    if M.has("wtype") then
      morf.process.run({ "wtype", "-M", "ctrl", "-k", "v", "-m", "ctrl" }, {}, function() end)
    end
  end, false)
end

return M
