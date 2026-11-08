-- eva-webapp's page in the Tools window: the sites made into apps, each with its
-- own desktop entry and icon, and a form for another. EVA_FAKE_WEBAPP=1 puts a
-- stand-in where the web would be.
local morf = require("morf")
local model = require("apps.webapp.model")

local M = {}

local ready = false
local function load()
  if ready then return end
  ready = true
  if morf.env("EVA_FAKE_WEBAPP") == "1" then require("apps.webapp.fake").install() end
  model.refresh()
end

--- The page, `w` by `h`.
function M.build(w, h)
  load()
  return require("apps.webapp.view").build(function() return w end, function() return h end)
end

-- `morf ipc call tool webapp VERB`.
M.verbs = {
  state = function()
    load()
    return { rows = model.rows:get(), message = model.message:get(), busy = model.busy:get() }
  end,
  add = function(name, url)
    load()
    model.name:set(name or "")
    model.url:set(url or "")
    model.submit()
    return true
  end,
  remove = function(name)
    load()
    local row = model.find(name)
    if row then model.remove(row) end
    return row ~= nil
  end,
}

return M
