-- A lan-mouse daemon for EVA_FAKE_SYSTEM: two machines, one allowed, one more
-- asking to connect, answering the socket's requests in its own JSON, a turn
-- later as a socket would. Nothing leaves the process.
local morf = require("morf")

local M = {}

local SURF = "3a:9f:1c:77:e0:42:b8:d5:6e:01:9c:f4:2a:7b:83:d0:5c:11:e9:a6:4f:20:b7:38:c2:95:0d:6a:f1:87:4e:3b"
local ASKING = "c7:21:5e:90:ab:3d:f6:08:72:1b:e4:59:a0:cd:36:8f:12:e7:4b:d9:60:aa:5f:03:b8:94:2c:71:de:06:8a:f5"
local OWN = "8e:4d:02:b9:71:c6:3f:a8:15:e0:9d:67:2b:f4:c1:58:a3:0e:76:db:49:12:8c:f0:65:b7:3a:d1:9e:24:07:6c"

local running = true
local state = {
  next = 3,
  clients = {
    { 1, { hostname = "surf", fix_ips = {}, port = 4242, pos = "right" },
      { active = true, alive = true, ips = { "100.68.8.12" }, dns_ips = {} } },
    { 2, { hostname = "iridium", fix_ips = {}, port = 4242, pos = "left" },
      { active = false, alive = false, ips = {}, dns_ips = {} } },
  },
  allowed = { [SURF] = "surf" },
}

function M.running() return running end
function M.set_running(on) running = on == true end

local function find(handle)
  for _, row in ipairs(state.clients) do if row[1] == handle then return row end end
end

--- A link to the stand-in daemon: `on_line(text)` hears it.
function M.connect(on_line)
  local open, queue = true, {}
  -- Lines go out in the order said, a turn later.
  local function flush()
    local lines = queue
    queue = {}
    for _, line in ipairs(lines) do if open then on_line(line) end end
  end
  local function say(event)
    queue[#queue + 1] = morf.json.encode(event)
    if #queue == 1 then morf.time.timer(1, flush, false) end
  end
  local function changed(row) say { State = row } end
  local function handle(request)
    if request == "Sync" then
      say { Enumerate = state.clients }
      say { EmulationStatus = "Enabled" }
      say { CaptureStatus = "Enabled" }
      say { PortChanged = { 4242 } }
      say { PublicKeyFingerprint = OWN }
      say { AuthorizedUpdated = state.allowed }
      if not state.allowed[ASKING] then say { ConnectionAttempt = { fingerprint = ASKING } } end
      return
    end
    if request == "Create" then
      local row = { state.next, { fix_ips = {}, port = 4242, pos = "left" },
        { active = false, alive = false, ips = {}, dns_ips = {} } }
      state.next = state.next + 1
      state.clients[#state.clients + 1] = row
      return say { Created = row }
    end
    if type(request) ~= "table" then return end
    local name, body = next(request)
    if name == "Activate" or name == "UpdateHostname" or name == "UpdatePosition" then
      local row = find(body[1])
      if not row then return say { NoSuchClient = body[1] } end
      if name == "Activate" then row[3].active = body[2] == true row[3].alive = body[2] == true end
      if name == "UpdateHostname" then row[2].hostname = body[2] end
      if name == "UpdatePosition" then row[2].pos = body[2] end
      return changed(row)
    end
    if name == "Delete" then
      for i, row in ipairs(state.clients) do
        if row[1] == body then table.remove(state.clients, i) return say { Deleted = body } end
      end
      return
    end
    if name == "AuthorizeKey" then
      state.allowed[body[2]] = body[1]
      return say { AuthorizedUpdated = state.allowed }
    end
    if name == "RemoveAuthorizedKey" then
      state.allowed[body] = nil
      return say { AuthorizedUpdated = state.allowed }
    end
  end
  local link = {}
  function link:send(text)
    for line in tostring(text):gmatch("[^\n]+") do
      local ok, request = pcall(morf.json.decode, line)
      if ok then handle(request) end
    end
    return true
  end
  function link:connected() return open end
  function link:close() open = false end
  return link
end

return M
