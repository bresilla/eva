-- A page of settings drawn from shell/settings_forms.lua, every field reading
-- and writing its key in the shell's configuration.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local config = require("config")
local forms = require("settings_forms")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}

local function id_of(key) return "form-" .. key:gsub("%.", "-"):gsub("_", "-") end

local function bool(field, inner)
  return F.toggle { id = id_of(field.key), width = inner, icon = field.icon, title = field.title, subtitle = field.note,
    on = function() return config.get(field.key) == true end, set = function(on) config.set(field.key, on == true) end }
end

local function choice(field, inner)
  return ui.Column { width = inner, gap = P.ROW_GAP,
    F.note(inner, field.title),
    F.choices { id = id_of(field.key), width = inner, items = field.items, now = function() return config.get(field.key) end,
      pick = function(value) config.set(field.key, value) end },
  }
end

local function number(field, inner)
  return F.slider { id = id_of(field.key), width = inner, icon = field.icon, name = field.title, from = field.from,
    to = field.to, step = field.step, value = function() return config.get(field.key) end,
    set = function(value) config.set(field.key, value) end,
    format = function(value)
      local text = value == math.floor(value) and ("%d"):format(value) or tostring(value)
      return text .. (field.unit or "")
    end }
end

--- A field editing one line: the text as it stands, kept on Enter or on
--- pressing Save.
local function line(field, inner, read, write)
  local id = id_of(field.key)
  local typed = morf.signal("eva.form.typed." .. id, nil)
  local save
  local box, handle = P.field { id = id, width = inner, placeholder = field.title,
    on_changed = function(value) typed:set(value) end, on_accepted = function() save() end }
  save = function()
    local value = handle.text
    write(value)
    typed:set(value)
  end
  morf.effect("eva.form.fill." .. id, function()
    local value = read()
    if typed:get() == nil or typed:get() == value then handle.text = value end
  end)
  local dirty = function() local now = typed:get() return now ~= nil and now ~= read() end
  return ui.Column { width = inner, gap = P.ROW_GAP / 2,
    P.row { width = inner, height = 44, icon = field.icon, title = field.title, subtitle = field.note,
      trailing = P.button { id = id .. "-save", label = "Save", accessible_name = "Save " .. field.title,
        visible = dirty, tone = "primary", on_clicked = save } },
    box,
  }
end

local function text(field, inner)
  return line(field, inner, function() return tostring(config.get(field.key) or "") end,
    function(value) config.set(field.key, value) end)
end

local function words(field, inner)
  return line(field, inner, function() return forms.join(config.get(field.key)) end,
    function(value) config.set(field.key, forms.split(value)) end)
end

local KINDS = { bool = bool, choice = choice, number = number, text = text, words = words, list = words }

--- The sections of form `name` as blocks, for a page to place.
function M.sections(name, w)
  local inner, blocks = P.inner(w), {}
  for _, section in ipairs(forms.PAGES[name].sections) do
    local spec = { width = w, title = section.title }
    if section.note then spec[1] = F.note(inner, section.note) end
    for _, field in ipairs(section.fields) do spec[#spec + 1] = KINDS[field.kind](field, inner) end
    blocks[#blocks + 1] = P.section(spec)
  end
  return blocks
end

--- The page for form `name`.
function M.build(name, w, h)
  local page = { id = "form-" .. name:gsub("/", "-") .. "-scroll", width = w, height = h,
    active = require("presentation").active("settings." .. name) }
  for _, block in ipairs(M.sections(name, w)) do page[#page + 1] = block end
  return P.page(page)
end

return M
