-- Reading a picture: the words in it with tesseract, a QR code with zbarimg.
-- A result goes to the clipboard and nowhere else.
local morf = require("morf")

local M = {}

M.TOOLS = { ocr = "tesseract", qr = "zbarimg" }

local function trimmed(text) return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function command(kind, path)
  if kind == "ocr" then return { "tesseract", path, "-" } end
  return { "zbarimg", "--quiet", "--raw", path }
end

--- `cb({ ocr = bool, qr = bool })`: which readers are installed.
function M.available(cb)
  local found, waiting = {}, 0
  for kind, program in pairs(M.TOOLS) do
    waiting = waiting + 1
    morf.process.run({ "sh", "-c", 'command -v "$0"', program }, {}, function(result)
      found[kind] = result ~= nil and result.ok == true
      waiting = waiting - 1
      if waiting == 0 then cb(found) end
    end)
  end
end

--- Reads `path` by `kind`, "ocr" or "qr", and copies what it found:
--- `cb(ok, words or why)`.
function M.read(kind, path, cb)
  local dry = morf.env("EVA_DRY_RUN")
  morf.process.run(command(kind, path), {}, function(result)
    local words = result and result.ok and trimmed(result.stdout) or ""
    if words == "" then
      cb(false, kind == "ocr" and "No text found" or "No code found")
      return
    end
    if dry == nil or dry == "" or dry == "0" then morf.clipboard.set(words) end
    cb(true, words)
  end)
end

return M
