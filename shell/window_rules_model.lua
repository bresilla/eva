-- The rules windows open by, and how far an unfocused window dims: kept in the
-- settings and sent through lib.compositor.hyprland_config, now and after every
-- reload. No nodes. A rule acts on a window as it opens; what it says on looks
-- (opacity, blur, dimming) reaches those already open too.
local morf = require("morf")
local config = require("config")
local lib = require("lib.services.window_rules")
local hyprconf = require("lib.compositor.hyprland_config")

local M = { FLAGS = lib.FLAGS, summary = lib.summary, label = lib.label }

M.DIM_MIN, M.DIM_MAX = .05, .8

-- The rule on the edit page, and what the last save said.
M.draft = morf.signal("eva.window_rules.draft", {})
M.message = morf.signal("eva.window_rules.message", "")

--- The rules kept, in order.
function M.list()
  local rules = config.get("windows.rules")
  return type(rules) == "table" and rules or {}
end

function M.get(id)
  for _, rule in ipairs(M.list()) do if rule.id == id then return rule end end
end

local function next_id()
  local used, n = {}, 1
  for _, rule in ipairs(M.list()) do used[rule.id] = true end
  while used["r" .. n] do n = n + 1 end
  return "r" .. n
end

local function write(rules)
  local copy = {}
  for index, rule in ipairs(rules) do copy[index] = rule end
  config.set("windows.rules", copy)
end

--- Keeps `rule`: in its place when it has an id, last when not. Answers its
--- id, or nil and why.
function M.save(rule)
  local kept = {}
  for key, value in pairs(rule) do kept[key] = value end
  if kept.id == nil or kept.id == "" then kept.id = next_id() end
  local why = lib.refused(kept)
  if why then return nil, why end
  local rules, found = {}, false
  for index, row in ipairs(M.list()) do
    if row.id == kept.id then rules[index] = kept found = true else rules[index] = row end
  end
  if not found then rules[#rules + 1] = kept end
  write(rules)
  return kept.id
end

function M.remove(id)
  local rules = {}
  for _, row in ipairs(M.list()) do
    if row.id ~= id then rules[#rules + 1] = row end
  end
  write(rules)
end

--- A rule on or off, kept either way.
function M.set_enabled(id, on)
  local rules = {}
  for index, row in ipairs(M.list()) do
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    if row.id == id then copy.enabled = on == true end
    rules[index] = copy
  end
  write(rules)
end

--- A draft from a running window: its class and what it is now.
function M.from_window(address)
  local windows = require("windows_model")
  local w = windows.get(address)
  if not w then return nil end
  local rule = { class = lib.exact(w.class), title = "", layout = w.floating and "float" or "" }
  if w.floating then rule.size = ("%d %d"):format(math.floor(w.width or 0), math.floor(w.height or 0)) end
  if type(w.workspace) == "number" and w.workspace > 0 then rule.workspace = tostring(w.workspace) end
  return rule
end

-- ----------------------------------------------------------------- sending --

local sent = {}
local dimmed = false

local function push_rules()
  hyprconf.apply(function(how)
    if how ~= "lua" then return {} end
    local plan, wanted = lib.plan(M.list(), sent)
    sent = wanted
    return plan
  end)
end

local function push_dim()
  local on = config.get("windows.dim_inactive") == true
  if not on and not dimmed then return end
  dimmed = on
  hyprconf.apply(function(how)
    return hyprconf.options_plan({ { "decoration:dim_inactive", "bool", on },
      { "decoration:dim_strength", "float", config.get("windows.dim_strength") } }, how)
  end)
end

--- Follows the rules and the dimming, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  if not require("input_model").available() then return end
  hyprconf.on_reload(function()
    sent, dimmed = {}, false
    push_rules()
    push_dim()
  end)
  morf.effect("eva.window_rules.follow", function()
    M.list()
    morf.time.timer(1, push_rules, false)
  end)
  morf.effect("eva.window_rules.dim", function()
    config.get("windows.dim_inactive")
    config.get("windows.dim_strength")
    morf.time.timer(1, push_dim, false)
  end)
end

-- --------------------------------------------------------------- the pages --

--- Opens the edit page on `rule`, a new one with no id.
function M.edit(rule)
  M.message:set("")
  M.draft:set(rule or {})
  require("utilities").request("windows/rule")
end

--- A change to the draft.
function M.change(field, value)
  local copy = {}
  for key, row in pairs(M.draft:get()) do copy[key] = row end
  copy[field] = value
  M.draft:set(copy)
end

--- Keeps the draft and goes back to the list; false with why on the page.
function M.commit()
  local id, why = M.save(M.draft:get())
  if not id then M.message:set(why) return false end
  M.message:set("")
  require("utilities").request("windows/rules")
  return true
end

function M.delete()
  local id = M.draft:get().id
  if id then M.remove(id) end
  require("utilities").request("windows/rules")
end

--- The screens a rule can send a window to, as choices.
function M.screens()
  local out = { { "", "public", "Any" } }
  for _, m in ipairs(require("windows_model").monitors()) do
    out[#out + 1] = { m.name, "monitor", m.name }
  end
  return out
end

return M
