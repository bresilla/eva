-- A line of text, a medical card and a way to call for help, all as the person
-- set them. Only the listed numbers can be dialled, through `dialer()`:
-- `lib.services.emergency_call`, with `present()` and `dial(number)`.
-- EVA_FAKE_DIAL=1 stands in under a dry run.
local morf = require("morf")
local M = {}

local CARD = {
  { key = "name", label = "Name" }, { key = "blood", label = "Blood type" },
  { key = "allergies", label = "Allergies" }, { key = "medication", label = "Medication" },
  { key = "contact", label = "Emergency contact" },
}

local function stand_in()
  return { present = function() return true end,
    dial = function(number) morf.log("info", "eva: emergency call " .. number .. " (stand-in)") return true end }
end

--- The dialler, or nil where no call can be made.
function M.dialer()
  if morf.env("EVA_FAKE_DIAL") == "1" and morf.env("EVA_DRY_RUN") == "1" then return stand_in() end
  local ok, calls = pcall(require, "lib.services.emergency_call")
  if ok and type(calls) == "table" and type(calls.present) == "function" and calls.present() then return calls end
  return nil
end

function M.new(prefs)
  local chosen = prefs.emergency or {}
  local self = {}
  local dialer = M.dialer()
  local numbers = {}
  for _, number in ipairs(chosen.numbers or {}) do
    if tostring(number):match("^%d%d%d?%d?$") then numbers[#numbers + 1] = tostring(number) end
  end

  --- The line under the date, or "".
  function self.text() return chosen.text or "" end

  --- The card's filled rows: `{ label, value }`.
  function self.card()
    local rows = {}
    for _, field in ipairs(CARD) do
      local value = chosen[field.key]
      if type(value) == "string" and value ~= "" then rows[#rows + 1] = { label = field.label, value = value } end
    end
    return rows
  end

  --- The numbers offered, none where no call can be made.
  function self.numbers() return dialer and numbers or {} end

  --- Whether there is anything to open.
  function self.available() return #self.card() > 0 or #self.numbers() > 0 end

  --- Calls `number` if it is one of the listed ones. True, or false and why.
  function self.dial(number)
    if not dialer then return false, "No way to call from here" end
    for _, allowed in ipairs(numbers) do
      if allowed == number then
        local ok, result, why = pcall(dialer.dial, number)
        if ok and result then return true end
        return false, why or "The call did not start"
      end
    end
    return false, "Not an emergency number"
  end
  return self
end

return M
