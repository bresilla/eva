-- eva-info's facts about this machine, gathered once when it opens: what
-- lib.services.sysinfo and lib.shell.displays know, and what only this tool asks
-- about, the firmware, USB, the session and the Nix generation. No nodes.
local morf = require("morf")
local sysinfo = require("lib.services.sysinfo")
local performance = require("performance_model")
local displays = require("lib.shell.displays")
local sys = require("common.sys")

local M = {
  facts = morf.signal("info.facts", {}),
  message = morf.signal("info.message", ""),
  revision = morf.signal("info.revision", 0),
}

M.root = morf.env("EVA_INFO_ROOT") or ""

local function path(p) return M.root .. p end

local function text_at(p)
  local ok, text = pcall(morf.fs.read, path(p), 4096)
  if not ok or type(text) ~= "string" then return nil end
  local value = text:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function link_at(p)
  local ok, link = pcall(morf.fs.read_link, path(p))
  return ok and type(link) == "string" and link or nil
end

local function list_at(p)
  local ok, list = pcall(morf.fs.list, path(p), { follow = true })
  return ok and type(list) == "table" and list or {}
end

local function size(bytes)
  local number, unit = performance.bytes(bytes)
  return number .. " " .. unit
end

-- ------------------------------------------------------------- the machine --

local function machine()
  return {
    vendor = text_at("/sys/class/dmi/id/sys_vendor"),
    product = text_at("/sys/class/dmi/id/product_name") or text_at("/proc/device-tree/model"),
    board = text_at("/sys/class/dmi/id/board_name"),
    firmware = text_at("/sys/class/dmi/id/bios_version"),
    firmware_date = text_at("/sys/class/dmi/id/bios_date"),
  }
end

local function scheduler(drives)
  local chosen
  for _, drive in ipairs(drives) do
    if drive.system or not chosen then
      local line = text_at("/sys/block/" .. drive.name .. "/queue/scheduler")
      chosen = line and line:match("%[(.-)%]") or chosen
    end
  end
  return chosen
end

