-- The phone link's state, over KDE Connect. No nodes. Nothing runs until the
-- page shows, and nothing at all on a machine without `kdeconnect-cli`.
local morf = require("morf")
local kdeconnect = require("lib.integrations.kdeconnect")
local M = {
  devices = morf.list_model({}),
  notifications = morf.list_model({}),
  selected = morf.signal("eva.phone.selected", ""),
  battery = morf.signal("eva.phone.battery", {}),
  said = morf.signal("eva.phone.said", ""),
  failed = morf.signal("eva.phone.failed", ""),
  loaded = morf.signal("eva.phone.loaded", false),
}
local timer, asked, known = nil, false, {}

--- Whether KDE Connect is installed.
function M.present() return kdeconnect.program() ~= nil end

local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

--- The device on show, as `{ id, name, reachable }`, or nil.
function M.device()
  local id = M.selected:get()
  for i = 1, M.devices:len() do
    local device = M.devices:get(i)
    if device.id == id then return device end
  end
end

local function read_device(id)
  kdeconnect.battery(id, function(percent, charging)
    M.battery:set { id = id, percent = percent, charging = charging }
  end)
  kdeconnect.run({ "--device", id, "--list-notifications" }, function(result)
    local rows = {}
    for i, text in ipairs(kdeconnect.parse_notifications(result.ok and result.stdout or "")) do
      rows[i] = { id = tostring(i), text = text }
    end
    M.notifications:replace(rows, "id")
  end)
end

--- Reads the devices, and the one on show.
function M.refresh()
  if not M.present() or asked then return end
  asked = true
  kdeconnect.devices(function(devices, why)
    asked = false
    M.loaded:set(true)
    M.failed:set(devices and "" or tostring(why))
    if not devices then return end
    known = devices
    M.devices:replace(devices, "id")
    local chosen = M.selected:get()
    local found = false
    for _, device in ipairs(devices) do found = found or device.id == chosen end
    if not found then
      chosen = devices[1] and devices[1].id or ""
      for _, device in ipairs(devices) do
        if device.reachable then chosen = device.id break end
      end
      M.selected:set(chosen)
    end
    if chosen ~= "" then read_device(chosen) end
  end)
end

function M.select(id)
  M.selected:set(id)
  read_device(id)
end

--- Polls while the page is on show.
function M.watch(on)
  if timer then timer:cancel() timer = nil end
  if on then
    M.refresh()
    timer = morf.time.timer(15000, M.refresh, true)
  end
end

local function act(name, words, ok_words, timeout)
  local device = M.device()
  if not device then return false end
  if dry_run() then
    morf.log("info", "eva: phone " .. name .. " (dry run)")
    M.said:set(ok_words)
    return true
  end
  M.said:set("Asking " .. device.name .. "…")
  local argv = { "--device", device.id }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  kdeconnect.run(argv, function(result)
    if result.ok then M.said:set(ok_words)
    else M.said:set(tostring(result.error or result.stderr or "It did not work."):gsub("%s+$", ""):sub(1, 200)) end
  end, timeout)
  return true
end

--- Rings the phone.
function M.ring() return act("ring", { "--ring" }, "Ringing") end
--- Pings the phone.
function M.ping() return act("ping", { "--ping" }, "Ping sent") end
--- Sends this machine's clipboard.
function M.send_clipboard() return act("clipboard", { "--send-clipboard" }, "Clipboard sent") end
--- Shares a file or an address.
function M.share(target)
  if type(target) ~= "string" or target == "" then return false end
  return act("share", { "--share", target }, "Sent " .. (target:match("([^/]+)/?$") or target), kdeconnect.SEND_MS)
end
--- Shares every path of a drop.
function M.share_all(paths)
  for _, path in ipairs(paths or {}) do M.share(path) end
end

return M
