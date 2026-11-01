-- Recent files, as applications record them for each other:
-- $XDG_DATA_HOME/recently-used.xbel, newest first.

local morf = require("morf")

local M = {}

--- Where the list lives.
function M.path()
  local data = (morf.env and morf.env("XDG_DATA_HOME")) or (morf.fs.home() .. "/.local/share")
  return data .. "/recently-used.xbel"
end

local function stamp(value)
  if not value or value == "" then return 0 end
  local ok, t = pcall(morf.time.parse, value)
  return ok and t or 0
end

--- The local files in `text`: `{ path, at, mime }` each, newest first.
function M.parse(text, limit)
  local out, seen = {}, {}
  for head, body in tostring(text or ""):gmatch("<bookmark%s+(.-)>(.-)</bookmark>") do
    local href = head:match('href="([^"]*)"')
    if href and href:sub(1, 7) == "file://" then
      local path = morf.encoding.url_decode(href:sub(8)):gsub("&amp;", "&"):gsub("&apos;", "'")
      if not seen[path] then
        seen[path] = true
        local at = math.max(stamp(head:match('visited="([^"]*)"')), stamp(head:match('modified="([^"]*)"')),
          stamp(head:match('added="([^"]*)"')))
        out[#out + 1] = { path = path, at = at, mime = body:match('mime%-type%s+type="([^"]*)"') }
      end
    end
  end
  table.sort(out, function(a, b) return a.at > b.at end)
  if limit then
    for i = #out, limit + 1, -1 do out[i] = nil end
  end
  return out
end

--- What the list holds now.
function M.read(limit)
  local ok, text = pcall(morf.fs.read, M.path())
  return M.parse(ok and text or "", limit)
end

return M
