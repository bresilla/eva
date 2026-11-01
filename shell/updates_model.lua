-- How current the system is. On Nix there is nothing to count, so it reads the
-- generation in use and how old its nixpkgs is, from the system's own version
-- and a flake.lock. Elsewhere it counts what the package managers offer
-- (lib/integrations/packages.lua). No nodes.
local morf = require("morf")
local M = { STALE_DAYS = 14, OLD_DAYS = 30 }

local function read_link(path)
  local ok, target = pcall(morf.fs.read_link, path)
  return ok and type(target) == "string" and target or nil
end

--- The generation a `system-41-link` names.
function M.generation(link)
  return tonumber(tostring(link or ""):match("system%-(%d+)%-link"))
end

--- The date in a NixOS version, `26.05.20261031.fa13731`, as a time.
function M.version_date(version)
  local y, m, d = tostring(version or ""):match("%.(%d%d%d%d)(%d%d)(%d%d)%.")
  if not y then return nil end
  return morf.time.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

--- When the root's nixpkgs input in a flake.lock's text was locked.
function M.flake_date(text)
  local ok, lock = pcall(morf.json.decode, text or "")
  if not ok or type(lock) ~= "table" or type(lock.nodes) ~= "table" then return nil end
  local root = lock.nodes[lock.root or "root"] or {}
  local name = (root.inputs or {}).nixpkgs or "nixpkgs"
  if type(name) == "table" then name = name[1] end
  local node = lock.nodes[name]
  return node and node.locked and tonumber(node.locked.lastModified) or nil
end

local function flake_paths(chosen, home)
  if chosen and chosen ~= "" then return { (chosen:gsub("^~/", home .. "/")) } end
  return { "/etc/nixos/flake.lock", home .. "/.config/nixos/flake.lock", home .. "/.config/home-manager/flake.lock" }
end

--- What Nix says of this machine, under `root` ("" for the real one): `{ nix,
--- generation, version, age, flake_age }`, the ages in whole days, or nil.
function M.nix(root, chosen, now)
  root, now = root or "", now or morf.time.now()
  if not morf.fs.exists(root .. "/nix") then return nil end
  local out = { nix = true, generation = M.generation(read_link(root .. "/nix/var/nix/profiles/system")) }
  local current = read_link(root .. "/run/current-system") or ""
  out.version = current:match("nixos%-system%-[^-]+%-(.+)$")
  local built = M.version_date(out.version)
  if built then out.age = math.max(0, (now - built) // 86400) end
  for _, path in ipairs(flake_paths(chosen, morf.fs.home())) do
    local ok, text = pcall(morf.fs.read, root .. path)
    local locked = ok and M.flake_date(text) or nil
    if locked then
      out.flake_age = math.max(0, (now - locked) // 86400)
      break
    end
  end
  return out
end

local function days(count)
  return count == 1 and "1 day" or (count .. " days")
end

--- What the module shows: `{ text, tooltip, tone, count, present }`.
function M.describe(nix, packages)
  if nix then
    local age = nix.flake_age or nix.age
    local tone = age and (age >= M.OLD_DAYS and "alert" or age >= M.STALE_DAYS and "warn") or nil
    local lines = {}
    if nix.generation then lines[#lines + 1] = "NixOS generation " .. nix.generation end
    if nix.version then lines[#lines + 1] = "Version " .. nix.version end
    if nix.age then lines[#lines + 1] = "Built from nixpkgs " .. days(nix.age) .. " old" end
    if nix.flake_age then lines[#lines + 1] = "flake.lock " .. days(nix.flake_age) .. " old" end
    local parts = {}
    if nix.generation then parts[#parts + 1] = "#" .. nix.generation end
    if age then parts[#parts + 1] = age .. "d" end
    return { present = #parts > 0, text = table.concat(parts, " "), tone = tone or nil, count = age or 0,
      tooltip = table.concat(lines, "\n") }
  end
  packages = packages or {}
  local total = packages.total or 0
  return { present = (packages.managers ~= nil and #packages.managers > 0), text = tostring(total), count = total,
    tone = total > 0 and "extra" or nil,
    tooltip = total == 1 and "1 update waiting" or (total .. " updates waiting") }
end

return M
