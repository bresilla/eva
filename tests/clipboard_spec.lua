-- eva-clipboard: what is kept and what is never read, pins, the limit, the
-- search, and that the history stays private.
--
--     morf test --no-dbus tests/clipboard_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local ENV = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" }

-- The tool, with a clipboard offer to hand it.
local HOST = morf.fs.read(ROOT .. "apps/clipboard/app.lua") .. [[
  local reads = 0
  morf.ipc.offer = function(mime, text)
    model.offer { mime_types = { mime }, read = function(_, kind, cb)
      reads = reads + 1
      cb(text, nil)
    end }
    return true
  end
  morf.ipc.reads = function() return reads end
  morf.ipc.ids = function()
    local out = {}
    for _, item in ipairs(model.items:get()) do out[#out + 1] = item.text or item.kind end
    return table.concat(out, ",")
  end
  morf.ipc.limit = function(n) model.LIMIT = tonumber(n) return true end
  morf.ipc.search = function(q) model.query:set(q) return #model.found() end
  morf.ipc.first = function() return model.items:get()[1].id end
]]

local function tool()
  local state = morf.env("XDG_STATE_HOME") .. "/clip-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  local env = { XDG_STATE_HOME = state }
  for key, value in pairs(ENV) do env[key] = value end
  test.load("../apps/clipboard/app.lua", { source = HOST, env = env })
  test.settle(300)
  return state
end

test.it("keeps text, newest first, and one of each", function()
  tool()
  test.ipc("text", "one")
  test.ipc("text", "two")
  test.ipc("text", "one")
  test.eq(test.ipc("ids"), "one,two")
end)

test.it("never reads what a password manager marks", function()
  local state = tool()
  test.ipc("offer", "x-kde-passwordManagerHint", "hunter2")
  test.eq(test.ipc("reads"), 0)
  test.eq(test.ipc("ids"), "")
  test.falsy((morf.fs.read(state .. "/eva/clipboard/history.json") or ""):find("hunter2", 1, true))
end)

test.it("reads an ordinary offer", function()
  tool()
  test.ipc("offer", "text/plain", "hello")
  test.eq(test.ipc("reads"), 1)
  test.eq(test.ipc("ids"), "hello")
end)

test.it("keeps a pin on top and through the limit", function()
  tool()
  test.ipc("limit", "2")
  test.ipc("text", "keep me")
  test.ipc("pin", test.ipc("first"))
  test.ipc("text", "b")
  test.ipc("text", "c")
  test.ipc("text", "d")
  test.eq(test.ipc("ids"), "keep me,d,c")
end)

test.it("clears all but the pins", function()
  tool()
  test.ipc("text", "pinned")
  test.ipc("pin", test.ipc("first"))
  test.ipc("text", "gone")
  test.ipc("clear")
  test.eq(test.ipc("ids"), "pinned")
end)

test.it("searches the text", function()
  tool()
  test.ipc("text", "Hello there")
  test.ipc("text", "something else")
  test.eq(test.ipc("search", "hello"), 1)
  test.eq(test.ipc("search", "nothing"), 0)
end)

test.it("remembers across a start", function()
  local state = tool()
  test.ipc("text", "still here")
  local env = { XDG_STATE_HOME = state }
  for key, value in pairs(ENV) do env[key] = value end
  test.load("../apps/clipboard/app.lua", { source = HOST, env = env })
  test.settle(300)
  test.eq(test.ipc("ids"), "still here")
end)

test.it("keeps the store's documented shape, for readers outside this tool", function()
  local state = tool()
  test.ipc("text", "older")
  test.ipc("text", "pin me")
  test.ipc("pin", test.ipc("first"))
  test.ipc("text", "newest")
  local entries = morf.json.decode(morf.fs.read(state .. "/eva/clipboard/history.json"))
  test.eq(#entries, 3)
  test.eq(entries[1].text, "pin me")
  test.eq(entries[1].pinned, true)
  test.eq(entries[2].text, "newest")
  test.eq(entries[3].text, "older")
  for _, entry in ipairs(entries) do
    test.eq(type(entry.id), "string")
    test.eq(entry.kind, "text")
    test.eq(math.type(entry.time) ~= nil, true)
  end
  test.eq(entries[2].pinned, nil)
end)

test.it("keeps its history readable by its owner alone", function()
  local state = tool()
  test.ipc("text", "private")
  local info = morf.fs.stat(state .. "/eva/clipboard/history.json")
  test.eq((info.mode or 0) & 63, 0)
end)

test.it("shows a word when there is nothing, and no error", function()
  tool()
  test.truthy(test.find { id = "clipboard-empty" })
  test.eq(#test.logs("error"), 0)
  test.eq(#test.logs("warn"), 0)
end)
