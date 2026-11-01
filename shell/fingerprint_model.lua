-- The Fingerprints page's state: the reader, and how what it holds reaches the
-- lock. The lock listens on the `eva-lock-finger` PAM stack (lib/shell/auth), which
-- nix/nixos/authentication.nix makes where fprintd is on, and
-- helpers/pam/readers.sh elsewhere. No nodes.
local morf = require("morf")
local config = require("config")
local service = require("lib.services.fingerprint")

local M = { FINGERS = service.FINGERS, name_of = service.name_of }

local reader

local function connected()
  if not reader then reader = service.new { user = morf.env("USER") or "" } end
  return reader
end

--- What the reader says now.
function M.state() return connected().state:get() end

function M.refresh() connected().refresh() end
function M.enroll(finger) return connected().enroll(finger) end
function M.cancel() connected().cancel() end
function M.remove(finger) return connected().remove(finger) end

--- The fingers that can still be added: `{ id, name }` each.
function M.spare()
  local held, out = {}, {}
  for _, finger in ipairs(M.state().fingers or {}) do held[finger] = true end
  for _, row in ipairs(M.FINGERS) do
    if not held[row[1]] then out[#out + 1] = { id = row[1], name = row[2] } end
  end
  return out
end

--- Whether this machine has the PAM stack the lock listens to a finger on.
function M.stack()
  local fake = morf.env("EVA_FAKE_FINGER_STACK")
  if fake and fake ~= "" then return fake == "1" end
  for _, service_name in ipairs(require("lib.shell.auth").lock_readers()) do
    if service_name == "eva-lock-finger" then return true end
  end
  return false
end

--- How a finger reaches the lock here, in words: `title`, `text`.
function M.join()
  local nixos = require("lib.services.host").nixos()
  if not M.stack() then
    return { title = "The lock does not listen yet",
      text = nixos and "Set services.fprintd.enable = true and rebuild" or "Run helpers/pam/readers.sh as root" }
  end
  if config.get("lock.readers") ~= true then
    return { title = "The lock's readers are off", text = "Turn them on below and a finger opens it" }
  end
  return { title = "A finger opens the lock", text = "Your password still works, and comes first after a restart" }
end

return M
