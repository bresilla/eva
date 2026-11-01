-- The scrambled number pad on the lock: the digits change places, a finger's press
-- types the digit it lands on, and what is typed goes the way a password goes. The
-- lock runs in preview, which never asks PAM.
--
--     morf test --no-dbus tests/lock_scramble_spec.lua
local test = morf.test

local PHONE = { 620, 1380 }
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"
local dir = morf.env("XDG_CACHE_HOME") .. "/lock-scramble-spec"
morf.fs.mkdir(dir, { parents = true })

local SOURCE = [==[
  local password = require("models.password")
  local given, taken = "", {}
  local new = password.new
  password.new = function(...)
    local self = new(...)
    local add, take = self.add, self.take
    self.add = function(text)
      given = given .. tostring(text)
      return add(text)
    end
    self.take = function(...)
      taken[#taken + 1] = #given
      return take(...)
    end
    return self
  end
  require("init")
  morf.ipc.given = function() return given end
  morf.ipc.taken = function() return taken end
]==]

local serial = 0
local function load(lock, style)
  serial = serial + 1
  local settings = dir .. "/eva-" .. serial .. ".json"
  morf.fs.write(settings, morf.json.encode { lock = lock })
  test.load("../lock/init.lua", { source = SOURCE, size = PHONE, args = { "window", "preview" },
    env = { EVA_SETTINGS = settings, EVA_DRY_RUN = "1", EVA_INPUT_DEVICES = TOUCH, EVA_STYLE = style or "material",
      EVA_APPEARANCE = dir .. "/none.json", XDG_RUNTIME_DIR = dir } })
  test.settle(1200)
end

local function open_sheet()
  test.swipe({ PHONE[1] / 2, PHONE[2] - 30 }, { PHONE[1] / 2, PHONE[2] - 700 }, { duration = 240 })
  test.settle(700)
end

-- The keys as a screen reader is told them, place by place.
local function order()
  local out = {}
  for _, row in ipairs(test.accessible()) do
    local place = tostring(row.id or ""):match("^lock%-pin%-(%d+)$")
    if place then out[tonumber(place)] = row.name end
  end
  return out
end

local function tap(place)
  local key = test.get("lock-pin-" .. place)
  local x, y = key.x + key.width / 2, key.y + key.height / 2
  test.touch("down", 0, x, y) test.advance(40)
  test.touch("up", 0, x, y) test.advance(80)
end

local function place_of(wanted)
  for place, key in ipairs(order()) do if key == wanted then return place end end
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " the scrambled pad", function()
    test.it("stands in the keyboard's place, with every digit once and delete and enter", function()
      load({ keypad = "digits", scramble = true }, style)
      open_sheet()
      test.eq(test.ipc("stage"), "sheet")
      test.truthy(test.find { id = "lock-pin", visible = true }, "no pad")
      local seen = {}
      for _, key in ipairs(order()) do
        test.falsy(seen[key], "twice: " .. key)
        seen[key] = true
      end
      for digit = 0, 9 do test.truthy(seen[tostring(digit)], "no " .. digit .. " in " .. table.concat(order(), " ")) end
      test.truthy(seen.Delete, "no delete")
      test.truthy(seen.Unlock, "no enter")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("types the digit a finger lands on, wherever it stands, and takes it back", function()
      load({ keypad = "digits", scramble = true }, style)
      open_sheet()
      for _, digit in ipairs { "4", "7", "1" } do tap(place_of(digit)) end
      test.eq(test.ipc("given"), "471", "a press typed something else")
      tap(place_of("Delete"))
      test.eq(#test.ipc("taken"), 0, "delete submitted it")
    end)

    test.it("submits the way a password goes", function()
      load({ keypad = "digits", scramble = true }, style)
      open_sheet()
      tap(place_of("2")) tap(place_of("8"))
      tap(place_of("Unlock"))
      test.settle(600)
      test.eq(test.ipc("taken"), { 2 }, "the lock's own submit did not take it")
    end)

    test.it("stands in a new order each time it comes up", function()
      load({ keypad = "digits", scramble = true }, style)
      local orders, different = {}, false
      for round = 1, 4 do
        open_sheet()
        orders[round] = table.concat(order(), " ")
        if round > 1 and orders[round] ~= orders[1] then different = true end
        test.key("Escape") test.settle(600)
      end
      test.truthy(different, "the digits stayed where they were")
    end)
  end)

  test.it(style .. " stays away unless both settings ask", function()
    load({ keypad = "digits", scramble = false }, style)
    open_sheet()
    test.falsy(test.find { id = "lock-pin", visible = true }, "scrambled with the setting off")
    load({ keypad = "text", scramble = true }, style)
    open_sheet()
    test.falsy(test.find { id = "lock-pin", visible = true }, "a pad over the text keyboard")
    test.truthy(test.find { id = "lock-keyboard", visible = true }, "the keyboard is gone")
  end)
end

test.it("spreads the digits evenly across the places", function()
  test.load("../lock/init.lua", { size = { 40, 40 }, args = { "window", "preview" }, source = [==[
    morf.ipc.spread = function()
      local pad = require("themes.phone_pad")
      local pick = require("lib.shell.launcher.password").pick
      local first = {}
      for _ = 1, 100 do
        local key = pad.shuffled(pick)[1]
        first[key] = (first[key] or 0) + 1
      end
      return first
    end
  ]==], env = { EVA_DRY_RUN = "1", XDG_RUNTIME_DIR = dir } })
  local first = {}
  for _ = 1, 10 do
    for key, count in pairs(test.ipc("spread")) do first[key] = (first[key] or 0) + count end
  end
  for digit = 0, 9 do
    local count = first[tostring(digit)] or 0
    test.truthy(count > 50 and count < 160, ("%d came first %d times of 1000"):format(digit, count))
  end
end)

test.it("the setting is reachable, and shows beside the number pad", function()
  local settings = dir .. "/eva-page.json"
  morf.fs.write(settings, morf.json.encode { lock = { keypad = "digits" } })
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 412, 915 }, env = { EVA_SETTINGS = settings, EVA_DRY_RUN = "1", EVA_WALLPAPER = "",
    EVA_INPUT_DEVICES = TOUCH, HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(900)
  test.ipc("settings", "lock") test.settle(900)
  test.truthy(test.find { id = "lock-set-scramble", visible = true }, "not beside the number pad")
  local keys = {}
  for _, hit in ipairs(test.ipc("settings-search", "scramble")) do keys[#keys + 1] = hit.key end
  test.truthy(table.concat(keys, " "):find("lock", 1, true), "search does not find it")
end)
