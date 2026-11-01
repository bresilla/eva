-- Snapshots and backups, over whichever of snapper, btrbk and restic this
-- machine has: what exists, making one, and getting one file back. Everything
-- goes through lib/services/host.lua, so a preview and the stand-in machine
-- touch nothing. A restic password stays in the file the setting names: only
-- that path reaches the command, in its environment.
--
--   backups.available()                     -- { { id, name } }
--   backups.list(tool, function(rows, why) end)   -- newest first
--   backups.create(tool, function(ok, why) end)
--   backups.restore(tool, row, path, "copy"|"replace", function(where, why) end)
--
-- A row: `{ id, when, title, detail, root, base, tag }`: `root` is the folder the
-- snapshot holds, and `base` where that folder stands in it.
local morf = require("morf")
local config = require("config")
local host = require("lib.services.host")

local M = { COPY_SUFFIX = ".restored" }

local NAMES = { snapper = "Snapper", btrbk = "btrbk", restic = "restic" }

--- The tools here, in the order they are offered.
function M.available()
  local out = {}
  for _, id in ipairs { "snapper", "btrbk", "restic" } do
    if host.installed(id) then out[#out + 1] = { id = id, name = NAMES[id] } end
  end
  return out
end

--- What each tool needs, for a page with none: on NixOS, the option.
function M.needs()
  if host.nixos() then
    return { { "Snapper", "services.snapper.configs, on btrfs" }, { "btrbk", "services.btrbk.instances, on btrfs" },
      { "restic", "services.restic.backups, on anything" } }
  end
  return { { "Snapper", "Install it and make a config, on btrfs" }, { "btrbk", "Install it and write btrbk.conf, on btrfs" },
    { "restic", "Install it and make a repository, on anything" } }
end

local function words(text)
  local out = {}
  for key, value in tostring(text):gmatch("([%w_]+)='([^']*)'") do out[key] = value end
  return out
end

-- ---------------------------------------------------------------- snapper --

local function snapper_config() return tostring(config.get("backups.snapper_config") or "root") end

--- The rows of `snapper --jsonout list`: snapshot 0 is the live system, so it
--- is left out.
function M.parse_snapper(text, name, root)
  local ok, value = pcall(morf.json.decode, text)
  if not ok or type(value) ~= "table" then return nil, "Snapper's list could not be read." end
  local list = value[name] or select(2, next(value))
  local rows = {}
  for _, row in ipairs(type(list) == "table" and list or {}) do
    local number = tonumber(row.number)
    if number and number > 0 then
      local words_of = (row.description or "") ~= "" and row.description or (row.type or "snapshot")
      rows[#rows + 1] = { id = tostring(number), when = tostring(row.date or ""), title = words_of,
        detail = ("Snapshot %d · %s"):format(number, tostring(row.type or "single")),
        root = root, base = root:gsub("/$", "") .. "/.snapshots/" .. number .. "/snapshot" }
    end
  end
  return rows
end

-- Snapper's refusal in a person's words.
local function plainly(why)
  if tostring(why):find("permission", 1, true) or tostring(why):find("No permissions", 1, true) then
    return "Snapper does not let you read this. Add yourself to ALLOW_USERS in its config."
  end
  return why
end

local function snapper_root(done)
  host.read({ "snapper", "--jsonout", "list-configs" }, function(text, why)
    if not text then return done(nil, plainly(why)) end
    local ok, value = pcall(morf.json.decode, text)
    local wanted = snapper_config()
    for _, row in ipairs(ok and type(value) == "table" and value.configs or {}) do
      if row.config == wanted then return done(row.subvolume) end
    end
    done(nil, ("Snapper has no config called %s."):format(wanted))
  end)
end

local function snapper_list(done)
  snapper_root(function(root, why)
    if not root then return done(nil, why) end
    host.read({ "snapper", "--jsonout", "-c", snapper_config(), "list" }, function(text, failed)
      if not text then return done(nil, plainly(failed)) end
      done(M.parse_snapper(text, snapper_config(), root))
    end)
  end)
end

-- ------------------------------------------------------------------ btrbk --

--- The rows of `btrbk list snapshots --format=raw`.
function M.parse_btrbk(text)
  local rows = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local fields = words(line)
    local base = fields.snapshot_subvolume
    if base then
      local stamp = fields.snapshot_name or base:match("([^/]+)$") or ""
      local y, m, d, H, N = stamp:match("(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)")
      rows[#rows + 1] = { id = base, when = y and ("%s-%s-%s %s:%s"):format(y, m, d, H, N) or "",
        title = fields.source_subvolume or stamp, detail = stamp, root = fields.source_subvolume or "", base = base }
    end
  end
  return rows
end

-- Lists as this person, or through polkit when `asked`. `done`'s third value
-- says only root could read it.
local function btrbk_list(asked, done)
  local argv = { "btrbk", "list", "snapshots", "--format=raw" }
  if asked then table.insert(argv, 1, "pkexec") end
  host.read(argv, function(text, why)
    if not text then return done(nil, why, not asked) end
    done(M.parse_btrbk(text))
  end)
end

-- ----------------------------------------------------------------- restic --

--- What restic needs to find its repository: a table for `env`, or nil and why.
local function restic_env()
  local repository = tostring(config.get("backups.restic_repository") or "")
  local password = tostring(config.get("backups.restic_password_file") or "")
  if repository == "" then return nil, "Name the restic repository in Backup settings." end
  if password == "" then return nil, "Name the file holding restic's password in Backup settings." end
  return { RESTIC_REPOSITORY = repository, RESTIC_PASSWORD_FILE = (morf.fs.expand(password)) }
end

--- The rows of `restic snapshots --json`.
function M.parse_restic(text)
  local ok, value = pcall(morf.json.decode, text)
  if not ok or type(value) ~= "table" then return nil, "restic's list could not be read." end
  local rows = {}
  for _, row in ipairs(value) do
    local short = row.short_id or tostring(row.id or ""):sub(1, 8)
    rows[#rows + 1] = { id = short, when = tostring(row.time or ""):sub(1, 16):gsub("T", " "),
      title = table.concat(row.paths or {}, ", "), detail = ("%s · %s"):format(short, tostring(row.hostname or "")) }
  end
  return rows
end

local function restic_list(done)
  local env, why = restic_env()
  if not env then return done(nil, why) end
  host.read({ "restic", "snapshots", "--json" }, function(text, failed)
    if not text then return done(nil, failed) end
    done(M.parse_restic(text))
  end, { env = env, timeout_ms = 60000 })
end

-- --------------------------------------------------------------- the whole --

local function newest_first(rows)
  table.sort(rows, function(a, b) return tostring(a.when) > tostring(b.when) end)
  return rows
end

--- `done(rows, why, needs_root)`: what `tool` holds. `asked`: a person pressed
--- for it, so polkit may ask them.
function M.list(tool, done, asked)
  local function answer(rows, why, needs_root)
    if not rows then return done(nil, why, needs_root) end
    done(newest_first(rows))
  end
  if tool == "snapper" then return snapper_list(answer) end
  if tool == "btrbk" then return btrbk_list(asked, answer) end
  return restic_list(answer)
end

--- Makes one now. A btrbk run keeps everything it would have pruned.
function M.create(tool, done)
  if tool == "snapper" then
    return host.act({ "snapper", "-c", snapper_config(), "create", "-d", "Made in Settings" }, done)
  end
  if tool == "btrbk" then return host.act({ "pkexec", "btrbk", "snapshot", "--preserve" }, done) end
  local env, why = restic_env()
  if not env then return done(nil, why) end
  local argv = { "restic", "backup" }
  for _, path in ipairs(config.get("backups.restic_paths") or {}) do argv[#argv + 1] = (morf.fs.expand(path)) end
  if #argv == 2 then return done(nil, "Name what to back up in Backup settings.") end
  host.act(argv, done, { env = env })
end

--- The path `path` has inside snapshot `row`, or nil and why.
function M.inside(row, path)
  local root = tostring(row.root or ""):gsub("/$", "")
  if path:sub(1, #root + 1) ~= root .. "/" then
    return nil, ("That file is not under %s, which this snapshot holds."):format(row.root)
  end
  return tostring(row.base) .. path:sub(#root + 1)
end

--- Where a restored copy of `path` goes.
function M.copy_path(path) return path .. M.COPY_SUFFIX end

local function restic_restore(row, path, how, done)
  local env, why = restic_env()
  if not env then return done(nil, why) end
  if how == "replace" then
    return host.act({ "restic", "restore", row.id, "--target", "/", "--include", path }, function(ok, failed)
      done(ok and path or nil, failed)
    end, { env = env })
  end
  -- It lands under its whole path: moved beside the file, the folder goes.
  local folder = path:match("^(.*)/[^/]*$") .. "/.eva-restore-" .. row.id
  host.act({ "restic", "restore", row.id, "--target", folder, "--include", path }, function(ok, failed)
    if not ok then return done(nil, failed) end
    host.act({ "mv", "-n", folder .. path, M.copy_path(path) }, function(moved, stuck)
      host.act({ "rm", "-rf", folder })
      done(moved and M.copy_path(path) or nil, stuck)
    end)
  end, { env = env })
end

--- Gets `path` back from snapshot `row`: "copy" beside it, or "replace" over
--- it. `done(where, why)`.
function M.restore(tool, row, path, how, done)
  path = tostring(path or ""):match("^%s*(.-)%s*$")
  path = (morf.fs.expand(path))
  if path == "" or path:sub(1, 1) ~= "/" then return done(nil, "Give the file's whole path.") end
  if how == "copy" and morf.fs.exists(M.copy_path(path)) then
    return done(nil, ("%s is already there: move it first."):format(M.copy_path(path)))
  end
  if tool == "restic" then return restic_restore(row, path, how, done) end
  local inside, why = M.inside(row, path)
  if not inside then return done(nil, why) end
  if how == "copy" then
    return host.act({ "cp", "--reflink=auto", "--no-clobber", "--", inside, M.copy_path(path) }, function(ok, failed)
      done(ok and M.copy_path(path) or nil, failed)
    end)
  end
  if tool == "snapper" then
    return host.act({ "snapper", "-c", snapper_config(), "undochange", row.id .. "..0", "--", path }, function(ok, failed)
      done(ok and path or nil, failed)
    end)
  end
  host.act({ "pkexec", "cp", "--reflink=auto", "--", inside, path }, function(ok, failed) done(ok and path or nil, failed) end)
end

return M
