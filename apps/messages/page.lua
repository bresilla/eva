-- eva-messages' page in the Tools window: text threads with delivery marks,
-- one open, and a line to write. The shell receives the texts and notifies.
local model = require("apps.messages.model")

local M = {}

--- The page, `w` by `h`.
function M.build(w, h)
  return require("apps.messages.view").build(function() return w end, function() return h end)
end

--- `eva-messages sms:NUMBER`: that thread open.
function M.open(args)
  if args[1] and args[1] ~= "" then model.show((args[1]:gsub("^sms:", ""))) end
end

--- Delete and back, in the window's head, while a thread is open.
function M.actions() return require("apps.messages.view").actions() end

-- `morf ipc call tool messages VERB`.
M.verbs = {
  state = function()
    return { threads = model.threads(), open = model.open:get(), thread = model.thread(),
      draft = model.draft:get(), can_send = model.can_send(), composing = model.composing:get() }
  end,
  fit = function(words, size, limit)
    return require("apps.messages.view").fit(words, tonumber(size), tonumber(limit))
  end,
  show = function(number) model.show(number) return true end,
  close = function() model.close() return true end,
  compose = function(number) model.compose(number) return true end,
  write = function(text) model.draft:set(text) return true end,
  send = function() return model.send() end,
  fake = function(what, ...)
    if not model.standin then error("no stand-in") end
    return model.standin[what](...)
  end,
}

return M
