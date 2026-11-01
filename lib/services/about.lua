-- This machine, from what the kernel and the system publish: nothing here
-- needs a daemon or a privilege, so it reads the same on any distribution.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

local function read(path)
  local ok, text = pcall(morf.fs.read, path)
  return ok and type(text) == "string" and (text:gsub("%s+$", "")) or nil
end

--- `os-release` as a table.
function M.parse_os_release(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local key, value = line:match("^([%w_]+)=(.*)$")
    if key then out[key] = (value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")) end
  end
  return out
end

--- `/proc/cpuinfo`'s model and how many threads it lists.
function M.parse_cpu(text)
  local model, count = nil, 0
  for line in tostring(text or ""):gmatch("[^\n]+") do
    if line:match("^processor%s*:") then count = count + 1 end
    model = model or line:match("^model name%s*:%s*(.+)$") or line:match("^Hardware%s*:%s*(.+)$")
  end
  return model or "", count
end

--- `/proc/meminfo`'s total, in bytes.
function M.parse_memory(text) return (tonumber(tostring(text or ""):match("MemTotal:%s*(%d+)")) or 0) * 1024 end

--- `lspci`'s graphics lines, as names.
function M.parse_gpus(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local name = line:match("VGA compatible controller:%s*(.+)$") or line:match("3D controller:%s*(.+)$")
      or line:match("Display controller:%s*(.+)$")
    if name then out[#out + 1] = (name:gsub("%s*%(rev [%x]+%)$", "")) end
  end
  return out
end

local function bytes(n)
  local units, value, unit = { "B", "KB", "MB", "GB", "TB" }, tonumber(n) or 0, 1
  while value >= 1024 and unit < #units do value, unit = value / 1024, unit + 1 end
  return ("%.1f %s"):format(value, units[unit])
end

--- Everything readable at once, as `{ { key, name, value } }` in order.
function M.facts(extra)
  local fake = host.fake() and require("lib.services.host_fake")
  local source = fake and fake.about() or {}
  local function file(path) if fake then return source[path] end return read(path) end
  local os = M.parse_os_release(file("/etc/os-release"))
  local model, threads = M.parse_cpu(file("/proc/cpuinfo"))
  local vendor = file("/sys/class/dmi/id/sys_vendor") or ""
  local product = file("/sys/class/dmi/id/product_name") or ""
  local rows = {}
  local function add(key, name, value)
    if value ~= nil and value ~= "" then rows[#rows + 1] = { key = key, name = name, value = tostring(value) } end
  end
  add("host", "Device name", file("/proc/sys/kernel/hostname"))
  add("model", "Model", ((vendor .. " " .. product):gsub("^%s+", ""):gsub("%s+$", "")))
  add("cpu", "Processor", model ~= "" and ("%s (%d threads)"):format(model, threads) or nil)
  add("memory", "Memory", bytes(M.parse_memory(file("/proc/meminfo"))))
  for index, name in ipairs(extra and extra.gpus or {}) do add("gpu" .. index, "Graphics", name) end
  local ok, disk = pcall(morf.fs.disk, "/")
  add("disk", "Disk", ok and type(disk) == "table" and bytes(disk.total) or nil)
  add("system", "System", os.PRETTY_NAME or os.NAME)
  add("kernel", "Kernel", file("/proc/sys/kernel/osrelease"))
  add("compositor", "Compositor", extra and extra.compositor)
  add("morf", "morf", morf.version)
  add("eva", "eva", extra and extra.eva)
  return rows
end

--- The facts as text to paste into a bug report.
function M.as_text(rows)
  local lines = {}
  for index, row in ipairs(rows) do lines[index] = row.name .. ": " .. row.value end
  return table.concat(lines, "\n")
end

--- `done(names)`: the graphics adapters.
function M.gpus(done)
  if not host.installed("lspci") then return done {} end
  host.read({ "lspci" }, function(text) done(M.parse_gpus(text)) end)
end

--- eva's own version, as its bundle declares it.
function M.eva_version()
  local ok, root = pcall(morf.paths.shell, "../morf.lua")
  local text = ok and root and read(root)
  return text and text:match('version%s*=%s*"([%d%.]+)"') or nil
end

return M
