-- The machine from the search box: processes, ports, man pages, systemd units,
-- SSH hosts, terminal sessions, Nix, password stores, keybindings and drives.
-- Each reads off the loop through a program of the system's; a program that is
-- not installed says so.
local morf = require("morf")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")

local M = {}

local row, note = rows.row, rows.note

local function missing(id, program, material)
  return { note(id, "Needs " .. program, "It is not on your PATH", material) }
end

local function confirmed(id, action)
  return function(...) return require("providers").confirmed(id, action)(...) end
end

--- Signals a process, or logs that it would.
local function signal(pid, name)
  if run.dry() then
    morf.log("info", "eva: launcher (dry run): kill -" .. name .. " " .. tostring(pid))
    return "close"
  end
  local ok, why = morf.process.kill(pid, name)
  if not ok then morf.log("warn", "eva: could not signal " .. tostring(pid) .. ": " .. tostring(why)) end
  return "close"
end
M.signal = signal

-- -------------------------------------------------------------- processes --

local function processes()
  local user = (morf.env and morf.env("USER")) or ""
  return rows.ask_run("ps", "all", { "ps", "-u", user, "-o", "pid=,pcpu=,pmem=,args=" }, function(stdout)
    local list = {}
    for line in stdout:gmatch("[^\n]+") do
      local pid, cpu, mem, args = line:match("^%s*(%d+)%s+([%d.]+)%s+([%d.]+)%s+(.+)$")
      local program = args and args:match("^(%S+)")
      if program and program:sub(1, 1) ~= "[" then
        local name = program:match("([^/]+)$") or program
        local shown = name .. args:sub(#program + 1)
        list[#list + 1] = { pid = tonumber(pid), cpu = tonumber(cpu), mem = tonumber(mem), args = shown,
          name = name, description = shown }
      end
    end
    table.sort(list, function(a, b) return a.cpu > b.cpu end)
    return list
  end, { debounce_ms = 0, ttl_ms = 4000 })
end

registry.mode { id = "kill", name = "Processes", material = "dangerous", shape = "sunny", words = { "kill", "ps", "proc" },
  hint = "kill firefox  ·  end a process of yours", search = function(term)
    local list = processes()
    if not list then return { note("kill", "Reading the processes…", "", "hourglass_top") } end
    local out = {}
    for _, p in ipairs(rows.fuzzy(list, term)) do
      local pid, name = p.pid, p.name
      out[#out + 1] = row {
        id = "process:" .. pid, name = name, material = "memory", tag = tostring(pid), copy = tostring(pid),
        description = ("%.1f%% CPU  ·  %.1f%% memory  ·  %s"):format(p.cpu, p.mem, p.args),
        run = function() return signal(pid, "TERM") end,
        actions = {
          { name = "End it", material = "cancel", run = function() return signal(pid, "TERM") end },
          { name = "Force it to quit", material = "dangerous", run = function() return signal(pid, "KILL") end },
          { name = "End every " .. name, material = "delete_sweep", run = confirmed("killall:" .. name, function()
            for _, other in ipairs(list) do
              if other.name == name then signal(other.pid, "TERM") end
            end
            return "close"
          end) },
        },
      }
      if #out >= 40 then break end
    end
    if #out == 0 then out[1] = note("kill", "No process of yours by that name", term, "memory") end
    return out
  end }

-- ------------------------------------------------------------------ ports --

--- The listening sockets in `ss -H -ltnup` output.
function M.parse_ss(stdout)
  local list = {}
  for line in stdout:gmatch("[^\n]+") do
    local proto, address = line:match("^(%S+)%s+%S+%s+%S+%s+%S+%s+(%S+)")
    local port = address and address:match(":(%d+)$")
    if port then
      local program, pid = line:match('users:%(%("([^"]+)",pid=(%d+)')
      list[#list + 1] = { proto = proto, port = port, address = address, program = program, pid = tonumber(pid),
        name = ":" .. port .. "  " .. (program or "someone else's"), description = proto .. "  ·  " .. address }
    end
  end
  table.sort(list, function(a, b) return tonumber(a.port) < tonumber(b.port) end)
  return list
end

registry.mode { id = "port", name = "Ports", material = "lan", shape = "square", words = { "port", "ports" },
  hint = "port 8080  ·  who listens, and end it", search = function(term)
    if not run.has("ss") then return missing("port", "ss, from iproute2", "lan") end
    local list = rows.ask_run("ports", "all", { "ss", "-H", "-ltnup" }, M.parse_ss, { debounce_ms = 0, ttl_ms = 3000 })
    if not list then return { note("port", "Reading the ports…", "", "hourglass_top") } end
    local out = {}
    for _, p in ipairs(list) do
      if term == "" or p.port:find(term, 1, true) or (p.program or ""):lower():find(term:lower(), 1, true) then
        local pid = p.pid
        out[#out + 1] = row {
          id = "port:" .. p.proto .. p.address, name = p.name, material = "lan", copy = p.port,
          description = p.description .. (pid and ("  ·  pid " .. pid .. "  ·  Return ends it") or "  ·  needs root to end"),
          run = function()
            if pid then return signal(pid, "TERM") end
            return "keep"
          end,
          actions = pid and { { name = "Force it to quit", material = "dangerous", run = function() return signal(pid, "KILL") end } } or nil,
        }
      end
    end
    if #out == 0 then out[1] = note("port", "Nothing listening there", term, "lan") end
    return out
  end }

-- -------------------------------------------------------------- man pages --

--- The entries in `man -k` output.
function M.parse_man(stdout)
  local list = {}
  for line in stdout:gmatch("[^\n]+") do
    local names, section, what = line:match("^(.-)%s*%((%w+)%)%s+%-%s+(.*)$")
    if names then
      list[#list + 1] = { page = names:match("^([^,%s]+)"), section = section, what = what }
    end
  end
  return list
end

registry.mode { id = "man", name = "Manual", material = "menu_book", shape = "pill", words = { "man", "manual" },
  hint = "man tar  ·  apropos on your manual pages", search = function(term)
    if term == "" then return { note("man", "Type a command or a topic", "man tar  ·  man socket", "menu_book") } end
    if not run.has("man") then return missing("man", "man", "menu_book") end
    local list = rows.ask_run("man", term, { "man", "-k", "--", term }, M.parse_man, { any_exit = true, timeout_ms = 4000 })
    local out = {}
    for _, page in ipairs(list or {}) do
      local argv = { "man", page.section, page.page }
      out[#out + 1] = row {
        id = "man:" .. page.section .. ":" .. page.page, name = page.page .. " (" .. page.section .. ")",
        description = page.what, material = "menu_book", tag = "Manual", copy = page.page,
        preview = { command = { "man", "-P", "cat", page.section, page.page }, env = { MANWIDTH = "60" },
          title = page.page .. " (" .. page.section .. ")" },
        run = function() return run.terminal(argv) end,
      }
      if #out >= 30 then break end
    end
    if #out == 0 then
      out[1] = list and row { id = "man", name = "man " .. term, description = "Open it in a terminal", material = "menu_book",
        run = function() return run.terminal { "man", term } end }
        or note("man", "Looking…", term, "hourglass_top")
    end
    return out
  end }

-- ---------------------------------------------------------------- systemd --

--- Units from `list-units` then, after a `---` line, `list-unit-files`.
function M.parse_units(stdout, scope)
  local list, by_name = {}, {}
  local files = false
  for line in stdout:gmatch("[^\n]+") do
    if line == "---" then
      files = true
    elseif files then
      local name, state = line:match("^(%S+)%s+(%S+)")
      if name then
        local unit = by_name[name]
        if not unit and not name:find("@%.") then
          unit = { name = name, scope = scope, load = "", active = "inactive", sub = "dead", what = "" }
          by_name[name] = unit
          list[#list + 1] = unit
        end
        if unit then unit.state = state end
      end
    else
      local name, load, active, sub, what = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(.*)$")
      if name then
        local unit = { name = name, scope = scope, load = load, active = active, sub = sub, what = what }
        by_name[name] = unit
        list[#list + 1] = unit
      end
    end
  end
  return list
end

local function units_of(scope)
  local flag = scope == "user" and "--user" or "--system"
  local base = "systemctl " .. flag .. " --no-pager --no-legend --plain "
  local script = base .. "list-units --all --type=service,timer,socket; echo ---; " .. base .. "list-unit-files --type=service,timer,socket"
  return rows.ask_run("units-" .. scope, "all", { "sh", "-c", script }, function(stdout)
    return M.parse_units(stdout, scope)
  end, { debounce_ms = 0, ttl_ms = 5000, any_exit = true })
end

local function unit_rows(term)
  local all = {}
  for _, scope in ipairs { "user", "system" } do
    for _, unit in ipairs(units_of(scope) or {}) do all[#all + 1] = unit end
  end
  local list = {}
  for _, unit in ipairs(all) do
    unit.description = unit.what
    list[#list + 1] = unit
  end
  local out = {}
  for _, unit in ipairs(rows.fuzzy(list, term)) do
    local flag = unit.scope == "user" and "--user" or "--system"
    local function ctl(verb)
      return function() run.start { "systemctl", flag, verb, unit.name } return "close" end
    end
    local running = unit.active == "active"
    out[#out + 1] = row {
      id = "unit:" .. unit.scope .. ":" .. unit.name, name = unit.name, tag = unit.scope,
      description = unit.active .. " (" .. unit.sub .. ")" .. (unit.state and ("  ·  " .. unit.state) or "")
        .. (unit.what ~= "" and ("  ·  " .. unit.what) or ""),
      material = running and "play_circle" or "stop_circle", copy = unit.name,
      preview = { command = { "systemctl", flag, "status", "--no-pager", "--lines=20", unit.name }, title = unit.name },
      run = function() return run.terminal { "sh", "-c", 'systemctl ' .. flag .. ' status "$1"; printf "\\n[done] "; read _', "sh", unit.name } end,
      actions = {
        { name = running and "Stop it" or "Start it", material = running and "stop" or "play_arrow", run = ctl(running and "stop" or "start") },
        { name = "Restart it", material = "restart_alt", run = ctl("restart") },
        { name = unit.state == "enabled" and "Disable it" or "Enable it", material = "toggle_on",
          run = ctl(unit.state == "enabled" and "disable" or "enable") },
        { name = "Follow its log", material = "article", run = function()
          return run.terminal { "journalctl", flag == "--user" and "--user-unit" or "--unit", unit.name, "--follow" }
        end },
      },
    }
    if #out >= 40 then break end
  end
  if #out == 0 then out[1] = note("unit", #all == 0 and "Reading the units…" or "No unit by that name", term, "settings_applications") end
  return out
end

registry.mode { id = "units", name = "Services", material = "settings_applications", shape = "square",
  words = { "unit", "units", "service", "systemd" }, hint = "unit nginx  ·  start, stop and read services",
  search = function(term)
    if not run.has("systemctl") then return missing("units", "systemctl", "settings_applications") end
    return unit_rows(term)
  end }

-- -------------------------------------------------------------------- ssh --

local ssh = require("lib.shell.launcher.sshconfig")

registry.mode { id = "ssh", name = "SSH", material = "terminal", shape = "square", words = { "ssh" },
  hint = "ssh box  ·  your configured and known hosts", search = function(term)
    local list = {}
    for _, host in ipairs(ssh.hosts()) do
      local target = (host.user and (host.user .. "@") or "") .. (host.hostname or host.alias)
      list[#list + 1] = { name = host.alias, description = target .. (host.port and (":" .. host.port) or ""), host = host.alias }
    end
    local seen = {}
    for _, item in ipairs(list) do seen[item.name] = true end
    local ok, known = pcall(morf.fs.read, rows.home .. "/.ssh/known_hosts")
    for _, name in ipairs(ssh.known(ok and known or "")) do
      if not seen[name] then list[#list + 1] = { name = name, description = "Known host", host = name } end
    end
    local out = {}
    for _, item in ipairs(rows.fuzzy(list, term)) do
      local host = item.host
      local function connect() return run.terminal { "ssh", host } end
      local actions = {
        { name = "Connect", material = "terminal", run = connect },
        { name = "Copy the command", material = "content_copy", run = function() return run.copy("ssh " .. host) end },
        { name = "Browse its files", material = "folder_open", run = function() return run.open("sftp://" .. host) end },
      }
      if run.has("mosh") then
        table.insert(actions, 2, { name = "Connect with mosh", material = "terminal", run = function() return run.terminal { "mosh", host } end })
      end
      out[#out + 1] = row { id = "ssh:" .. host, name = host, description = item.description, material = "terminal",
        tag = "SSH", pin = "cmd:ssh " .. host, run = connect, actions = actions }
    end
    if #out == 0 then
      if term ~= "" then
        return { row { id = "ssh", name = "ssh " .. term, description = "Connect in a terminal", material = "terminal",
          run = function() return run.terminal { "ssh", term } end } }
      end
      out[1] = note("ssh", "No hosts yet", "From ~/.ssh/config and known_hosts", "terminal")
    end
    return out
  end }

-- ---------------------------------------------------------------- sessions --

registry.mode { id = "tmux", name = "Terminal sessions", material = "view_quilt", shape = "square", words = { "tmux", "zellij" },
  hint = "tmux work  ·  attach, or make a session", search = function(term)
    local out = {}
    if run.has("tmux") then
      local sessions = rows.ask_run("tmux", "all", { "tmux", "list-sessions", "-F", "#S\t#{session_windows}\t#{session_attached}" },
        function(stdout)
          local list = {}
          for line in stdout:gmatch("[^\n]+") do
            local name, windows, attached = line:match("^([^\t]*)\t(%d+)\t(%d+)$")
            if name then
              list[#list + 1] = { name = name, description = windows .. " windows" .. (attached ~= "0" and "  ·  attached" or "") }
            end
          end
          return list
        end, { debounce_ms = 0, ttl_ms = 3000 })
      for _, s in ipairs(rows.fuzzy(sessions or {}, term)) do
        out[#out + 1] = row { id = "tmux:" .. s.name, name = s.name, description = s.description, material = "view_quilt", tag = "tmux",
          run = function() return run.terminal { "tmux", "attach", "-t", s.name } end,
          actions = { { name = "End the session", material = "close",
            run = function() run.start { "tmux", "kill-session", "-t", s.name } return "close" end } } }
      end
      if term ~= "" then
        out[#out + 1] = row { id = "tmux:new", name = "New session “" .. term .. "”", material = "add", description = "tmux",
          run = function() return run.terminal { "tmux", "new-session", "-A", "-s", term } end }
      end
    end
    if run.has("zellij") then
      local sessions = rows.ask_run("zellij", "all", { "zellij", "list-sessions", "--no-formatting", "--short" }, function(stdout)
        local list = {}
        for name in stdout:gmatch("[^\n]+") do list[#list + 1] = { name = name } end
        return list
      end, { debounce_ms = 0, ttl_ms = 3000 })
      for _, s in ipairs(rows.fuzzy(sessions or {}, term)) do
        out[#out + 1] = row { id = "zellij:" .. s.name, name = s.name, description = "zellij", material = "view_quilt", tag = "zellij",
          run = function() return run.terminal { "zellij", "attach", s.name } end }
      end
    end
    if #out == 0 then return missing("tmux", "tmux or zellij", "view_quilt") end
    return out
  end }

-- -------------------------------------------------------------------- nix --

--- The packages in `nix search --json`: `{ attr, pname, version, description }`.
function M.parse_nix(stdout)
  local ok, data = pcall(morf.json.decode, stdout)
  local out = {}
  if not ok or type(data) ~= "table" then return out end
  for key, value in pairs(data) do
    local attr = key:match("^legacyPackages%.[^.]+%.(.+)$") or key:match("^packages%.[^.]+%.(.+)$") or key
    out[#out + 1] = { attr = attr, name = attr, version = tostring(value.version or ""),
      description = tostring(value.description or "") }
  end
  table.sort(out, function(a, b) return #a.attr < #b.attr or (#a.attr == #b.attr and a.attr < b.attr) end)
  return out
end

registry.mode { id = "nix", name = "Nix packages", material = "deployed_code", shape = "cookie9", words = { "nix", "nixpkgs" },
  hint = "nix ripgrep  ·  Return: nix run", search = function(term)
    if term == "" then return { note("nix", "Type a package", "Searches nixpkgs; the first search takes a while", "deployed_code") } end
    if not run.has("nix") then return missing("nix", "nix", "deployed_code") end
    -- The answer alone: stderr goes to /dev/null.
    local list, settled = rows.ask_run("nix", term,
      { "sh", "-c", 'exec nix --extra-experimental-features "nix-command flakes" search nixpkgs "$1" --json 2>/dev/null', "sh", term },
      M.parse_nix, { debounce_ms = 500, timeout_ms = 120000, any_exit = true })
    local out = {}
    for _, p in ipairs(list or {}) do
      local flake = "nixpkgs#" .. p.attr
      out[#out + 1] = row {
        id = "nix:" .. p.attr, name = p.attr, description = p.version .. "  ·  " .. p.description, material = "deployed_code",
        tag = "Nix", copy = flake,
        run = function() return run.terminal { "nix", "run", flake } end,
        actions = {
          { name = "Run it", material = "play_arrow", run = function() return run.terminal { "nix", "run", flake } end },
          { name = "Open a shell with it", material = "terminal", run = function() return run.terminal { "nix", "shell", flake } end },
          { name = "Install it in your profile", material = "download", run = function()
            return run.terminal { "sh", "-c", 'nix profile install "$1"; printf "\\n[done] "; read _', "sh", flake }
          end },
          { name = "Copy nix run", material = "content_copy", run = function() return run.copy("nix run " .. flake) end },
          { name = "Copy nix-shell", material = "content_copy", run = function() return run.copy("nix-shell -p " .. p.attr) end },
        },
      }
      if #out >= 40 then break end
    end
    if #out == 0 then out[1] = note("nix", settled and "No package by that name" or "Searching nixpkgs…", term, "deployed_code") end
    return out
  end }

-- --------------------------------------------------------------- get apps --

-- Something to install as a row: Return arms it, a second Return installs it.
local function installable(item, tag, detail)
  local providers = require("providers")
  local id = "get:" .. item.backend .. ":" .. item.id
  local confirm = providers.confirmed(id, function()
    require("software_model").install(item)
    return "close"
  end)
  return row { id = id, name = item.name, tag = tag, material = "download",
    description = providers.armed(id) and "Press again to install" or detail, run = confirm }
end

registry.mode { id = "get", name = "Get apps", material = "add_circle", shape = "cookie9", words = { "get", "install" }, bare = false,
  hint = "get a chess game  ·  from what this machine installs with", search = function(term)
    local software = require("lib.services.software")
    local machine = software.machine()
    if not machine.flatpak and not machine.nix then
      return { note("get", "Nothing here installs apps", "This machine has neither Flatpak nor Nix", "block") }
    end
    if term == "" then return { note("get", "Type what you are after", "Finds apps to install", "add_circle") } end
    local out, settled = {}, true
    if machine.flatpak then
      local list, done = rows.ask_run("get-flatpak", term, software.flatpak_search(term), software.parse_flatpak,
        { debounce_ms = 400, timeout_ms = 30000, any_exit = true })
      settled = settled and done
      for _, item in ipairs(list or {}) do
        if #out < 20 then out[#out + 1] = installable(item, "Flatpak", item.version .. "  ·  " .. item.description) end
      end
    end
    if machine.nix then
      local argv = software.nix("search", "nixpkgs", term, "--json")
      local list, done = rows.ask_run("get-nix", term, argv, M.parse_nix, { debounce_ms = 500, timeout_ms = 120000, any_exit = true })
      settled = settled and done
      for _, package in ipairs(list or {}) do
        if #out < 40 then
          local item = { backend = "nix", id = package.attr, name = package.attr }
          out[#out + 1] = installable(item, "Nix", package.version .. "  ·  " .. package.description)
        end
      end
    end
    if #out == 0 then out[1] = note("get", settled and "Nothing by that name" or "Searching…", term, "add_circle") end
    return out
  end }

-- ---------------------------------------------------------- password stores --

-- A password stays with its tool: `pass -c` copies it, and rbw's goes straight
-- from its stdout to a marked clipboard.
local function vault_rows(term)
  local out = {}
  if run.has("pass") then
    local base = (morf.env and morf.env("PASSWORD_STORE_DIR")) or (rows.home .. "/.password-store")
    local list = rows.ask_run("pass", base, { "sh", "-c", 'cd "$1" 2>/dev/null && find . -name "*.gpg" -type f', "sh", base }, function(stdout)
      local names = {}
      for line in stdout:gmatch("[^\n]+") do names[#names + 1] = { name = line:gsub("^%./", ""):gsub("%.gpg$", "") } end
      table.sort(names, function(a, b) return a.name < b.name end)
      return names
    end, { debounce_ms = 0, ttl_ms = 30000, any_exit = true })
    for _, entry in ipairs(rows.fuzzy(list or {}, term, "name")) do
      out[#out + 1] = row { id = "pass:" .. entry.name, name = entry.name, description = "pass  ·  Return copies it", material = "key",
        private = true, tag = "pass", run = function() run.start { "pass", "show", "--clip", entry.name } return "close" end,
        actions = { { name = "Copy its name", material = "content_copy", run = function() return run.copy(entry.name) end } } }
      if #out >= 40 then break end
    end
  end
  if run.has("rbw") then
    local list = rows.ask_run("rbw", "all", { "rbw", "list" }, function(stdout)
      local names = {}
      for line in stdout:gmatch("[^\n]+") do names[#names + 1] = { name = line } end
      return names
    end, { debounce_ms = 0, ttl_ms = 60000, any_exit = true })
    for _, entry in ipairs(rows.fuzzy(list or {}, term, "name")) do
      out[#out + 1] = row { id = "rbw:" .. entry.name, name = entry.name, description = "Bitwarden  ·  Return copies it", material = "key",
        private = true, tag = "rbw",
        run = function() run.start { "sh", "-c", 'rbw get "$1" | wl-copy --sensitive', "sh", entry.name } return "close" end }
      if #out >= 40 then break end
    end
  end
  return out
end

registry.mode { id = "vault", name = "Passwords", material = "key", shape = "pill", words = { "vault", "secret" },
  hint = "vault github  ·  from pass or rbw", search = function(term)
    if not (run.has("pass") or run.has("rbw")) then return missing("vault", "pass or rbw", "key") end
    local out = vault_rows(term)
    if #out == 0 then out[1] = note("vault", "Nothing by that name", term, "key") end
    return out
  end }

-- ------------------------------------------------------------- keybindings --

registry.mode { id = "keys", name = "Key bindings", material = "keyboard", shape = "pill", words = { "keys", "bind", "binds", "shortcut" },
  hint = "keys screenshot  ·  what a key does", search = function(term)
    local binds = rows.ask_run("binds", "all", { "hyprctl", "binds", "-j" }, function(stdout)
      local ok, list = pcall(morf.json.decode, stdout)
      return ok and type(list) == "table" and list or {}
    end, { debounce_ms = 0, ttl_ms = 30000, any_exit = true })
    local list = {}
    for _, bind in ipairs(require("key_rows").merge(binds or {})) do
      list[#list + 1] = { name = bind.what, description = bind.keys .. "  ·  " .. bind.group, keys = bind.keys }
    end
    local out = {}
    for i, b in ipairs(rows.fuzzy(list, term)) do
      out[#out + 1] = rows.copy("bind:" .. i, b.name, b.description, "keyboard", b.keys)
      if #out >= 40 then break end
    end
    if #out == 0 then out[1] = note("keys", "No binding like that", term, "keyboard") end
    return out
  end }

-- ------------------------------------------------------------------ drives --

--- The removable partitions in `lsblk -J` output.
function M.parse_lsblk(stdout)
  local ok, data = pcall(morf.json.decode, stdout)
  local out = {}
  if not ok or type(data) ~= "table" then return out end
  local function walk(devices, removable)
    for _, d in ipairs(devices or {}) do
      local away = removable or d.rm == true or d.hotplug == true or d.rm == "1"
      if d.type == "part" and away then
        out[#out + 1] = { device = "/dev/" .. d.name, label = d.label, size = d.size,
          mount = d.mountpoint ~= morf.json.null and d.mountpoint or nil }
      end
      walk(d.children, away)
    end
  end
  walk(data.blockdevices, false)
  return out
end

registry.mode { id = "drives", name = "Drives", material = "usb", shape = "pill", words = { "mount", "usb", "drive" },
  hint = "removable drives: open, mount, eject", search = function(term)
    if not run.has("lsblk") then return missing("drives", "lsblk", "usb") end
    local list = rows.ask_run("drives", "all", { "lsblk", "-J", "-o", "NAME,LABEL,SIZE,MOUNTPOINT,RM,HOTPLUG,TYPE" }, M.parse_lsblk,
      { debounce_ms = 0, ttl_ms = 2000, any_exit = true })
    local items = {}
    for _, d in ipairs(list or {}) do
      items[#items + 1] = { drive = d, name = d.label ~= morf.json.null and d.label or d.device, description = tostring(d.size or "") }
    end
    local out = {}
    for _, item in ipairs(rows.fuzzy(items, term)) do
      local d = item.drive
      local actions = {}
      if d.mount then
        actions[1] = { name = "Unmount it", material = "eject",
          run = function() run.start { "udisksctl", "unmount", "--block-device", d.device } return "close" end }
      end
      out[#out + 1] = row { id = "drive:" .. d.device, name = item.name, tag = "Drive", material = "usb",
        description = item.description .. "  ·  " .. (d.mount or "not mounted"), actions = actions,
        run = function()
          if d.mount then return run.open(d.mount) end
          run.start { "udisksctl", "mount", "--block-device", d.device }
          return "close"
        end }
    end
    if #out == 0 then out[1] = note("drives", "No removable drives", "Plug one in", "usb") end
    return out
  end }

-- ---------------------------------------------------------------- qalc --

--- What `qalc` makes of a sum eva's own calculator cannot read; nil until it
--- answers, or without qalc.
function M.qalc(text)
  if not run.has("qalc") then return nil end
  local answer = rows.ask_run("qalc", text, { "qalc", "-t", text }, function(stdout)
    return (stdout:match("^%s*(.-)%s*$"))
  end, { timeout_ms = 3000, debounce_ms = 200, failed = "" })
  if answer and answer ~= "" then return answer end
  return nil
end

return M
