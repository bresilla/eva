-- What a QR code is made of, with no state: the `WIFI:` string, qrencode's ASCII
-- read into modules, and the modules as one outline.
local M = {}

M.SECURITY = { "WPA", "WEP", "nopass" }

--- `value` with what the `WIFI:` format reserves escaped.
function M.escape(value)
  return (tostring(value):gsub('[\\;,:"]', "\\%0"))
end

--- The string that joins `net` (`ssid`, `security`, `hidden`) with `password`.
function M.wifi(net, password)
  local security = net.security or "WPA"
  local parts = { "WIFI:T:", security, ";S:", M.escape(net.ssid), ";" }
  if security ~= "nopass" then
    parts[#parts + 1] = "P:" .. M.escape(password or "") .. ";"
  end
  if net.hidden then parts[#parts + 1] = "H:true;" end
  parts[#parts + 1] = ";"
  return table.concat(parts)
end

--- qrencode's `-t ASCII -m 0`, two characters to a module: `{ size, rows }`,
--- a row a list of booleans; nil for what is not a square of modules.
function M.parse(ascii)
  local rows = {}
  for line in tostring(ascii or ""):gmatch("[^\r\n]+") do
    if #line % 2 ~= 0 then return nil end
    local row = {}
    for index = 1, #line, 2 do
      local cell = line:sub(index, index + 1)
      if cell ~= "##" and cell ~= "  " then return nil end
      row[#row + 1] = cell == "##"
    end
    rows[#rows + 1] = row
  end
  local size = #rows
  if size == 0 then return nil end
  for _, row in ipairs(rows) do
    if #row ~= size then return nil end
  end
  return { size = size, rows = rows }
end

--- The dark modules as path data, a run of a row to one box.
function M.outline(code)
  local parts = {}
  for y, row in ipairs(code.rows) do
    local x = 1
    while x <= code.size do
      if row[x] then
        local from = x
        while row[x + 1] do x = x + 1 end
        parts[#parts + 1] = ("M%d %dh%dv1h-%dz"):format(from - 1, y - 1, x - from + 1, x - from + 1)
      end
      x = x + 1
    end
  end
  return table.concat(parts)
end

return M
