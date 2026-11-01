-- Snippets: named text, kept in $XDG_CONFIG_HOME/eva/snippets.json as
-- `{ name, text, trigger }`, a file a person can edit. `{date}`, `{time}`,
-- `{datetime}`, `{uuid}` and `{clipboard}` are filled in as a snippet is used, and
-- `{shell:a command}` with what the command prints.

local morf = require("morf")

local M = {}

M.revision = morf.signal("eva.snippets.revision", 0)

--- Where the file lives.
function M.path()
  local base = (morf.env and morf.env("XDG_CONFIG_HOME")) or (morf.fs.home() .. "/.config")
  return base .. "/eva/snippets.json"
end

local list

--- The snippets.
function M.all()
  if list then return list end
  list = {}
  local ok, text = pcall(morf.fs.read, M.path())
  local fine, data = pcall(morf.json.decode, ok and text or "")
  if fine and type(data) == "table" then
    for _, item in ipairs(data) do
      if type(item) == "table" and item.name and item.text then list[#list + 1] = item end
    end
  end
  return list
end

--- Reads the file again.
function M.reload()
  list = nil
  M.revision:set(M.revision:get() + 1)
end

local function save()
  morf.fs.write(M.path(), morf.json.encode(M.all()), { atomic = true, parents = true })
  M.revision:set(M.revision:get() + 1)
end

--- Adds a snippet, or replaces the one of that name.
function M.add(name, text, trigger)
  local all = M.all()
  for i, item in ipairs(all) do
    if item.name == name then table.remove(all, i) break end
  end
  all[#all + 1] = { name = name, text = text, trigger = trigger }
  save()
end

--- Removes the snippet `name`.
function M.remove(name)
  local all = M.all()
  for i, item in ipairs(all) do
    if item.name == name then table.remove(all, i) break end
  end
  save()
end

--- The snippet `word` triggers, or nil.
function M.triggered(word)
  for _, item in ipairs(M.all()) do
    if item.trigger and item.trigger == word then return item end
  end
end

--- The text a snippet typed before the cursor ends with: the snippet, or nil.
function M.ending(text)
  for _, item in ipairs(M.all()) do
    local trigger = item.trigger
    if trigger and trigger ~= "" and #text >= #trigger and text:sub(-#trigger) == trigger then
      local before = text:sub(-#trigger - 1, -#trigger - 1)
      if before == "" or before:match("[%s%p]") then return item end
    end
  end
end

--- `text` with its placeholders filled in. `clipboard` is what `{clipboard}` reads.
function M.fill(text, clipboard, now)
  now = now or morf.time.now()
  local values = {
    date = morf.time.format("%Y-%m-%d", now), time = morf.time.format("%H:%M", now),
    datetime = morf.time.format("%Y-%m-%d %H:%M", now), uuid = morf.encoding.uuid(), clipboard = clipboard or "",
  }
  return (text:gsub("{(%a+)}", function(name) return values[name] end))
end

--- `text` filled in, handed to `done`, every `{shell:...}` run first.
function M.expand(text, clipboard, done)
  local command = text:match("{shell:([^}]*)}")
  if not command then done(M.fill(text, clipboard)) return end
  morf.process.run({ "sh", "-c", command }, { timeout_ms = 5000 }, function(result)
    local output = tostring(result and result.stdout or ""):gsub("%s+$", "")
    local replaced = text:gsub("{shell:[^}]*}", function() return output end, 1)
    M.expand(replaced, clipboard, done)
  end)
end

return M
