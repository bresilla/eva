-- The pages that are nothing but settings: each a list of sections of fields,
-- each field naming its key in shell/config.lua. Plain data, no nodes.
-- themes/layouts/views/settings_form.lua draws them.
--
-- A field: `key`, `title`, `icon`, `note`, and `kind`:
--   bool                 a switch
--   choice               `items` ({ value, icon, name })
--   number               `from`, `to`, `step`, `unit`
--   text                 one line
--   words                a command: a list of words, edited as one line
--   list                 a list of names, edited as one line
local M = {}

local function commands(prefix, rows)
  local out = {}
  for index, row in ipairs(rows) do
    out[index] = { key = prefix .. row[1], kind = "words", title = row[2], icon = row[3] }
  end
  return out
end

M.PAGES = {
  launcher = { sections = {
    { title = "Results", fields = {
      { key = "launcher.max_shown", kind = "number", title = "Results shown", icon = "format_list_numbered",
        from = 3, to = 15, step = 1 },
    } },
    { title = "Actions", fields = {
      { key = "launcher.action_prefix", kind = "text", title = "Action prefix", icon = "keyboard_command_key",
        note = "Typed first, it turns the launcher to actions" },
    } },
  } },
  rail = { sections = {
    { title = "Workspace rail", fields = {
      { key = "rail.enabled", kind = "bool", title = "Show the rail", icon = "view_week",
        note = "The workspaces down the left edge" },
      { key = "rail.hold", kind = "number", title = "Number stays for", icon = "timer", from = 200, to = 3000, step = 100, unit = " ms" },
    } },
  } },
  capture = { sections = {
    { title = "Where", fields = {
      { key = "capture.folder", kind = "text", title = "Folder", icon = "folder", note = "Screenshots and recordings go here" },
      { key = "capture.keybind_file", kind = "text", title = "Keybind file", icon = "description",
        note = "Where the hotkey is written, empty for none" },
      { key = "capture.hotkey", kind = "text", title = "Hotkey", icon = "keyboard" },
    } },
    { title = "After a capture", fields = {
      { key = "capture.editor", kind = "bool", title = "Open the editor", icon = "edit" },
      { key = "capture.cursor", kind = "bool", title = "Show the cursor", icon = "arrow_selector_tool" },
      { key = "capture.save_dialog", kind = "bool", title = "Ask where to save", icon = "save_as" },
      { key = "capture.copy_on_save", kind = "bool", title = "Copy when saved", icon = "content_copy" },
      { key = "capture.copy_to_disk", kind = "bool", title = "Also save when copied", icon = "save" },
    } },
    { title = "Editor", fields = {
      { key = "capture.blur", kind = "number", title = "Blur strength", icon = "blur_on", from = 2, to = 100, step = 2 },
      { key = "capture.pixelate", kind = "number", title = "Pixel size", icon = "grid_on", from = 2, to = 64, step = 2 },
      { key = "capture.zoom", kind = "number", title = "Zoom factor", icon = "zoom_in", from = 1, to = 10, step = 0.5 },
    } },
    { title = "Sharing", fields = {
      { key = "capture.upload_endpoint", kind = "text", title = "Upload address", icon = "cloud_upload",
        note = "Where More, Upload sends a capture" },
    } },
    { title = "Capture commands", note = "$FILE is the file to write", fields = commands("capture.commands.", {
      { "screenshot_region", "Screenshot a region", "screenshot_region" },
      { "screenshot_window", "Screenshot a window", "select_window" },
      { "screenshot_screen", "Screenshot the screen", "monitor" },
      { "record_region", "Record a region", "screen_record" },
      { "record_window", "Record a window", "select_window" },
      { "record_screen", "Record the screen", "monitor" },
      { "open", "Open a capture", "open_in_new" },
    }) },
  } },
  osk = { sections = {
    { title = "On-screen keyboard", fields = {
      { key = "keyboard.auto", kind = "bool", title = "Up by itself", icon = "keyboard_alt",
        note = "When a program asks for text and no real keyboard is attached" },
    } },
  } },
  weather = { sections = {
    { title = "Weather", fields = {
      { key = "services.weather_location", kind = "text", title = "Location", icon = "location_on",
        note = "A city, or empty to go by this connection's address" },
      { key = "services.imperial", kind = "bool", title = "Imperial units", icon = "straighten" },
    } },
  } },
  commands = { sections = {
    { title = "Session", note = "$USER is your name", fields = commands("session.commands.", {
      { "lock", "Lock", "lock" }, { "logout", "Log out", "logout" }, { "suspend", "Suspend", "bedtime" },
      { "hibernate", "Hibernate", "downloading" }, { "reboot", "Restart", "restart_alt" },
      { "shutdown", "Power off", "power_settings_new" },
    }) },
    { title = "Utilities", note = "~/ and $HOME are your home folder", fields = commands("utilities.commands.", {
      { "mic_on", "Microphone on", "mic" }, { "mic_off", "Microphone off", "mic_off" },
      { "settings", "Settings program", "settings" }, { "gamemode_on", "Game mode on", "sports_esports" },
      { "gamemode_off", "Game mode off", "sports_esports" },
    }) },
  } },
  panels = { sections = {
    { title = "Desk", note = "A page moves by moving its name: settings, notifications, tasks, calendar, assistant, drop", fields = {
      { key = "panels.right", kind = "list", title = "Right panel", icon = "dock_to_left" },
      { key = "panels.left", kind = "list", title = "Left panel", icon = "dock_to_right" },
    } },
    { title = "Phone and tablet", fields = {
      { key = "panels.top", kind = "list", title = "Sheet from the top", icon = "vertical_align_top" },
    } },
  } },
  wallpaper = { sections = {
    { title = "Picture", fields = {
      { key = "wallpaper.path", kind = "text", title = "Picture", icon = "image", note = "Empty follows the eva tools' current one" },
      { key = "wallpaper.draw", kind = "bool", title = "Painted by the shell", icon = "wallpaper",
        note = "Off, the compositor's wallpaper tool shows through" },
    } },
    { title = "Colours", fields = {
      { key = "theme.source", kind = "text", title = "Colours from", icon = "palette",
        note = "auto, lule, wallpaper, or a colour such as #45aa86" },
      { key = "theme.variant", kind = "choice", title = "Scheme", icon = "style", items = {
        { "tonal_spot", "palette", "Tonal" }, { "vibrant", "colorize", "Vibrant" },
        { "expressive", "brush", "Expressive" }, { "neutral", "contrast", "Neutral" } } },
      { key = "appearance.font_file", kind = "text", title = "Font file", icon = "font_download",
        note = "Every label set in this file, empty for the installed faces" },
    } },
  } },
  -- The rest of Bar's and Eva's keys, on the pages that hold the others.
  ["bar/more"] = { sections = {
    { title = "Clock", fields = {
      { key = "bar.clock.twelve_hour", kind = "bool", title = "12-hour clock", icon = "schedule" },
      { key = "bar.bluetooth_settings", kind = "words", title = "Bluetooth program", icon = "bluetooth" },
    } },
    { title = "Screen shape", note = "For a screen with rounded corners or a cutout", fields = {
      { key = "edgebar.corner", kind = "number", title = "Corner reach", icon = "rounded_corner", from = 0, to = 120, step = 4, unit = " px" },
      { key = "edgebar.cutout.x", kind = "number", title = "Cutout left edge", icon = "border_left", from = 0, to = 2000, step = 4, unit = " px" },
      { key = "edgebar.cutout.width", kind = "number", title = "Cutout width", icon = "width", from = 0, to = 600, step = 4, unit = " px" },
      { key = "edgebar.cutout.height", kind = "number", title = "Cutout height", icon = "height", from = 0, to = 200, step = 4, unit = " px" },
    } },
  } },
}

