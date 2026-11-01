-- The screen held still as a picture, for a tool that reads its pixels: taken
-- with `morf.screencopy`, else grim, kept in a private folder until let go.
--
--     local freeze = require("common.freeze").new("ruler")
--     freeze.take()
--     freeze.picture:get()      -- { path, width, height }, nil until it is held
--     freeze.pixel(10, 20)      -- the colour there, or nil
--     freeze.release()
local morf = require("morf")
local capture = require("lib.shell.capture")

local M = {}

--- `name` keeps the signals apart from another tool's.
function M.new(name)
  local f = {
    picture = morf.signal(name .. ".picture", nil),
    message = morf.signal(name .. ".frozen-message", ""),
  }
  local session, preview

  local function held(path)
    local info, why = morf.image.info(path)
    if not info then
      f.message:set(tostring(why))
      return
    end
    f.picture:set { path = path, width = info.width, height = info.height }
  end

  --- Takes the first screen.
  function f.take()
    if session then session.close() end
    session = capture.session {}
    local screen = (morf.screens or {})[1] or {}
    session.snapshot(screen.name, function(ok, frame)
      if ok then held(frame.source) return end
      local path = session.path("frozen.png")
      morf.process.run({ "grim", path }, {}, function(result)
        if result and result.ok then held(path)
        else f.message:set("Could not read the screen") end
      end)
    end)
  end

  --- Lets go of the picture.
  function f.release()
    f.picture:set(nil)
    if preview then preview.close() preview = nil end
    if session then session.close() session = nil end
  end

  --- Keeps the surface `build()` makes for as long as the picture is held.
  function f.overlay(build)
    local layer
    morf.effect(name .. ".overlay", function()
      local shown = f.picture:get() ~= nil
      if shown and not layer then
        layer = build()
      elseif not shown and layer then
        require("common.frame").dismiss(layer)
        layer = nil
      end
    end)
  end

  --- Pixels of the picture to a surface pixel.
  function f.scale()
    local picture, screen = f.picture:get(), (morf.screens or {})[1]
    return picture and screen and screen.width and screen.width > 0 and picture.width / screen.width or 1
  end

  --- The colour at picture pixel `x`, `y`, held to the picture.
  function f.pixel(x, y)
    local picture = f.picture:get()
    if not picture then return nil end
    x = math.max(0, math.min(picture.width - 1, math.floor(x)))
    y = math.max(0, math.min(picture.height - 1, math.floor(y)))
    return morf.image.pixel(picture.path, x, y)
  end

  --- The same on an image worker, `done(color)`, for a picture too large to
  --- read a pixel of at once.
  function f.sample(x, y, done)
    local picture = f.picture:get()
    if not picture then return done(nil) end
    preview = preview or morf.image.preview(picture.path)
    preview.render({ { "crop", math.floor(x), math.floor(y), 1, 1 } }, function(ok, result)
      done(ok and morf.image.pixel(result.path, 0, 0) or nil)
    end)
  end

  return f
end

return M
