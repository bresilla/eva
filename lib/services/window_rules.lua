-- Hyprland's window rules, as `hl.window_rule` takes them on 0.55: pure plans
-- over a rule kept in the settings.
--
-- A named rule added to again keeps what it had, so a rule's name carries a hash
-- of what it says: an edit is a new name, and the old one is switched off. A
-- reload forgets every rule sent at run time, so they are sent again.
local M = {}

-- What a rule can say as a switch: `{ field, title, icon }`.
M.FLAGS = {
  { "center", "Centred", "center_focus_strong" },
  { "pin", "On every workspace", "keep" },
  { "fullscreen", "Fullscreen", "fullscreen" },
  { "maximize", "Maximized", "fullscreen_exit" },
  { "no_initial_focus", "Does not take the focus", "filter_center_focus" },
  { "no_blur", "No blur behind it", "blur_off" },
  { "no_shadow", "No shadow", "layers_clear" },
  { "no_dim", "Never dimmed", "light_mode" },
  { "no_anim", "No animation", "animation" },
}

local TEXT = "^[%w_%.%*%+%-/%%%(%) ]*$"
local WORKSPACE = "^[%w_:%-%. ]*$"
local MONITOR = "^[%w_:%-%. ]*$"

local function blank(value) return value == nil or value == "" end

--- A window's class or title as a pattern matching exactly it.
function M.exact(text)
  return "^" .. tostring(text or ""):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?%{%}%|\\]", "\\%0") .. "$"
end

--- FNV-1a of `text`, as eight hex digits.
local function hash(text)
  local value = 2166136261
  for i = 1, #text do value = ((value ~ text:byte(i)) * 16777619) & 0xffffffff end
  return ("%08x"):format(value)
end

--- The text between the braces of `hl.window_rule`, or nil and why.
local function body(rule)
  local match = {}
  if not blank(rule.class) then match[#match + 1] = ("class = %q"):format(rule.class) end
  if not blank(rule.title) then match[#match + 1] = ("title = %q"):format(rule.title) end
  if #match == 0 then return nil, "A rule needs a class or a title to match" end
  for _, field in ipairs { "class", "title" } do
    if #tostring(rule[field] or "") > 256 then return nil, "Too long a pattern" end
  end
  local parts = { "match = { " .. table.concat(match, ", ") .. " }" }
  local function word(field, value) parts[#parts + 1] = ("%s = %q"):format(field, value) end
  if rule.layout == "float" then parts[#parts + 1] = "float = true"
  elseif rule.layout == "tile" then parts[#parts + 1] = "tile = true"
  elseif not blank(rule.layout) then return nil, "Float or tile" end
  for _, field in ipairs { "size", "move" } do
    local value = rule[field]
    if not blank(value) then
      if not tostring(value):match(TEXT) or not tostring(value):find("%S%s+%S") then
        return nil, (field == "size" and "Size" or "Position") .. " is two numbers, such as 800 600"
      end
      word(field, value)
    end
  end
  if not blank(rule.workspace) then
    if not tostring(rule.workspace):match(WORKSPACE) then return nil, "That is no workspace" end
    word("workspace", tostring(rule.workspace) .. (rule.silent and " silent" or ""))
  end
  if not blank(rule.monitor) then
    if not tostring(rule.monitor):match(MONITOR) then return nil, "That is no screen" end
    word("monitor", rule.monitor)
  end
  local opacity = tonumber(rule.opacity)
  if opacity and opacity < 1 then
    if opacity < .1 then return nil, "Opacity is at least 10%" end
    word("opacity", ("%.2f"):format(opacity))
  end
  for _, flag in ipairs(M.FLAGS) do
    if rule[flag[1]] == true then parts[#parts + 1] = flag[1] .. " = true" end
  end
  if #parts == 1 then return nil, "A rule needs something to do" end
  return table.concat(parts, ", ")
end

--- Why `rule` cannot be sent, or nil.
function M.refused(rule)
  local text, why = body(rule)
  return not text and why or nil
end

--- The name `rule` goes by, or nil and why.
function M.name(rule)
  local text, why = body(rule)
  if not text then return nil, why end
  return ("eva-%s-%s"):format(tostring(rule.id):gsub("%W", ""), hash(text))
end

--- The steps taking the compositor from the names in `sent` (name -> true) to
--- `rules`, and the names that leaves. A rule switched off is left out.
function M.plan(rules, sent)
  local wanted, chunks = {}, {}
  for _, rule in ipairs(rules or {}) do
    if rule.enabled ~= false then
      local text, why = body(rule)
      if text then
        local name = M.name(rule)
        wanted[name] = true
        if not sent[name] then chunks[#chunks + 1] = ("hl.window_rule({ name = %q, %s })"):format(name, text) end
      end
      if why then require("morf").log("warn", "eva: window rule " .. tostring(rule.id) .. ": " .. why) end
    end
  end
  local gone = {}
  for name in pairs(sent) do
    if not wanted[name] then gone[#gone + 1] = name end
  end
  table.sort(gone)
  for _, name in ipairs(gone) do chunks[#chunks + 1] = ("hl.window_rule({ name = %q, enabled = false })"):format(name) end
  if #chunks == 0 then return {}, wanted end
  return { { eval = table.concat(chunks, " ") } }, wanted
end

--- What `rule` does, in a line.
function M.summary(rule)
  local words = {}
  local function add(text) words[#words + 1] = text end
  if rule.layout == "float" then add("floats") elseif rule.layout == "tile" then add("tiles") end
  if not blank(rule.size) then add(tostring(rule.size):gsub("%s+", " x ")) end
  if not blank(rule.workspace) then add("workspace " .. rule.workspace .. (rule.silent and " quietly" or "")) end
  if not blank(rule.monitor) then add("on " .. rule.monitor) end
  local opacity = tonumber(rule.opacity)
  if opacity and opacity < 1 then add(("%d%%"):format(math.floor(opacity * 100 + .5))) end
  for _, flag in ipairs(M.FLAGS) do
    if rule[flag[1]] == true then add(flag[2]:lower()) end
  end
  return #words > 0 and table.concat(words, ", ") or "Does nothing yet"
end

--- A running window's name for a rule: its class, without the anchors.
function M.label(rule)
  local text = rule.name
  if blank(text) then text = rule.class end
  if blank(text) then text = rule.title end
  return (tostring(text or "A rule"):gsub("^%^", ""):gsub("%$$", ""):gsub("\\(.)", "%1"))
end

return M
