-- eva-qr's page in the Tools window: a code from text or a Wi-Fi network, on
-- its plate, copied, saved, or alone over the whole page for a camera.
local morf = require("morf")
local ui = require("morf.ui")
local model = require("apps.qr.model")

local M = {}

local loaded = false
local function load()
  if loaded then return end
  loaded = true
  model.load_saved()
end

--- The page, `w` by `h`.
function M.build(w, h)
  load()
  local view = require("apps.qr.view")
  return ui.Item { width = w, height = h,
    view.build(function() return w end, function() return h end), view.full() }
end

--- `eva-qr TEXT`, `eva-qr wifi SSID [...]`: the code of those words. With
--- `--input FILE` last, the text or the network's password is in that private
--- file, read once and removed.
function M.open(args)
  local words, input = {}, nil
  local index = 1
  while args[index] do
    if args[index] == "--input" and args[index + 1] then
      local ok, text = pcall(morf.fs.read, args[index + 1])
      input = ok and text or nil
      pcall(morf.fs.remove, args[index + 1])
      index = index + 2
    else
      words[#words + 1] = args[index]
      index = index + 1
    end
  end
  load()
  model.take(words, input)
  model.encode()
end

function M.shown(on) if not on then model.full:set(false) end end

-- `morf ipc call tool qr VERB`.
M.verbs = {
  state = function() return model.state() end,
  text = function(...)
    model.mode:set(1)
    model.text:set(table.concat({ ... }, " "))
    return true
  end,
  wifi = function(ssid)
    model.mode:set(2)
    model.ssid:set(ssid or "")
    return true
  end,
  security = function(index) model.security:set(tonumber(index)) return true end,
  hidden = function(how) model.hidden:set(how == "on") return true end,
  level = function(index) model.level:set(tonumber(index)) return true end,
  focus = function() require("apps.qr.view").password_input.focus = true return true end,
  copy = function() return model.copy() end,
  save = function(path) model.save(path or model.default_path()) return true end,
  show = function(how) model.full:set(how ~= "off") return true end,
  pick = function(name) model.pick_saved(name) return true end,
}

return M
