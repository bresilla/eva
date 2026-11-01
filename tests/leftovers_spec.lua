-- No page speaks of what the shell no longer has.
--
--     morf test tests/leftovers_spec.lua

local test = morf.test

local FOLDERS = { "themes/layouts/views", "shell" }
local KEPT = { ["themes/layouts/views/keyboard.lua"] = true, ["shell/keyboard.lua"] = true }
local GONE = { "prediction", "taskbar", "home screen", "desktop widget", "keyboard language" }

test.it("a string on a page names nothing removed", function()
  local strays = {}
  for _, folder in ipairs(FOLDERS) do
    for _, entry in ipairs(morf.fs.list(folder)) do
      local name = tostring(type(entry) == "table" and entry.name or entry)
      local path = folder .. "/" .. name
      if name:match("%.lua$") and not KEPT[path] then
        for quoted in (morf.fs.read(path) or ""):gmatch('"([^"\n]+)"') do
          local lowered = quoted:lower()
          for _, word in ipairs(GONE) do
            if lowered:find(word, 1, true) then strays[#strays + 1] = path .. ": " .. quoted end
          end
        end
      end
    end
  end
  test.eq(strays, {})
end)
