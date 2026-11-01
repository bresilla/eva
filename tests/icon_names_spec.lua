-- Every icon name in the source is a glyph of the icon font: a name the font
-- lacks is drawn as its letters, in place of the icon.
--
--     morf test tests/icon_names_spec.lua
local test = morf.test

local FOLDERS = { "shell", "themes", "lib", "apps", "apps/common" }
local PATTERNS = { 'icon%s*=%s*"([%l%d_]+)"', 'icon%("([%l%d_]+)"' }
local SIZE = 24
-- A tool's links back to the shell.
local LINKS = { lua = true, common = true, fonts = true }

local function walk(folder, out)
  for _, entry in ipairs(morf.fs.list(folder) or {}) do
    local name = tostring(type(entry) == "table" and entry.name or entry)
    if name:match("%.lua$") then out[#out + 1] = folder .. "/" .. name
    elseif not name:find(".", 1, true) and not LINKS[name] then pcall(walk, folder .. "/" .. name, out) end
  end
end

local function source_names()
  local files, found, list = {}, {}, {}
  for _, folder in ipairs(FOLDERS) do walk(folder, files) end
  for _, path in ipairs(files) do
    local text = morf.fs.read(path) or ""
    for _, pattern in ipairs(PATTERNS) do
      for name in text:gmatch(pattern) do
        if not found[name] then found[name] = path list[#list + 1] = name end
      end
    end
  end
  table.sort(list)
  return list, found
end

local function host(list)
  local rows = {}
  for i, name in ipairs(list) do
    rows[i] = ('ui.Text { id = "icon-%d", text = %q, font_family = theme.icon_font, font_size = %d },'):format(i, name, SIZE)
  end
  return [[
    local ui = require("morf.ui")
    local theme = require("theme")
    ui.Column { ]] .. table.concat(rows, "\n") .. [[ }
  ]]
end

test.it("the icon names in the source are glyphs", function()
  local list, found = source_names()
  test.truthy(#list > 100, "the walk reached the source")
  test.load("../shell/init.lua", { source = host(list), size = { 400, 400 }, env = { EVA_STYLE = "material" } })
  test.settle(1000)
  local letters = {}
  for i, name in ipairs(list) do
    if test.get("icon-" .. i).width > SIZE * 1.5 then letters[#letters + 1] = name .. " in " .. found[name] end
  end
  test.eq(letters, {})
end)
