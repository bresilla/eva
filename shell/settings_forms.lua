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
--   records              a list of tables of `fields`, edited as one line of words
-- `clean` (words, list) turns the words typed into what is kept; the field then
-- shows what was.
local M = {}

local function commands(prefix, rows)
  local out = {}
  for index, row in ipairs(rows) do
    out[index] = { key = prefix .. row[1], kind = "words", title = row[2], icon = row[3] }
  end
  return out
end

-- The session's actions by id, named and drawn as the menu has them.
local function session_commands(ids)
  local rows = {}
  for index, id in ipairs(ids) do
    local action = require("models.session_actions").BY_ID[id]
    rows[index] = { id, action.name, action.icon }
  end
  return commands("session.commands.", rows)
end

M.PAGES = {
  ["backups/more"] = { sections = {
    { title = "Which tool", fields = {
      { key = "backups.tool", kind = "choice", title = "Use", items = {
        { "", "auto_mode", "First found" }, { "snapper", "backup", "Snapper" }, { "btrbk", "backup", "btrbk" }, { "restic", "backup", "restic" } } },
      { key = "backups.snapper_config", kind = "text", title = "Snapper config", icon = "settings",
        note = "The config to show: root, home, or one of your own" },
    } },
    { title = "restic", note = "The password stays in its file, and only the file's path reaches restic.", fields = {
      { key = "backups.restic_repository", kind = "text", title = "Repository", icon = "storage",
        note = "A folder, or sftp:, s3:, rest: and the like" },
      { key = "backups.restic_password_file", kind = "text", title = "Password file", icon = "key" },
      { key = "backups.restic_paths", kind = "list", title = "What to back up", icon = "folder" },
    } },
  } },
  launcher = { sections = {
    { title = "Results", fields = {
      { key = "launcher.max_shown", kind = "number", title = "Results shown", icon = "format_list_numbered",
        from = 3, to = 15, step = 1 },
      { key = "launcher.max_results", kind = "number", title = "Results listed", icon = "format_list_numbered",
        from = 10, to = 100, step = 5 },
      { key = "launcher.layout", kind = "choice", title = "Layout", items = {
        { "auto", "devices", "Auto" }, { "grid", "apps", "Grid" }, { "list", "view_list", "List" } } },
      { key = "launcher.preview_pane", kind = "bool", title = "Preview beside the results", icon = "preview",
        note = "Files and pictures, where there is room" },
      { key = "launcher.keep_query", kind = "bool", title = "Keep the last search", icon = "history" },
      { key = "launcher.remember", kind = "bool", title = "Remember what is picked", icon = "star",
        note = "For ranking and history" },
    } },
    { title = "What a search reaches", fields = {
      { key = "launcher.sources", kind = "list", title = "Sources", icon = "manage_search",
        note = "apps settings windows system actions app_actions places modes snippets recent bookmarks files" },
      { key = "launcher.search_files", kind = "bool", title = "Search files", icon = "folder_open" },
      { key = "launcher.exclude", kind = "list", title = "Folders left out", icon = "folder_off" },
      { key = "launcher.projects", kind = "list", title = "Project folders", icon = "folder_code" },
    } },
    { title = "Actions", fields = {
      { key = "launcher.action_prefix", kind = "text", title = "Action prefix", icon = "keyboard_command_key",
        note = "Typed first, it turns the launcher to actions" },
      { key = "launcher.terminal", kind = "words", title = "Terminal", icon = "terminal", note = "Empty uses $TERMINAL" },
      { key = "launcher.expansion", kind = "bool", title = "Expand snippets anywhere", icon = "short_text" },
      { key = "launcher.plugins", kind = "bool", title = "Load plugins", icon = "extension",
        note = "From ~/.config/eva/plugin" },
    } },
    { title = "Web", fields = {
      { key = "launcher.engines", kind = "records", title = "Search engines", icon = "travel_explore",
        fields = { "bang", "name", "url" }, note = "bang, name, address with %s, one after another" },
      { key = "launcher.quicklinks", kind = "records", title = "Quick links", icon = "link",
        fields = { "name", "url" }, note = "name, address with {query}, one after another" },
      { key = "launcher.translate_to", kind = "text", title = "Translate to", icon = "translate" },
      { key = "launcher.wiki_language", kind = "text", title = "Wikipedia language", icon = "language" },
    } },
    { title = "Files", fields = {
      { key = "launcher.menus.appimages", kind = "list", title = "AppImage folders", icon = "deployed_code" },
      { key = "launcher.menus.bookmarks", kind = "text", title = "Bookmark folder", icon = "bookmark" },
      { key = "launcher.menus.player", kind = "words", title = "Player", icon = "play_circle" },
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
      { key = "capture.thumbnail", kind = "bool", title = "Show a thumbnail", icon = "picture_in_picture",
        note = "A small picture after a shot: press it to edit, or leave it to fade" },
      { key = "capture.thumbnail_seconds", kind = "number", title = "Thumbnail stays for", icon = "timer",
        from = 2, to = 30, step = 1, unit = " s" },
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
    { title = "Recordings", fields = {
      { key = "capture.replay_seconds", kind = "number", title = "Replay keeps", icon = "replay", from = 5, to = 600, step = 5, unit = " s",
        note = "The seconds the replay buffer holds" },
      { key = "capture.gif_fps", kind = "number", title = "GIF frame rate", icon = "gif_box", from = 2, to = 30, step = 1, unit = " fps" },
      { key = "capture.gif_width", kind = "number", title = "GIF width", icon = "width", from = 240, to = 1920, step = 40, unit = " px" },
    } },
    { title = "Capture commands", note = "$FILE is the file to write", fields = commands("capture.commands.", {
      { "record_region", "Record a region", "screen_record" },
      { "record_window", "Record a window", "select_window" },
      { "record_screen", "Record the screen", "monitor" },
      { "record_portal", "Record through the portal", "cast" },
      { "record_replay", "Replay buffer", "replay" },
      { "trim", "Trim a recording", "content_cut" },
      { "gif", "Make a GIF", "gif_box" },
      { "open", "Open a capture", "open_in_new" },
    }) },
  } },
  ["input/remap"] = { status = "remap_model", sections = {
    { title = "Caps Lock", fields = {
      { key = "remap.caps", kind = "choice", title = "It acts as", per_row = 2, items = {
        { "", "keyboard_capslock", "Caps Lock" }, { "escape", "keyboard", "Escape" },
        { "control", "keyboard_control_key", "Control" }, { "hyper", "star", "Hyper" },
        { "tap_escape_hold_control", "touch_app", "Tap Esc, hold Ctrl" },
        { "tap_escape_hold_hyper", "touch_app", "Tap Esc, hold Hyper" } } },
    } },
    { title = "Hyper", note = "A key that holds Ctrl, Alt, Shift and Super at once", fields = {
      { key = "remap.hyper", kind = "choice", title = "Hyper key", per_row = 2, items = {
        { "", "block", "None" }, { "right_alt", "keyboard_option_key", "Right Alt" },
        { "right_control", "keyboard_control_key", "Right Ctrl" }, { "menu", "menu", "Menu" } } },
    } },
    { title = "More", fields = {
      { key = "remap.swap_alt_super", kind = "bool", title = "Swap Alt and Super", icon = "swap_horiz" },
      { key = "remap.home_row", kind = "bool", title = "Modifiers on the home row", icon = "keyboard",
        note = "A S D F and J K L ; type when tapped, and are Super, Alt, Shift, Ctrl when held" },
    } },
    { title = "Tap or hold", fields = {
      { key = "remap.tap", kind = "number", title = "A tap lasts up to", icon = "touch_app", from = 100, to = 500, step = 10, unit = " ms" },
      { key = "remap.hold", kind = "number", title = "A hold starts after", icon = "timer", from = 100, to = 500, step = 10, unit = " ms" },
    } },
  } },
  ["windows/more"] = { sections = {
    { title = "Scratchpads", fields = {
      { key = "windows.scratchpads", kind = "records", fields = { "name", "command", "icon" }, title = "Scratchpads",
        icon = "stacks", note = "name, the command in quotes and an icon, one after another" },
    } },
  } },
  ["lock/more"] = { sections = {
    { title = "Readers", fields = {
      { key = "lock.reader_tries", kind = "number", title = "Tries on a reader", icon = "fingerprint", from = 0, to = 10, step = 1,
        note = "Then the password" },
    } },
  } },
  keyboard = { sections = {
    { title = "Keyboard", fields = {
      { key = "keyboard.auto", kind = "bool", title = "Up by itself", icon = "keyboard_alt",
        note = "When a program asks for text and no real keyboard is attached" },
    } },
  } },
  phone = { sections = {
    { title = "Calls and texts", fields = {
      { key = "phone.contacts", kind = "text", title = "Contacts folder", icon = "contacts", note = "A folder of vCards" },
      { key = "phone.country", kind = "text", title = "Country code", icon = "flag", note = "What a bare number gets: +31" },
      { key = "phone.silence_unknown", kind = "bool", title = "Silence unknown callers", icon = "phone_disabled",
        note = "Numbers not in your contacts do not ring" },
      { key = "phone.delivery_reports", kind = "bool", title = "Delivery reports", icon = "mark_chat_read",
        note = "A text asks the network to say when it lands" },
    } },
    { title = "Power key", fields = {
      { key = "phone.power_ends_call", kind = "bool", title = "Ends a call", icon = "call_end" },
      { key = "phone.double_power", kind = "words", title = "Pressed twice", icon = "double_arrow",
        note = "The command it runs: the camera, say" },
      { key = "phone.sos", kind = "bool", title = "Five presses for an emergency call", icon = "emergency",
        note = "A countdown, then the call" },
    } },
    { title = "Emergency", fields = {
      { key = "phone.medical", kind = "text", title = "Medical information", icon = "medical_information",
        note = "Blood type, allergies, medication: on the lock's emergency pad, for a stranger to read" },
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
    { title = "Updates", fields = {
      { key = "update.flake", kind = "text", title = "Flake", icon = "account_tree",
        note = "What eva-update reads, or its folder; empty finds /etc/nixos's" },
    } },
    { title = "Session", note = "$USER is your name", fields = session_commands {
      "lock", "logout", "suspend", "hibernate", "suspend_hibernate", "reboot", "shutdown" } },
    { title = "Session menu", fields = {
      { key = "session.countdown", kind = "number", title = "Count down", icon = "timer", from = 0, to = 30, step = 1,
        unit = " s" },
      { key = "session.hide", kind = "list", title = "Left out", icon = "visibility_off", note = "Actions by id" },
      { key = "session.custom", kind = "records", fields = { "id", "name", "icon", "command" }, title = "Your own",
        icon = "terminal", note = "id, name, icon and the command in quotes, one after another" },
    } },
    { title = "Utilities", note = "~/ and $HOME are your home folder", fields = commands("utilities.commands.", {
      { "mic_on", "Microphone on", "mic" }, { "mic_off", "Microphone off", "mic_off" },
      { "settings", "Settings program", "settings" }, { "gamemode_on", "Game mode on", "sports_esports" },
      { "gamemode_off", "Game mode off", "sports_esports" },
    }) },
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

--- The records in `list` as one line, each one's `fields` as words.
function M.join_records(list, fields)
  local flat = {}
  for _, record in ipairs(list or {}) do
    for _, name in ipairs(fields) do
      local value = record[name] or ""
      flat[#flat + 1] = type(value) == "table" and M.join(value) or value
    end
  end
  return M.join(flat)
end

--- The times of day in `words`, each `HH:MM`, in order and once each. What is no
--- time is dropped.
function M.times(words)
  local seen, out = {}, {}
  for _, word in ipairs(words) do
    for hour, minute in word:gmatch("%f[%d](%d%d?):(%d%d)%f[%D]") do
      hour, minute = tonumber(hour), tonumber(minute)
      if hour < 24 and minute < 60 then seen[("%02d:%02d"):format(hour, minute)] = true end
    end
  end
  for time in pairs(seen) do out[#out + 1] = time end
  table.sort(out)
  return out
end

--- The records on `line`, each `#fields` words. A record left short is dropped.
function M.split_records(line, fields)
  local flat, out = M.split(line), {}
  for first = 1, #flat - #fields + 1, #fields do
    local record = {}
    for offset, name in ipairs(fields) do record[name] = flat[first + offset - 1] end
    out[#out + 1] = record
  end
  return out
end

return M
