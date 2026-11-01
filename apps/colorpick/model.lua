-- eva-colorpick's state and actions: the frozen picture, the colour under the
-- pointer, the recent colours. No nodes.
local morf = require("morf")
local config = require("config")
local formats = require("formats")
local frozen = require("common.freeze").new("colorpick")

local M = {
  picture = frozen.picture,
  hover = morf.signal("colorpick.hover", nil),
  picked = morf.signal("colorpick.picked", ""),
  format = morf.signal("colorpick.format", "hex"),
  recent = morf.signal("colorpick.recent", {}),
  message = morf.signal("colorpick.message", ""),
}

M.RECENT = 12
M.ZOOM = 8

morf.effect("colorpick.frozen-message", function()
  local words = frozen.message:get()
  if words ~= "" then M.message:set(words) end
end)

local function dry()
  local value = morf.env("EVA_DRY_RUN")
  return value ~= nil and value ~= "" and value ~= "0"
end

local function recent_path()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/colorpick/recent.json"
end

function M.load()
  local ok, list = pcall(function() return morf.json.decode(morf.fs.read(recent_path())) end)
  if ok and type(list) == "table" then M.recent:set(list) end
end

local function remember(hex)
  local list = { hex }
  for _, old in ipairs(M.recent:get()) do
    if old ~= hex and #list < M.RECENT then list[#list + 1] = old end
  end
  M.recent:set(list)
  morf.fs.write(recent_path(), morf.json.encode(list), { atomic = true, parents = true })
end

--- Holds the screen still as a picture.
function M.freeze()
  M.hover:set(nil)
  frozen.take()
end

--- Lets go of the picture.
function M.thaw()
  M.hover:set(nil)
  frozen.release()
end

M.scale = frozen.scale
M.overlay = frozen.overlay

--- The pointer at surface `x`, `y`; `scale` is pixels of the picture to a
--- surface pixel.
function M.point(x, y, scale)
  local picture = M.picture:get()
  if not picture then return end
  local px = math.max(0, math.min(picture.width - 1, math.floor(x * (scale or 1))))
  local py = math.max(0, math.min(picture.height - 1, math.floor(y * (scale or 1))))
  local function hover(color)
    M.hover:set { x = x, y = y, px = px, py = py, hex = color and color:hex() or "#000000" }
  end
  local color = frozen.pixel(px, py)
  if color then hover(color) else frozen.sample(px, py, hover) end
end

--- `hex` in the chosen format, on the clipboard.
function M.copy(hex)
  local words = formats.write(hex, M.format:get())
  if not dry() then morf.clipboard.set(words) end
  M.message:set("Copied " .. words)
  return words
end

--- Takes the colour under the pointer.
function M.pick()
  local hover = M.hover:get()
  if not hover then return nil end
  M.picked:set(hover.hex)
  remember(hover.hex)
  M.copy(hover.hex)
  M.thaw()
  return hover.hex
end

--- Sets the shell's colour source, `theme.source`, to `hex`.
function M.send_to_lule(hex)
  if not dry() then config.set("theme.source", hex) end
  M.message:set("Sent " .. hex .. " to the theme")
end

return M
