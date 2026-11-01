-- What accessibility asks of the compositor: a colour filter as a screen
-- shader, the screen's zoom, sticky keys as an xkb keymap whose modifiers
-- latch, and mouse keys as number pad bindings. Plans over
-- lib.compositor.hyprland_config, so each is tried in both of Hyprland's
-- languages and nothing writes the person's configuration.
local morf = require("morf")
local host = require("lib.services.host")
local input = require("lib.services.input_config")

local M = {}

M.FILTERS = { { "none", "block", "None" }, { "grayscale", "filter_b_and_w", "Grayscale" }, { "invert", "invert_colors", "Invert" },
  { "protanopia", "palette", "Protanopia" }, { "deuteranopia", "palette", "Deuteranopia" }, { "tritanopia", "palette", "Tritanopia" } }

-- The colour blindness matrices: linear RGB shifted into what a person with
-- that vision can tell apart.
local MATRIX = {
  protanopia = "0.152,1.053,-0.205, 0.115,0.786,0.099, -0.004,-0.048,1.052",
  deuteranopia = "0.367,0.861,-0.228, 0.280,0.673,0.047, -0.012,0.043,0.969",
  tritanopia = "1.256,-0.077,-0.179, -0.078,0.931,0.148, 0.005,0.691,0.304",
}

--- A filter's shader source, or nil for none.
function M.shader(filter)
  local head = "#version 300 es\nprecision highp float;\nin vec2 v_texcoord;\nuniform sampler2D tex;\nout vec4 fragColor;\n"
  local body
  if filter == "grayscale" then
    body = "float y = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));\n  fragColor = vec4(y, y, y, c.a);"
  elseif filter == "invert" then
    body = "fragColor = vec4(1.0 - c.rgb, c.a);"
  elseif MATRIX[filter] then
    body = "mat3 m = transpose(mat3(" .. MATRIX[filter] .. "));\n  fragColor = vec4(clamp(m * c.rgb, 0.0, 1.0), c.a);"
  else
    return nil
  end
  return head .. "void main() {\n  vec4 c = texture(tex, v_texcoord);\n  " .. body .. "\n}\n"
end

--- Where a filter's shader is written.
function M.shader_path(filter) return morf.paths.state("eva/shaders/" .. filter .. ".frag") end

--- Writes the shader and gives the step that turns it on. "none" clears it.
function M.filter_step(filter, how)
  local source = M.shader(filter)
  if not source then return input.path_step("decoration:screen_shader", "", how) end
  local path = M.shader_path(filter)
  if not host.held("write shader " .. filter) then
    morf.fs.mkdir((path:gsub("/[^/]+$", "")))
    morf.fs.write(path, source)
  end
  return input.path_step("decoration:screen_shader", path, how)
end

-- ------------------------------------------------------------- sticky keys --

--- A compiled keymap with its modifiers latching, and how many changed: every
--- modifier key's action in the compatibility section has this one form.
function M.sticky_keymap(text)
  return tostring(text):gsub("SetMods%(modifiers=([%w_]+),clearLocks%)", "LatchMods(modifiers=%1,clearLocks,latchToLock)")
end

--- Where the keymap is written.
function M.keymap_path() return morf.paths.state("eva/keymaps/sticky.xkb") end

--- Whether sticky keys can be built here.
function M.can_stick() return host.installed("xkbcli") end

--- Compiles the layouts into a latching keymap: `done(path, err)`.
function M.build_sticky(layouts, options, done)
  local layout, variant = input.layout_words(layouts)
  local argv = { "xkbcli", "compile-keymap", "--layout", layout ~= "" and layout or "us" }
  if variant:gsub(",", "") ~= "" then argv[#argv + 1] = "--variant" argv[#argv + 1] = variant end
  if (options or "") ~= "" then argv[#argv + 1] = "--options" argv[#argv + 1] = options end
  host.read(argv, function(text, why)
    if not text then return done(nil, why) end
    local keymap, changed = M.sticky_keymap(text)
    if changed == 0 then return done(nil, "This keymap has no modifiers to latch") end
    local path = M.keymap_path()
    if not host.held("write sticky keymap") then
      morf.fs.mkdir((path:gsub("/[^/]+$", "")))
      morf.fs.write(path, keymap)
    end
    done(path)
  end)
end

-- -------------------------------------------------------------- mouse keys --

-- The number pad as a pointer: each key and how far it moves.
local STEP = 12
M.MOUSE_KEYS = { { "KP_Left", -STEP, 0 }, { "KP_Right", STEP, 0 }, { "KP_Up", 0, -STEP }, { "KP_Down", 0, STEP },
  { "KP_Home", -STEP, -STEP }, { "KP_Prior", STEP, -STEP }, { "KP_End", -STEP, STEP }, { "KP_Next", STEP, STEP } }

function M.can_mouse_keys() return host.installed("wlrctl") end

--- The steps binding or unbinding the keys. The centre key clicks.
function M.mouse_key_steps(on, how)
  local steps, lua = {}, {}
  local function bind(key, command, repeating)
    if how == "lua" then
      if on then
        lua[#lua + 1] = ('hl.bind(%q, hl.dsp.exec_cmd(%q)%s)'):format(key, command, repeating and ", { repeating = true }" or "")
      else
        lua[#lua + 1] = ("hl.unbind(%q)"):format(key)
      end
    elseif on then
      steps[#steps + 1] = { keyword = repeating and "binde" or "bind", value = (",%s,exec,%s"):format(key, command) }
    else
      steps[#steps + 1] = { keyword = "unbind", value = "," .. key }
    end
  end
  for _, row in ipairs(M.MOUSE_KEYS) do bind(row[1], ("wlrctl pointer move %d %d"):format(row[2], row[3]), true) end
  bind("KP_Begin", "wlrctl pointer click", false)
  if how == "lua" then return { { eval = table.concat(lua, " ") } } end
  return steps
end

return M
