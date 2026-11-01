-- Every `hl.dsp` name the shell writes is one Hyprland has: the fixture comes
-- from the stubs Hyprland 0.55.4 ships (share/hypr/stubs/hl.meta.lua).
local test = morf.test

local FILES = { "shell/windows_model.lua", "shell/window_menu.lua", "shell/window_modes.lua", "shell/workspaces_model.lua",
  "shell/windows_ipc.lua", "shell/keybinds.lua" }

test.it("the dispatchers the shell sends exist", function()
  local known = {}
  for line in morf.fs.read("tests/fixtures/hl-dsp-names.txt"):gmatch("[^\n]+") do known[line] = true end
  test.truthy(known["window.move"] and known.focus, "the fixture is empty")
  local seen, unknown = 0, {}
  local function name(found, path)
    seen = seen + 1
    if not known[found] then unknown[#unknown + 1] = path .. ": " .. found end
  end
  for _, path in ipairs(FILES) do
    local text = morf.fs.read(path)
    for found in text:gmatch("hl%.dsp%.([%w_%.]+)%(") do name(found, path) end
    for found in text:gmatch('{ "(%l+%.[%w_]+)", ') do
      if found:match("^window%.") or found:match("^group%.") or found:match("^workspace%.") then name(found, path) end
    end
  end
  test.truthy(seen > 15, "the scan found too little: " .. seen)
  test.eq(unknown, {})
end)
