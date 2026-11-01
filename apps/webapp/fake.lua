-- A stand-in for the web, with EVA_FAKE_WEBAPP=1: `icon.test` names a picture on
-- its page, `ico.test` keeps a PNG in its favicon.ico, `plain.test` has no icon
-- at all. EVA_FAKE_WEBAPP_PICTURE is the file that picture is.
local morf = require("morf")

local M = {}

local function bytes_le(value, count)
  local out = {}
  for index = 1, count do
    out[index] = string.char(value % 256)
    value = value // 256
  end
  return table.concat(out)
end

--- `png` as an icon file holding it.
function M.ico(png)
  return "\0\0\1\0" .. bytes_le(1, 2) .. "\32\32\0\0" .. bytes_le(1, 2) .. bytes_le(32, 2) .. bytes_le(#png, 4)
    .. bytes_le(22, 4) .. png
end

--- Puts the stand-in where the model asks.
function M.install()
  local picture = morf.fs.read(morf.env("EVA_FAKE_WEBAPP_PICTURE") or "") or ""
  local pages = {
    ["https://icon.test"] = '<html><head><link href="/static/mark.png" rel="icon" sizes="64x64"></head></html>',
    ["https://icon.test/static/mark.png"] = picture,
    ["https://ico.test"] = "<html></html>",
    ["https://ico.test/favicon.ico"] = M.ico(picture),
    ["https://plain.test"] = "<html></html>",
  }
  morf.http = {
    get = function(url, _, done)
      local body = pages[url]
      morf.time.timer(1, function()
        done { ok = body ~= nil, status = body and 200 or 404, body = body or "" }
      end, false)
    end,
  }
end

return M