--- Every key a form reaches, as a set.
function M.keys()
  local out = {}
  for _, page in pairs(M.PAGES) do
    for _, section in ipairs(page.sections) do
      for _, field in ipairs(section.fields) do out[field.key] = true end
    end
  end
  return out
end

--- A list of words as the line it is edited in.
function M.join(words)
  local out = {}
  for index, word in ipairs(words or {}) do
    word = tostring(word)
    if word == "" or word:find("[%s\"]") then word = '"' .. word:gsub('"', '\\"') .. '"' end
    out[index] = word
  end
  return table.concat(out, " ")
end

--- A line back into its words: runs of blanks part them, "double quotes" hold
--- them together, \" is a quote inside.
function M.split(line)
  local out, word, quoted, escaped, had = {}, {}, false, false, false
  for index = 1, #line do
    local c = line:sub(index, index)
    if escaped then word[#word + 1] = c escaped = false
    elseif quoted and c == "\\" then escaped = true
    elseif c == '"' then quoted = not quoted had = true
    elseif not quoted and c:find("%s") then
      if #word > 0 or had then out[#out + 1] = table.concat(word) end
      word, had = {}, false
    else word[#word + 1] = c end
  end
  if #word > 0 or had then out[#out + 1] = table.concat(word) end
  return out
end

return M
