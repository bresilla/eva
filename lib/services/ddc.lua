-- External screens over DDC/CI, through ddcutil 2.2: its output as rows and the
-- commands that ask and set. Pure; shell/ddc_model.lua runs them, against
-- lib/services/host_fake.lua in the specs and a stand-in ddcutil in the VM.
local M = {}

-- The VCP feature a monitor's brightness is.
M.BRIGHTNESS = "10"

--- `ddcutil detect --brief` as rows: `{ bus, connector, model, serial }`. A
--- display it could not talk to is left out.
function M.parse_detect(text)
  local rows, row = {}, nil
  local function close()
    if row and row.bus then rows[#rows + 1] = row end
    row = nil
  end
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    if line:match("^Display%s+%d+") then
      close()
      row = { connector = "", model = "", serial = "" }
    elseif line:match("^%S") then
      close()
    elseif row then
      local bus = line:match("I2C bus:%s*/dev/i2c%-(%d+)")
      if bus then row.bus = bus end
      local connector = line:match("DRM connector:%s*(%S+)")
      if connector and connector ~= "not" then row.connector = (connector:gsub("^card%d+%-", "")) end
      local _, model, serial = line:match("Monitor:%s*([^:]*):([^:]*):(.*)$")
      if model then row.model, row.serial = model:match("^%s*(.-)%s*$"), serial:match("^%s*(.-)%s*$") end
    end
  end
  close()
  return rows
end

--- `ddcutil --brief getvcp 10` as current and max, or nil.
function M.parse_vcp(text)
  text = tostring(text or "")
  local current, max = text:match("VCP%s+10%s+C%s+(%d+)%s+(%d+)")
  if not current then current, max = text:match("current value%s*=%s*(%d+),%s*max value%s*=%s*(%d+)") end
  if not current or tonumber(max) == 0 then return nil end
  return tonumber(current), tonumber(max)
end

--- The display of `rows` on `output`, a row of the compositor's monitors:
--- `{ name, description }`. By connector, else by the model and serial its
--- description holds, as a port behind a dock may not say.
function M.find(rows, output)
  for _, row in ipairs(rows or {}) do
    if row.connector ~= "" and row.connector == output.name then return row end
  end
  local words = output.description or ""
  for _, row in ipairs(rows or {}) do
    if row.model ~= "" and words:find(row.model, 1, true) and (row.serial == "" or words:find(row.serial, 1, true)) then return row end
  end
end

function M.detect_args() return { "ddcutil", "detect", "--brief" } end

function M.read_args(bus) return { "ddcutil", "--bus", tostring(bus), "--brief", "getvcp", M.BRIGHTNESS } end

function M.write_args(bus, value)
  return { "ddcutil", "--bus", tostring(bus), "--noverify", "setvcp", M.BRIGHTNESS, tostring(math.floor(value)) }
end

--- A percentage as the monitor counts, 0 to `max`.
function M.raw(percent, max)
  return math.floor(math.max(0, math.min(100, percent)) * (max or 100) / 100 + .5)
end

return M
