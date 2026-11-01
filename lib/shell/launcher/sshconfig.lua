-- The hosts in ~/.ssh/config, following its Includes, and the plain names in
-- ~/.ssh/known_hosts. Patterns are not hosts, and a hashed known host has no
-- name to read.

local morf = require("morf")

local M = {}

local MAX_INCLUDES = 16

local function expand(path, folder)
  if path:sub(1, 2) == "~/" then return morf.fs.home() .. path:sub(2) end
  if path:sub(1, 1) ~= "/" then return folder .. "/" .. path end
  return path
end

--- `{ alias, hostname, user, port, identity, jump }` for each named host in
--- `text`; `seen` gathers them across included files.
local function parse(text, folder, out, seen, depth)
  local current = {}
  for line in text:gmatch("[^\r\n]+") do
    local stripped = line:match("^%s*(.-)%s*$")
    if stripped ~= "" and stripped:sub(1, 1) ~= "#" then
      local key, value = stripped:match("^([%w]+)%s*=?%s*(.-)$")
      key = key and key:lower()
      if key == "host" then
        current = {}
        for alias in value:gmatch("%S+") do
          alias = alias:gsub('^"(.*)"$', "%1")
          if not alias:find("[*?!]") and not seen[alias] then
            seen[alias] = true
            local host = { alias = alias }
            out[#out + 1] = host
            current[#current + 1] = host
          end
        end
      elseif key == "match" then
        current = {}
      elseif key == "include" and depth < MAX_INCLUDES then
        for pattern in value:gmatch("%S+") do
          local ok, paths = pcall(morf.fs.glob, expand(pattern, folder))
          for _, path in ipairs(ok and type(paths) == "table" and paths or {}) do
            local file = type(path) == "table" and path.path or path
            local fine, included = pcall(morf.fs.read, file)
            if fine and type(included) == "string" then parse(included, folder, out, seen, depth + 1) end
          end
        end
      else
        for _, host in ipairs(current) do
          if key == "hostname" then host.hostname = value
          elseif key == "user" then host.user = value
          elseif key == "port" then host.port = value
          elseif key == "identityfile" then host.identity = value
          elseif key == "proxyjump" then host.jump = value end
        end
      end
    end
  end
end

--- The hosts in the config at `path` (~/.ssh/config).
function M.hosts(path)
  local folder = morf.fs.home() .. "/.ssh"
  path = path or (folder .. "/config")
  local ok, text = pcall(morf.fs.read, path)
  local out = {}
  if ok and type(text) == "string" then parse(text, folder, out, {}, 0) end
  return out
end

--- The plain host names in `text` (a known_hosts file).
function M.known(text)
  local out, seen = {}, {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local names = line:match("^([^%s#|@][^%s]*)%s")
    if names then
      for name in names:gmatch("[^,]+") do
        local plain = name:gsub("^%[(.-)%]:%d+$", "%1")
        if not seen[plain] and not plain:match("^%d+%.%d+%.%d+%.%d+$") and not plain:find(":", 1, true) then
          seen[plain] = true
          out[#out + 1] = plain
        end
      end
    end
  end
  return out
end

return M