local function usb()
  local out = {}
  for _, entry in ipairs(list_at("/sys/bus/usb/devices")) do
    if not entry.name:find(":", 1, true) and not entry.name:match("^usb%d") then
      local base = "/sys/bus/usb/devices/" .. entry.name
      local vendor, product = text_at(base .. "/idVendor"), text_at(base .. "/idProduct")
      if vendor then
        out[#out + 1] = {
          name = text_at(base .. "/product") or (vendor .. ":" .. tostring(product)),
          maker = text_at(base .. "/manufacturer"), id = vendor .. ":" .. tostring(product),
          speed = tonumber(text_at(base .. "/speed")),
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function portals()
  local dirs = morf.env("XDG_DATA_DIRS") or ""
  if dirs == "" then dirs = "/usr/local/share:/usr/share" end
  local seen, out = {}, {}
  for dir in dirs:gmatch("[^:]+") do
    for _, entry in ipairs(list_at(dir .. "/xdg-desktop-portal/portals")) do
      local name = entry.name:match("^(.+)%.portal$")
      if name and not seen[name] then
        seen[name] = true
        out[#out + 1] = name
      end
    end
  end
  table.sort(out)
  return out
end

local function session()
  return {
    type = morf.env("XDG_SESSION_TYPE"), desktop = morf.env("XDG_CURRENT_DESKTOP"),
    compositor = sys.compositor(), wayland = morf.env("WAYLAND_DISPLAY"), portals = portals(),
  }
end

local function nix()
  local current = link_at("/run/current-system")
  if not current then return nil end
  local link = link_at("/nix/var/nix/profiles/system")
  local out = {
    closure = current:match("([^/]+)$"), version = text_at("/run/current-system/nixos-version"),
    generation = link and tonumber(link:match("(%d+)")),
  }
  if out.version then out.nixpkgs = out.version:match("%.(%x+)$") end
  if link then
    local ok, stat = pcall(morf.fs.stat, path("/nix/var/nix/profiles/" .. link))
    if ok and type(stat) == "table" then out.built = stat.modified end
  end
  return out
end

local function eva_version()
  local file = morf.paths.shell("app.lua"):gsub("/apps/info/app%.lua$", "/morf.lua")
  local ok, text = pcall(morf.fs.read, file)
  return ok and type(text) == "string" and text:match('version%s*=%s*"([^"]+)"') or "unknown"
end

local function cpu_facts(info, cpu)
  return { model = performance.cpu_name(info.model), threads = info.logical, sockets = info.sockets,
    max_mhz = info.max_mhz > 0 and info.max_mhz or cpu.frequency, governor = info.governor,
    virtualization = info.virtualization }
end

local function gpu_facts(cards)
  local out = {}
  for _, card in ipairs(cards) do
    out[#out + 1] = { card = card.name, name = card.model, vendor = card.vendor, driver = card.driver, slot = card.slot,
      memory = card.vram_total, suspended = card.suspended }
  end
  return out
end

local function drive_facts(drives)
  local out = {}
  for _, drive in ipairs(drives) do
    out[#out + 1] = { name = drive.name, model = drive.model, kind = drive.kind, capacity = drive.capacity,
      removable = drive.removable, system = drive.system }
  end
  return out
end

local function mount_facts(disks)
  local out = {}
  for _, disk in ipairs(disks) do
    out[#out + 1] = { mount = disk.mount, device = disk.device, type = disk.type, total = disk.total, used = disk.used,
      percent = disk.percent }
  end
  return out
end

local function display_facts(outputs)
  local out = {}
  for _, output in ipairs(outputs or {}) do
    if output.enabled ~= false then
      out[#out + 1] = { name = output.name, model = output.description or output.model, width = output.width,
        height = output.height, refresh = output.refresh, scale = output.scale }
    end
  end
  return out
end

-- ------------------------------------------------------------- what is asked --

local function publish(facts)
  M.facts:set(facts)
  M.revision:set(M.revision:get() + 1)
end

-- The name a card is sold under, where the sampler has only its numbers.
local function name_gpus(facts, done)
  local cards = facts.gpus
  local missing, nvidia = false, false
  for _, card in ipairs(cards) do
    if card.name:match("^%x%x%x%x:%x%x%x%x$") and not card.suspended then
      missing = true
      nvidia = nvidia or card.driver == "nvidia"
    end
  end
  if not missing then done() return end
  if nvidia and sys.has("nvidia-smi") then
    sys.run({ "nvidia-smi", "--query-gpu=pci.bus_id,name,memory.total,driver_version", "--format=csv,noheader,nounits" },
      { read = true, timeout_ms = 3000 }, function(result)
        for line in tostring(result.stdout or ""):gmatch("[^\n]+") do
          local slot, name, memory, driver = line:match("^%s*%x*(%x%x%x%x:%x%x:%x%x%.%x),%s*(.-),%s*(%d+),%s*(.-)%s*$")
          for _, card in ipairs(cards) do
            if slot and card.slot:lower() == slot:lower() then
              card.name, card.memory, card.driver_version = name, tonumber(memory) * 1048576, driver
            end
          end
        end
        done()
      end)
    return
  end
  done()
end

local function nix_revision(facts, done)
  if not facts.nix then done() return end
  sys.run({ "nixos-version", "--json" }, { read = true, timeout_ms = 3000 }, function(result)
    local ok, data = pcall(morf.json.decode, result.stdout or "")
    if ok and type(data) == "table" then
      facts.nix.flake = data.configurationRevision
      facts.nix.nixpkgs = data.nixpkgsRevision or facts.nix.nixpkgs
    end
    done()
  end)
end

local function failed_units(facts, done)
  sys.run({ "systemctl", "--failed", "--no-legend", "--plain" }, { read = true, timeout_ms = 3000 }, function(result)
    if result.ok then
      local names = {}
      for row in tostring(result.stdout or ""):gmatch("[^\n]+") do names[#names + 1] = row:match("^%s*(%S+)") end
      facts.session.failed = names
    end
    done()
  end)
end

local function read_displays(facts, done)
  if displays.kind() ~= "hyprland" and displays.kind() ~= "sway" then done() return end
  displays.read(function(outputs)
    facts.displays = display_facts(outputs)
    done()
  end)
end

-- ---------------------------------------------------------------- the words --

local function joined(parts, between)
  local out = {}
  for _, part in ipairs(parts) do
    if part and part ~= "" then out[#out + 1] = part end
  end
  return table.concat(out, between or ", ")
end

local function line(rows, label, value)
  if value ~= nil and value ~= "" then rows[#rows + 1] = { label, tostring(value) } end
end

--- A length of time in words.
function M.span(seconds)
  seconds = math.floor(seconds or 0)
  local days, hours, minutes = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
  if days > 0 then return ("%d d %d h"):format(days, hours) end
  if hours > 0 then return ("%d h %d min"):format(hours, minutes) end
  return ("%d min"):format(minutes)
end

--- The facts as what a person reads: `{ { key, title, rows = { { label, value } } } }`,
--- a section with nothing to say left out.
function M.sections(facts)
  local out = {}
  local function section(key, title, rows)
    if #rows > 0 then out[#out + 1] = { key = key, title = title, rows = rows } end
  end
  local system, cpu, memory = facts.system or {}, facts.cpu or {}, facts.memory or {}
  local rows = {}
  line(rows, "Host name", system.hostname)
  line(rows, "User", system.user)
  line(rows, "Operating system", system.os)
  line(rows, "Kernel", system.kernel)
  line(rows, "I/O scheduler", system.scheduler)
  line(rows, "Sched-ext", system.sched_ext)
  line(rows, "Up", system.uptime and M.span(system.uptime))
  section("system", "System", rows)

  rows = {}
  local maker = facts.machine or {}
  line(rows, "Machine", joined({ maker.vendor, maker.product }, " "))
  line(rows, "Board", maker.board)
  line(rows, "Firmware", joined({ maker.firmware, maker.firmware_date }))
  line(rows, "Processor", cpu.model)
  line(rows, "Threads", cpu.threads and joined { tostring(math.floor(cpu.threads)),
    (cpu.sockets or 1) > 1 and (math.floor(cpu.sockets) .. " sockets") or nil })
  line(rows, "Clock", cpu.max_mhz and cpu.max_mhz > 0 and ("%.2f GHz"):format(cpu.max_mhz / 1000) or nil)
  line(rows, "Governor", cpu.governor)
  line(rows, "Virtualization", cpu.virtualization)
  line(rows, "Memory", memory.total and size(memory.total))
  line(rows, "Swap", memory.swap and memory.swap > 0 and size(memory.swap) or nil)
  section("hardware", "Hardware", rows)

  rows = {}
  for _, card in ipairs(facts.gpus or {}) do
    line(rows, card.card, joined { card.name, card.memory and size(card.memory), card.driver,
      card.driver_version, card.suspended and "asleep" or nil })
  end
  section("gpus", "Graphics", rows)

  rows = {}
  for _, drive in ipairs(facts.drives or {}) do
    line(rows, drive.name, joined { drive.model, drive.kind, size(drive.capacity), drive.system and "system" or nil })
  end
  for _, mount in ipairs(facts.mounts or {}) do
    line(rows, mount.mount, ("%s of %s, %s"):format(size(mount.used), size(mount.total), mount.type))
  end
  section("disks", "Storage", rows)

  rows = {}
  for _, output in ipairs(facts.displays or {}) do
    line(rows, output.name, joined { ("%d x %d at %.0f Hz"):format(output.width or 0, output.height or 0, output.refresh or 0),
      output.scale and output.scale ~= 1 and ("scale %g"):format(output.scale) or nil, output.model })
  end
  section("displays", "Displays", rows)

  local versions = facts.versions or {}
  rows = {}
  line(rows, "eva", versions.eva)
  line(rows, "morf", versions.morf)
  section("versions", "Versions", rows)

  local nixos = facts.nix or {}
  rows = {}
  line(rows, "Generation", nixos.generation and math.floor(nixos.generation))
  line(rows, "Built", nixos.built and morf.time.format("%-d %b %Y %H:%M", nixos.built))
  line(rows, "NixOS", nixos.version)
  line(rows, "Flake revision", nixos.flake)
  line(rows, "Nixpkgs", nixos.nixpkgs)
  section("nix", "Nix", rows)

  rows = {}
  for _, device in ipairs(facts.usb or {}) do
    line(rows, device.name, joined { device.maker, device.id, device.speed and (math.floor(device.speed) .. " Mb/s") })
  end
  section("usb", "USB", rows)

  local place = facts.session or {}
  rows = {}
  line(rows, "Session", place.type)
  line(rows, "Desktop", place.desktop)
  line(rows, "Compositor", place.compositor ~= "other" and place.compositor or nil)
  line(rows, "Display", place.wayland)
  line(rows, "Portals", place.portals and table.concat(place.portals, ", "))
  if place.failed then line(rows, "Failed units", #place.failed == 0 and "None" or table.concat(place.failed, ", ")) end
  section("session", "Session", rows)
  return out
end

--- Everything as text, for a paste.
function M.text(facts)
  local out = {}
  for _, section in ipairs(M.sections(facts or M.facts:get())) do
    if #out > 0 then out[#out + 1] = "" end
    out[#out + 1] = section.title
    for _, row in ipairs(section.rows) do out[#out + 1] = ("  %s: %s"):format(row[1], row[2]) end
  end
  return table.concat(out, "\n") .. "\n"
end

--- Gathers every fact, `done(facts)` once the slow ones are in.
function M.gather(done)
  if M.root ~= "" then sysinfo.configure { root = M.root, blocking = true } end
  local system = sysinfo.sample("system") or {}
  local cpu = sysinfo.sample("cpu") or { frequency = 0 }
  local memory = sysinfo.sample("memory") or {}
  local gpu = sysinfo.sample("gpu") or { cards = {} }
  local drives = sysinfo.sample("drives") or { drives = {} }
  local disks = sysinfo.sample("disks") or {}
  local info = sysinfo.cpu_info()
  local facts = {
    system = { hostname = system.hostname, user = system.user, os = system.os, os_id = system.os_id, kernel = system.kernel,
      uptime = system.uptime, scheduler = scheduler(drives.drives), sched_ext = text_at("/sys/kernel/sched_ext/state") },
    machine = machine(), cpu = cpu_facts(info, cpu), memory = { total = memory.total, swap = memory.swap and memory.swap.total },
    gpus = gpu_facts(gpu.cards), drives = drive_facts(drives.drives), mounts = mount_facts(disks), displays = {},
    versions = { eva = eva_version(), morf = tostring(morf.version) }, nix = nix(), usb = usb(), session = session(),
  }
  publish(facts)
  local waiting = 4
  local function arrived()
    waiting = waiting - 1
    publish(facts)
    if waiting == 0 and done then done(facts) end
  end
  name_gpus(facts, arrived)
  nix_revision(facts, arrived)
  failed_units(facts, arrived)
  read_displays(facts, arrived)
end

--- All of it on the clipboard.
function M.copy()
  sys.copy(M.text())
  M.message:set(sys.dry() and "Would copy it all (dry run)" or "Copied")
  return true
end

return M
