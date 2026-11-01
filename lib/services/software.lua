-- What put each application on this machine, and what could take it off: the
-- system's configuration, a Nix profile, Flatpak, a snap, an AppImage or a file
-- of the person's own. Each kind names the command that does the work, or says
-- in words why there is none. No nodes.
--
--   local software = require("lib.services.software")
--   software.machine()              -- { nixos, nix, flatpak, snap }
--   software.source_of(row)         -- { kind, label, removable, why, argv }
--   software.scan(done)             -- reads the Nix profile; source_of needs it
--   software.remove(row, done)      -- done(text) or done(nil, why)
--   software.install(item, done)    -- item: { backend, id, remote }
--
-- Every change goes through host.act, which holds back under EVA_DRY_RUN.
-- EVA_FAKE_SOFTWARE ("app.desktop=flatpak,other.desktop=system") names the kind
-- of chosen apps, for a machine without those systems.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

M.LABELS = {
  flatpak = "Flatpak", profile = "Nix profile", snap = "Snap", appimage = "AppImage", ["local"] = "Your own entry",
  system = "This NixOS system", declared = "Your configuration", package = "System package", unknown = "Unknown",
}

local NIX = { "nix", "--extra-experimental-features", "nix-command flakes" }

local function nix(...)
  local out = {}
  for _, word in ipairs(NIX) do out[#out + 1] = word end
  for _, word in ipairs { ... } do out[#out + 1] = word end
  return out
end
M.nix = nix

--- What this machine adds and removes software with.
function M.machine()
  return { nixos = host.nixos(), nix = host.installed("nix"), flatpak = host.installed("flatpak"),
    snap = host.installed("snap") }
end

-- ------------------------------------------------------------- the profile --

-- The Nix profile's elements by store path, and whether Home Manager keeps it.
local elements, home_manager = {}, false

--- Takes `nix profile list --json`'s answer.
function M.read_profile(text)
  elements, home_manager = {}, false
  local ok, data = pcall(morf.json.decode, text or "")
  local rows = ok and type(data) == "table" and data.elements or nil
  if type(rows) ~= "table" then return end
  for name, element in pairs(rows) do
    local label = type(name) == "string" and name or element.name or tostring(name)
    if label:find("home-manager", 1, true) then home_manager = true end
    for _, path in ipairs(element.storePaths or {}) do elements[path] = label end
  end
end

--- Reads the person's Nix profile. `done()` once it has answered.
function M.scan(done)
  done = done or function() end
  if not host.installed("nix") or (host.dry() and not host.fake()) then return done() end
  host.read(nix("profile", "list", "--json"), function(text)
    M.read_profile(text)
    done()
  end, { timeout_ms = 15000 })
end

-- ------------------------------------------------------------- the sources --

local function faked()
  local spec = morf.env and morf.env("EVA_FAKE_SOFTWARE")
  local out = {}
  for id, kind in tostring(spec or ""):gmatch("([^=,]+)=([^=,]+)") do out[id] = kind end
  return out
end
local FAKED = faked()

local function home() return morf.env("HOME") or morf.fs.home() end

local function data_home()
  local data = morf.env("XDG_DATA_HOME")
  if data and data ~= "" then return data end
  return home() .. "/.local/share"
end

local function link(path)
  local ok, target = pcall(morf.fs.read_link, path)
  return ok and type(target) == "string" and target or nil
end

-- An entry's file: `source` is its folder, and its id comes without the suffix.
local function entry_path(row)
  local id = tostring(row.id)
  return (row.source or "") .. "/" .. (id:find("%.desktop$") and id or id .. ".desktop")
end

local function under(path, prefix) return path:sub(1, #prefix) == prefix end

--- What kind of thing put `row` here.
function M.kind_of(row)
  if FAKED[row.id] then return FAKED[row.id] end
  local source = row.source or ""
  if source:find("flatpak", 1, true) then return "flatpak" end
  if tostring((row.command or {})[1] or ""):lower():find("%.appimage$") then return "appimage" end
  if source:find("snapd", 1, true) then return "snap" end
  if under(source, "/run/current-system") or under(source, "/nix/var/nix/profiles/system") then return "system" end
  if under(source, "/etc/profiles/per-user/") then return "declared" end
  if source:find(".nix-profile", 1, true) or source:find("/nix/profiles/", 1, true) then return "profile" end
  if under(source, data_home()) then
    return tostring(link(entry_path(row)) or ""):find("^/nix/store/") and "declared" or "local"
  end
  if under(source, "/nix/") then return "system" end
  if source == "" then return "unknown" end
  return "package"
end

local function trash(paths)
  if not host.installed("gio") then return nil end
  local argv = { "gio", "trash" }
  for _, path in ipairs(paths) do argv[#argv + 1] = path end
  return argv
end

local WHY = {
  system = "Part of this NixOS system. Take it out of the configuration and rebuild.",
  declared = "Declared in your NixOS or Home Manager configuration. Take it out there and rebuild.",
  package = "Installed by the system's package manager. Remove it there.",
  unknown = "Nothing here says what installed it.",
}

local function refused(kind, why)
  return { kind = kind, label = M.LABELS[kind], removable = false, why = why or WHY[kind] }
end

local function offered(kind, argv, what)
  if not argv then return refused(kind, "The program that would remove it is missing.") end
  return { kind = kind, label = M.LABELS[kind], removable = true, argv = argv, what = what }
end

--- Where `row` came from and whether it can go: `{ kind, label, removable, why,
--- argv, what }`. `why` says in words why it cannot.
function M.source_of(row)
  local kind = M.kind_of(row)
  if kind == "flatpak" then
    if not host.installed("flatpak") then return refused(kind, "Flatpak is not installed here.") end
    local app = tostring(row.id):gsub("%.desktop$", "")
    local place = under(row.source or "", home()) and "--user" or "--system"
    return offered(kind, { "flatpak", "uninstall", "--noninteractive", "-y", place, app }, "Removes the app, leaves its data")
  end
  if kind == "snap" then
    if not host.installed("snap") then return refused(kind, "Snap is not installed here.") end
    return offered(kind, { "snap", "remove", (tostring(row.id):gsub("_.*$", ""):gsub("%.desktop$", "")) }, "Removes the snap")
  end
  if kind == "profile" then
    local store = tostring(link(entry_path(row)) or ""):match("^(/nix/store/[^/]+)")
    local element = store and elements[store] or row.profile_element
    if element then return offered(kind, nix("profile", "remove", element), "Takes it out of your Nix profile") end
    if home_manager then return refused("declared") end
    return refused(kind, "Your Nix profile does not list it, so nothing here can remove it.")
  end
  if kind == "appimage" then
    local file = tostring((row.command or {})[1] or "")
    return offered(kind, trash { file, entry_path(row) }, "Moves the file to the trash")
  end
  if kind == "local" then return offered(kind, trash { entry_path(row) }, "Moves its entry to the trash") end
  return refused(kind)
end

--- Takes `row` off the machine. `done(text)` or `done(nil, why)`.
function M.remove(row, done)
  local source = M.source_of(row)
  if not source.removable then return done(nil, source.why) end
  return host.act(source.argv, done, { timeout_ms = 600000 })
end

-- ------------------------------------------------------------ installing --

--- What `flatpak search` printed: `{ backend, id, name, description, version, remote }`.
function M.parse_flatpak(text)
  local out = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local id, name, description, version, remote = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
    if id and id ~= "" then
      out[#out + 1] = { backend = "flatpak", id = id, name = name, description = description, version = version,
        remote = (remote:match("^[^,]+") or "") }
    end
  end
  return out
end

--- How to look for `term` in Flatpak's own catalogue.
function M.flatpak_search(term)
  return { "flatpak", "search", "--columns=application,name,description,version,remotes", term }
end

--- The command that installs `item`.
function M.install_argv(item)
  if item.backend == "nix" then return nix("profile", "install", "nixpkgs#" .. item.id) end
  if item.backend == "flatpak" then
    local argv = { "flatpak", "install", "--noninteractive", "-y" }
    if item.remote and item.remote ~= "" then argv[#argv + 1] = item.remote end
    argv[#argv + 1] = item.id
    return argv
  end
end

--- Installs `item`. `done(text)` or `done(nil, why)`.
function M.install(item, done)
  local argv = M.install_argv(item)
  if not argv then return done(nil, "Nothing here can install that") end
  return host.act(argv, done, { timeout_ms = 1800000 })
end

return M
