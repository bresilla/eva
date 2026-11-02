-- A choice on a Settings page shows its whole label: a label wider than its
-- button is one cut off.
--
--     morf test tests/choice_labels_spec.lua

local test = morf.test

local function load(style)
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, env = { EVA_STYLE = style, EVA_DRY_RUN = "1",
    EVA_FAKE_SYSTEM = "1", EVA_FONT_FILE = "", LULE_A = "/nonexistent/lule", HYPRLAND_INSTANCE_SIGNATURE = false },
    source = [[
      require("services").here = function() return true end
      require("init")
    ]] })
  test.advance(1800)
end

-- What each label measures in full, from the unseen copy each button keeps.
local function naturals()
  local nodes, by_handle, widths = test.nodes(), {}, {}
  for _, node in ipairs(nodes) do by_handle[node.handle] = node end
  for _, node in ipairs(nodes) do
    local box = by_handle[node.parent]
    if node.element == "Text" and node.opacity == 0 and box and box.width == 1 and box.height == 1 then
      widths[node.text] = math.max(widths[node.text] or 0, node.width)
    end
  end
  return widths
end

local function cut()
  local widths, out = naturals(), {}
  for _, node in ipairs(test.nodes()) do
    local full = node.element == "Text" and node.visible and widths[node.text]
    if full and node.width < full - 1 then out[#out + 1] = node.text end
  end
  return out
end

local PAGES = { "backups/more", "focus", "focus/mode", "network/proxy", "notifications", "input", "input/remap",
  "theme/look", "windows/rule", "assistant", "lock" }

local DATES = { None = true, NONE = true, Day = true, DAY = true, Short = true, SHORT = true, Long = true, LONG = true,
  ISO = true }

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the bar's date choices are not cut off", function()
    load(style)
    test.ipc("settings", "bar")
    test.settle(1200)
    local dates = {}
    for _, label in ipairs(cut()) do
      if DATES[label] then dates[#dates + 1] = label end
    end
    test.eq(dates, {})
  end)
  test.it(style .. ": no label of a choice is cut off", function()
    load(style)
    for _, page in ipairs(PAGES) do
      test.ipc("settings", page)
      test.settle(1200)
      test.eq(cut(), {}, page)
    end
  end)
end
