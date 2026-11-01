-- The SIM asking for its PIN or PUK. No nodes. The digits stay in a local here
-- and go to ModemManager over the bus: only how many there are is a signal.
--
--   local sim = require("models.phone_sim").new { mobile = m }
--   sim.asking()     -- whether to show the prompt
--   sim.step:get()   -- pin, puk, new or confirm
--   sim.count:get()  -- digits so far
--   sim.digit("1")  sim.back()  sim.submit()  sim.later()
local morf = require("morf")

local M = { MIN_PIN = 4, MAX_PIN = 8, PUK = 8 }

local serial = 0

function M.new(options)
  serial = serial + 1
  local name = "eva.sim." .. serial .. "."
  local mobile = options.mobile
  local sim = {
    step = morf.signal(name .. "step", "pin"),
    count = morf.signal(name .. "count", 0),
    message = morf.signal(name .. "message", ""),
    busy = morf.signal(name .. "busy", false),
    put_off = morf.signal(name .. "later", false),
  }
  local draft, puk, chosen = "", "", ""

  local function clear()
    draft = ""
    sim.count:set(0)
  end

  --- What the SIM wants right now: sim-pin, sim-puk or "".
  function sim.wanted() return mobile.state.unlock end

  --- Whether the prompt belongs on the screen.
  function sim.asking() return sim.wanted() ~= "" and not sim.put_off:get() end

  morf.effect(name .. "follow", function()
    local wanted = sim.wanted()
    if wanted == "sim-pin" then sim.step:set("pin")
    elseif wanted == "sim-puk" then
      local step = sim.step:get()
      if step ~= "new" and step ~= "confirm" then sim.step:set("puk") end
    end
    if wanted == "" then
      clear()
      puk, chosen = "", ""
      sim.message:set("")
      sim.put_off:set(false)
    end
  end)

  --- The line under the prompt: how many tries are left.
  function sim.tries()
    local step = sim.step:get()
    local left = step == "puk" and mobile.state.tries_puk or step == "pin" and mobile.state.tries_pin or -1
    if left < 0 then return "" end
    return left == 1 and "1 try left" or (left .. " tries left")
  end

  function sim.title()
    return ({ pin = "Enter SIM PIN", puk = "Enter PUK", new = "Choose a new PIN", confirm = "Confirm the new PIN" })[sim.step:get()]
  end

  local function longest()
    return sim.step:get() == "puk" and M.PUK or M.MAX_PIN
  end
  local function shortest()
    return sim.step:get() == "puk" and M.PUK or M.MIN_PIN
  end

  --- Whether what is typed is long enough to send.
  function sim.ready()
    return sim.count:get() >= shortest() and not sim.busy:get()
  end

  function sim.digit(key)
    if not key:match("^%d$") or #draft >= longest() or sim.busy:get() then return false end
    draft = draft .. key
    sim.count:set(#draft)
    sim.message:set("")
    return true
  end

  function sim.back()
    draft = draft:sub(1, -2)
    sim.count:set(#draft)
  end

  --- Leaves the SIM locked for now; emergency calls still work.
  function sim.later() sim.put_off:set(true) end
  --- Brings the prompt back.
  function sim.again() sim.put_off:set(false) end

  local function send(method, arguments, wrong)
    local path = mobile.sim_path()
    if not path then sim.message:set("No SIM") clear() return false end
    sim.busy:set(true)
    return mobile.sim_call(path, method, arguments, function(ok)
      sim.busy:set(false)
      clear()
      if not ok then sim.message:set(wrong) end
    end)
  end

  --- Sends what is typed, or moves on a step of the PUK flow.
  function sim.submit()
    if not sim.ready() then return false end
    local step = sim.step:get()
    if step == "pin" then return send("SendPin", { draft }, "Wrong PIN") end
    if step == "puk" then
      puk = draft
      clear()
      sim.step:set("new")
      return true
    end
    if step == "new" then
      chosen = draft
      clear()
      sim.step:set("confirm")
      return true
    end
    if draft ~= chosen then
      clear()
      chosen = ""
      sim.step:set("new")
      sim.message:set("The PINs did not match")
      return false
    end
    local code, pin = puk, chosen
    puk, chosen = "", ""
    sim.step:set("puk")
    return send("SendPuk", { code, pin }, "Wrong PUK")
  end

  return sim
end

return M
