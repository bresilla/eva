-- A change to a running Hyprland in whichever of its two languages it takes: a
-- Lua-configured one answers an `eval` with "ok" and refuses `keyword`, a classic
-- one the other way round.
--
--   hypr.eval_or(hyprland, chunk, function() hyprland.keyword(name, value) end)
--
-- `hyprland` is lib.compositor.hyprland, or anything with its `eval(chunk, done)`.
local M = {}

--- Whether `reply` is Hyprland saying a chunk was taken.
function M.took(reply)
  return type(reply) == "string" and reply:match("^%s*ok%s*$") ~= nil
end

--- Says `chunk`. Then `taken()` where it took, if given, and `classic()` where
--- it did not.
function M.eval_or(hyprland, chunk, classic, taken)
  hyprland.eval(chunk, function(reply)
    if not M.took(reply) then classic()
    elseif taken then taken() end
  end)
end

return M
