-- Layouts place on the spacing scale (themes/spacing.lua): a gap or a margin
-- written as a number is a step of the 4 px grid.
--
--     morf test tests/spacing_spec.lua

local test = morf.test

-- Hairlines, and steps of the grid.
local function allowed(value) return value <= 2 or value % 4 == 0 end
local FOLDERS = { "themes/layouts", "themes/layouts/views", "themes/kit", "shell" }
local KEYS = { "gap", "top_margin", "bottom_margin", "left_margin", "right_margin", "margins" }

local function lua_files(folder)
  local names = {}
  for _, entry in ipairs(morf.fs.list(folder)) do
    local name = type(entry) == "table" and entry.name or entry
    if tostring(name):match("%.lua$") then names[#names + 1] = folder .. "/" .. name end
  end
  return names
end

test.it("layouts keep their gaps and margins on the grid", function()
  local strays = {}
  for _, folder in ipairs(FOLDERS) do
    for _, path in ipairs(lua_files(folder)) do
      local number = 0
      for line in (morf.fs.read(path) .. "\n"):gmatch("(.-)\n") do
        number = number + 1
        for _, key in ipairs(KEYS) do
          for value in line:gmatch("%f[%w_]" .. key .. "%s*=%s*(%d+)%f[^%d.]") do
            if not allowed(tonumber(value)) then strays[#strays + 1] = ("%s:%d %s=%s"):format(path, number, key, value) end
          end
        end
      end
    end
  end
  test.eq(strays, {})
end)
