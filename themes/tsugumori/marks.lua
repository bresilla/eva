-- The chrome a boot pass drives, by node: cards' brackets and outlines,
-- captions' plates and rules, and readings that replay (`play(delay)` -> stop),
-- held until the node is destroyed.
local R = { cards = {}, captions = {}, values = {}, OUTLINE = .3 }

local function read(node) return node.layout_x, node.layout_y, node.layout_width, node.layout_height end
--- `node`'s last layout box, or nil (and false for a node that is gone).
function R.box(node)
  local ok, x, y, w, h = pcall(read, node)
  if not ok then return nil, false end
  if not x or not y or not w or not h or w <= 0 or h <= 0 then return nil, true end
  return x, y, w, h
end

--- `set`'s nodes laid out over `host`, top first, with where each top stands (0..1).
function R.within(set, host)
  local hx, hy, hw, hh = R.box(host)
  local out = {}
  if not hx then return out, nil end
  local gone
  for node, entry in pairs(set) do
    local x, y, w, h = R.box(node)
    if y == false then
      gone = gone or {}
      gone[#gone + 1] = node
    elseif x and x < hx + hw and x + w > hx and y < hy + hh and y + h > hy then
      out[#out + 1] = { node = node, entry = entry, x = x, y = y, w = w, h = h,
        at = math.max(0, math.min(1, (y - hy) / hh)) }
    end
  end
  for _, node in ipairs(gone or {}) do set[node] = nil end
  table.sort(out, function(a, b)
    if math.abs(a.y - b.y) > 6 then return a.y < b.y end
    return a.x < b.x
  end)
  return out, { x = hx, y = hy, w = hw, h = hh }
end

return R
