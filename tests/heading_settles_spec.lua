-- A Tsugumori title decodes once and lands on its word: the month's over the
-- dashboard's calendar was seen scrambled in a shot, so its whole read is
-- filmed here, and the ways a read can be cut short.
local test = morf.test
local SOURCE = [[
  require("init")
  morf.ipc.month = function() return require("lib.util.unicase").upper(morf.time.format("%B %Y")) end
]]
local function load()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, source = SOURCE, env = { EVA_STYLE = "tsugumori",
    EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule",
    HOME = morf.env("XDG_CACHE_HOME"), EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/heading.json" } })
  test.settle(800)
end
local TITLE = "calendar-title-text"
local function title() return test.get(TITLE).text end

test.it("the month's title scrambles while it reads in, and lands within a second and a half", function()
  load()
  local word = test.ipc("month")
  test.ipc("dashboard", "open")
  local frames, landed = {}, nil
  for step = 1, 60 do
    test.advance(50)
    local text = title()
    frames[#frames + 1] = text
    if text == word and not landed then landed = step * 50 end
  end
  local scrambled = 0
  for _, text in ipairs(frames) do if text ~= word then scrambled = scrambled + 1 end end
  test.truthy(scrambled > 0, "it never read in: this film shows nothing")
  test.truthy(landed and landed <= 1500, "it landed late: " .. tostring(landed))
  for i = landed // 50, #frames do test.eq(frames[i], word, "it scrambled again after landing") end
end)

test.it("a read cut short by closing leaves the word, not the scramble", function()
  load()
  local word = test.ipc("month")
  test.ipc("dashboard", "open") test.advance(450)
  test.ipc("close") test.advance(1500)
  test.eq(title(), word)
  test.ipc("dashboard", "open") test.advance(250)
  test.ipc("close") test.advance(60)
  test.ipc("dashboard", "open") test.advance(2200)
  test.eq(title(), word)
end)

test.it("a read cut short by another tab leaves the word too", function()
  load()
  local word = test.ipc("month")
  test.ipc("dashboard", "open") test.advance(450)
  test.click("dashboard-tab-media") test.advance(1500)
  test.click("dashboard-tab-dashboard") test.advance(2200)
  test.eq(title(), word)
end)
