-- Bookmarks wherever a browser or a tool keeps them: Firefox's places.sqlite (read
-- from a copy, as the browser holds it open), Chromium's Bookmarks JSON, the
-- `bookmark` tool's JSON files, and the setting `launcher.bookmarks`.
--
-- A bookmark is `{ name, url, folder }`. Reading goes off the loop: `read(done)`.

local morf = require("morf")

local M = {}

--- The bookmarks in a Chromium `Bookmarks` file.
function M.chromium(text)
  local ok, data = pcall(morf.json.decode, text)
  local out = {}
  if not ok or type(data) ~= "table" or type(data.roots) ~= "table" then return out end
  local function walk(node, folder)
    if type(node) ~= "table" then return end
    if node.type == "url" and node.url then
      out[#out + 1] = { name = tostring(node.name or node.url), url = node.url, folder = folder }
    end
    for _, child in ipairs(type(node.children) == "table" and node.children or {}) do
      walk(child, node.name or folder)
    end
  end
  for _, root in pairs(data.roots) do walk(root, "") end
  return out
end

--- The links in one of the `bookmark` tool's files, of `group` if named:
--- `{ urls = { items = { { id, name, url, group } } } }`.
function M.tool_file(path, group)
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" then return {} end
  local fine, data = pcall(morf.json.decode, text)
  local items = fine and type(data) == "table" and type(data.urls) == "table" and data.urls.items or {}
  local out = {}
  for _, item in ipairs(type(items) == "table" and items or {}) do
    if not group or item.group == group then
      out[#out + 1] = { id = item.id, name = tostring(item.name or item.url), url = tostring(item.url), folder = item.group }
    end
  end
  return out
end

local FIREFOX = [[
db=$(ls -t "$HOME"/.var/app/app.zen_browser.zen/.zen/*/places.sqlite "$HOME"/.zen/*/places.sqlite \
  "$HOME"/.mozilla/firefox/*/places.sqlite \
  "$HOME"/.var/app/org.mozilla.firefox/.mozilla/firefox/*/places.sqlite 2>/dev/null | head -1)
[ -n "$db" ] || exit 0
copy=$(mktemp) && cp -f "$db" "$copy" && sqlite3 -separator "$(printf '\t')" "$copy" \
  "SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1 AND b.title IS NOT NULL AND p.url NOT LIKE 'place:%';"
rm -f "$copy"]]

local function chromium_paths()
  local config = (morf.env and morf.env("XDG_CONFIG_HOME")) or (morf.fs.home() .. "/.config")
  local out = {}
  for _, name in ipairs { "chromium", "google-chrome", "BraveSoftware/Brave-Browser", "vivaldi", "microsoft-edge" } do
    local path = config .. "/" .. name .. "/Default/Bookmarks"
    if morf.fs.exists(path) then out[#out + 1] = path end
  end
  return out
end

local function own()
  local out = {}
  local ok, list = pcall(function() return require("config").get("launcher.bookmarks") end)
  for _, mark in ipairs(ok and type(list) == "table" and list or {}) do
    if type(mark) == "table" and mark.url then
      out[#out + 1] = { name = mark.name or mark.url, url = mark.url, folder = mark.folder or "" }
    end
  end
  return out
end

--- Every bookmark that can be found, handed to `done` off the loop; `tool_dir`
--- is the folder of the `bookmark` tool's files.
function M.read(tool_dir, done)
  local out, seen = {}, {}
  local function add(list)
    for _, mark in ipairs(list) do
      if not seen[mark.url] then
        seen[mark.url] = true
        out[#out + 1] = mark
      end
    end
  end
  add(own())
  if tool_dir then add(M.tool_file(tool_dir .. "/webmarks_v0.1.json", "default")) end
  local function finish()
    local paths = chromium_paths()
    if #paths == 0 then done(out) return end
    morf.fs.read_async(paths, function(_, contents)
      for _, text in ipairs(type(contents) == "table" and contents or {}) do
        if type(text) == "string" then add(M.chromium(text)) end
      end
      done(out)
    end)
  end
  return morf.process.run({ "sh", "-c", FIREFOX }, { timeout_ms = 5000 }, function(result)
    local list = {}
    for line in tostring(result and result.stdout or ""):gmatch("[^\n]+") do
      local title, url = line:match("^([^\t]*)\t(.+)$")
      if url then list[#list + 1] = { name = title ~= "" and title or url, url = url, folder = "" } end
    end
    add(list)
    finish()
  end)
end

return M
