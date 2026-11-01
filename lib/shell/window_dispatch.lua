-- What Hyprland is told to do to one window, by its address: the window menu's
-- buttons and eva-kill send their steps here. A step is `{ lua = { "window.pin",
-- {...} }, conf = { dispatcher, argument } }`, the Lua form for a Lua-configured
-- Hyprland and the classic one elsewhere; `global` marks a step on the focused
-- window. EVA_DRY_RUN=1 logs what would be dispatched instead.
local morf = require("morf")
local hypr = require("lib.util.hypr")

local M = {}

--- The step that ends a window outright.
M.KILL = { lua = { "window.kill", {} }, conf = { "killwindow", "$W" } }

local lua_config
--- `done(lua)`: whether this Hyprland is configured in Lua, asked once.
function M.flavour(done)
  if lua_config ~= nil then return done(lua_config) end
  local ok, config = pcall(require, "lib.compositor.hyprland_config")
  if not ok then lua_config = false return done(false) end
  config.flavour(function(kind) lua_config = kind == "lua" done(lua_config) end)
end
local flavour = M.flavour

local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

local function quoted(value) return ("%q"):format(tostring(value)) end
--- `value` as a string in a Lua chunk.
M.quoted = quoted
local function fields(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = k .. " = " .. (type(v) == "string" and quoted(v) or tostring(v)) end
  table.sort(out)
  return "{ " .. table.concat(out, ", ") .. " }"
end

--- Runs `steps` on the window at `address`; `done(ok)` once the compositor has
--- heard the last. False where there is no address. `options.sent(chunk)` hears
--- what goes to a Lua Hyprland, `options.live` runs under a dry run all the same.
function M.run(address, steps, done, options)
  done = done or function() end
  options = options or {}
  if address == "" or address == nil then done(false) return false end
  local hyprland = require("lib.compositor.hyprland")
  local selector = "address:" .. address
  if dry_run() and not options.live then
    local names = {}
    for _, s in ipairs(steps) do names[#names + 1] = s.lua[1] end
    morf.log("info", "eva: window menu (dry run): " .. table.concat(names, ", ") .. " on " .. address)
    done(true)
    return true
  end
  flavour(function(lua)
    if lua then
      local chunk = {}
      for _, s in ipairs(steps) do
        if s.global and #chunk == 0 then chunk[1] = ("hl.dispatch(hl.dsp.focus({ window = %s }))"):format(quoted(selector)) end
      end
      for _, s in ipairs(steps) do
        local args = s.lua[2]
        if type(args) == "string" then args = quoted(args)
        else
          local t = {}
          for k, v in pairs(args or {}) do t[k] = v end
          if not s.global then t.window = selector end
          args = fields(t)
        end
        chunk[#chunk + 1] = ("hl.dispatch(hl.dsp.%s(%s))"):format(s.lua[1], args)
      end
      if options.sent then options.sent(table.concat(chunk, " ")) end
      hyprland.eval(table.concat(chunk, " "), function(reply, err)
        if err or (reply and not hypr.took(reply)) then
          morf.log("warn", "eva: window menu: " .. tostring(err or reply))
          done(false)
        else
          done(true)
        end
      end)
    else
      -- Classic dispatchers mostly act on the focused window: focus it first.
      local queue = { { "focuswindow", "$W" } }
      for _, s in ipairs(steps) do queue[#queue + 1] = s.conf end
      local function step(i)
        local s = queue[i]
        if not s then return done(true) end
        local arg = s[2] and (s[2]:gsub("%$W", selector)) or nil
        hyprland.dispatch(s[1], arg, function() step(i + 1) end)
      end
      step(1)
    end
  end)
  return true
end

return M
