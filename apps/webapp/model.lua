-- eva-webapp: a site as an app of its own: a desktop entry that opens it in a
-- Chromium-family browser's app window, and an icon from the site or a letter
-- tile. No nodes.
local morf = require("morf")
local sys = require("apps.common.sys")
local desktop = require("lib.util.desktop")
local remote = require("lib.util.remote")
local unicase = require("lib.util.unicase")

local M = {
  rows = morf.signal("webapp.rows", {}),
  name = morf.signal("webapp.name", ""),
  url = morf.signal("webapp.url", ""),
  message = morf.signal("webapp.message", ""),
  busy = morf.signal("webapp.busy", false),
}

M.BROWSERS = { "chromium", "chromium-browser", "google-chrome-stable", "google-chrome", "brave", "brave-browser",
  "vivaldi", "vivaldi-stable", "microsoft-edge", "microsoft-edge-stable" }

local PREFIX = "eva-webapp-"
local URL_KEY = "X-Eva-Webapp-Url"
local TILE = 256
local TIMEOUT_MS = 8000
local MAX_BYTES = 4 * 1024 * 1024

local function data_home()
  return morf.env("XDG_DATA_HOME") or (morf.fs.home() .. "/.local/share")
end

local function entry_dir() return data_home() .. "/applications" end
local function icon_dir() return data_home() .. "/icons" end
local function entry_path(slug) return entry_dir() .. "/" .. PREFIX .. slug .. ".desktop" end
local function icon_path(slug) return icon_dir() .. "/" .. PREFIX .. slug .. ".png" end

--- `name` as a file name holds it.
function M.slug(name)
  local slug = tostring(name or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  slug = slug:sub(1, 48):gsub("%-+$", "")
  return slug ~= "" and slug or "app"
end

--- The browser that can open an app window, or nil and why not.
function M.browser()
  for _, name in ipairs(M.BROWSERS) do
    if sys.has(name) then return name end
  end
  if sys.has("firefox") then
    return nil, "Firefox has no --app window: install a Chromium-family browser"
  end
  return nil, "No Chromium-family browser: install Chromium, Chrome, Brave, Vivaldi or Edge"
end

--- `url` with a scheme, or nil where it cannot be one.
function M.address(url)
  url = tostring(url or ""):match("^%s*(.-)%s*$")
  if url == "" or url:find("[%c%s]") then return nil end
  if not url:find("^%a[%w+.-]*://") then url = "https://" .. url end
  if not url:match("^https?://[^/?#]+") then return nil end
  return url
end

local function origin(url) return url:match("^(%a+://[^/?#]+)") end

-- What `href` means on the page at `base`.
local function absolute(base, href)
  href = href:gsub("&amp;", "&")
  if href:find("^%a[%w+.-]*:") then return href:find("^https?://") and href or nil end
  if href:find("^//") then return base:match("^(%a+:)") .. href end
  if href:find("^/") then return origin(base) .. href end
  local folder = base:gsub("[?#].*$", ""):match("^(%a+://.*/)") or (origin(base) .. "/")
  return folder .. href
end

-- The attributes of a tag, their names in lower case.
local function attributes(tag)
  local out = {}
  for key, value in tag:gmatch("([%w%-:]+)%s*=%s*\"([^\"]*)\"") do out[key:lower()] = value end
  for key, value in tag:gmatch("([%w%-:]+)%s*=%s*'([^']*)'") do out[key:lower()] = out[key:lower()] or value end
  for key, value in tag:gmatch("([%w%-:]+)%s*=%s*([^%s\"'>]+)") do out[key:lower()] = out[key:lower()] or value end
  return out
end

--- The icons a page names, largest first.
function M.icon_links(html, base)
  local found = {}
  for tag in tostring(html or ""):gmatch("<[Ll][Ii][Nn][Kk]%s[^>]*>") do
    local attrs = attributes(tag)
    local rel = (attrs.rel or ""):lower()
    if attrs.href and rel:find("icon", 1, true) and not rel:find("mask", 1, true) then
      local url = absolute(base, attrs.href)
      local size = tonumber((attrs.sizes or ""):match("(%d+)")) or (attrs.href:lower():find("%.svg") and 512) or
        (rel:find("apple", 1, true) and 180) or 16
      if url then found[#found + 1] = { url = url, size = size } end
    end
  end
  table.sort(found, function(a, b) return a.size > b.size end)
  local urls = {}
  for index, item in ipairs(found) do urls[index] = item.url end
  return urls
end

local function little(bytes, at, count)
  local value = 0
  for index = count - 1, 0, -1 do value = value * 256 + (bytes:byte(at + index) or 0) end
  return value
end

--- The largest PNG inside an `.ico`, or nil.
function M.ico_png(bytes)
  if little(bytes, 1, 2) ~= 0 or little(bytes, 3, 2) ~= 1 then return nil end
  local best, area
  for index = 0, little(bytes, 5, 2) - 1 do
    local entry = 7 + index * 16
    local width, height = bytes:byte(entry) or 0, bytes:byte(entry + 1) or 0
    width, height = width == 0 and 256 or width, height == 0 and 256 or height
    local size, offset = little(bytes, entry + 8, 4), little(bytes, entry + 12, 4)
    if bytes:sub(offset + 1, offset + 8) == "\x89PNG\r\n\x1a\n" and (not area or width * height > area) then
      best, area = bytes:sub(offset + 1, offset + size), width * height
    end
  end
  return best
end

local function save(path, bytes)
  morf.fs.mkdir(icon_dir(), { parents = true })
  return morf.fs.write(path, bytes, { atomic = true, parents = true })
end

-- Makes the picture at `source` a PNG at the slug's icon: `done(path)`, nil
-- where it cannot be read.
local function as_png(source, slug, done)
  local target = icon_path(slug)
  local ok, queued = pcall(morf.image.process, { source = source, output = target,
    ops = { { "resize", TILE, TILE, "fit" } },
    on_done = function(good) done(good and target or nil) end })
  if not ok or not queued then done(nil) end
end

-- Keeps `bytes` of an image as the slug's icon.
local function keep(bytes, url, slug, done)
  local kind = remote.kind(bytes, url)
  if kind == "ico" or (bytes:sub(1, 4) == "\0\0\1\0") then
    bytes = M.ico_png(bytes)
    if not bytes then done(nil) return end
    kind = "png"
  end
  if kind ~= "png" and kind ~= "jpg" and kind ~= "webp" and kind ~= "gif" and kind ~= "svg" then done(nil) return end
  local holding = icon_dir() .. "/" .. PREFIX .. slug .. ".source." .. kind
  if not save(holding, bytes) then done(nil) return end
  as_png(holding, slug, function(path)
    morf.fs.remove(holding)
    done(path)
  end)
end

-- A colour of its own for each name.
local function tile_colour(slug)
  local hue = 0
  for index = 1, #slug do hue = (hue * 31 + slug:byte(index)) % 360 end
  local c, m = 0.55, 0.3
  local x = c * (1 - math.abs((hue / 60) % 2 - 1))
  local band = hue // 60
  local r, g, b = 0, 0, 0
  if band == 0 then r, g = c, x elseif band == 1 then r, g = x, c elseif band == 2 then g, b = c, x
  elseif band == 3 then g, b = x, c elseif band == 4 then r, b = x, c else r, b = c, x end
  return ("#%02x%02x%02x"):format(math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255))
end

--- The first letter of `name`, for a tile.
function M.letter(name)
  local first = unicase.first(tostring(name or ""))
  return unicase.upper(first == "" and "?" or first):gsub("[&<>]", "?")
end

local function letter_tile(name, slug, done)
  morf.fs.mkdir(icon_dir(), { parents = true })
  local mark = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' ..
    '<rect width="%d" height="%d" rx="56" fill="%s"/>' ..
    '<text x="128" y="176" font-family="sans-serif" font-size="136" font-weight="600" text-anchor="middle" fill="white">%s</text>' ..
    "</svg>"):format(TILE, TILE, TILE, TILE, tile_colour(slug), M.letter(name))
  local target = icon_path(slug)
  local ok, queued = pcall(morf.image.compose, { width = TILE, height = TILE, background = "#00000000", output = target,
    ops = { { "overlay", mark, 0, 0 } }, on_done = function(good) done(good and target or nil) end })
  if not ok or not queued then done(nil) end
end

local function get(url, done)
  morf.http.get(url, { timeout_ms = TIMEOUT_MS, max_bytes = MAX_BYTES }, function(response)
    done(response and response.ok and type(response.body) == "string" and #response.body > 0 and response.body or nil)
  end)
end

-- The site's icon: what the page names, then its /favicon.ico. `done(path)`.
local function site_icon(url, slug, done)
  get(url, function(page)
    local list = M.icon_links(page, url)
    list[#list + 1] = origin(url) .. "/favicon.ico"
    local function try(index)
      local candidate = list[index]
      if not candidate then done(nil) return end
      get(candidate, function(bytes)
        if not bytes then try(index + 1) return end
        keep(bytes, candidate, slug, function(path)
          if path then done(path) else try(index + 1) end
        end)
      end)
    end
    try(1)
  end)
end

-- A person's own picture as the icon.
local function file_icon(file, slug, done)
  local bytes = morf.fs.read(file)
  if not bytes then done(nil) return end
  keep(bytes, file, slug, done)
end

--- A row of the file at `path`, or nil.
local function row_of(path)
  local keys = desktop.parse(morf.fs.read(path))
  local slug = path:match("eva%-webapp%-(.+)%.desktop$")
  if not slug or not keys.Name then return nil end
  return { slug = slug, name = keys.Name, url = keys[URL_KEY] or "", icon = keys.Icon or "", path = path }
end

--- The apps made, by name.
function M.read()
  local rows = {}
  for _, entry in ipairs(morf.fs.list(entry_dir()) or {}) do
    if entry.name:sub(1, #PREFIX) == PREFIX then
      local row = row_of(entry_dir() .. "/" .. entry.name)
      if row then rows[#rows + 1] = row end
    end
  end
  table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
  return rows
end

function M.refresh() M.rows:set(M.read()) end

--- The command that opens the app.
function M.command(browser, url, slug)
  return { browser, "--app=" .. url, "--class=" .. PREFIX .. slug }
end

--- The desktop entry of an app.
function M.entry(name, url, slug, browser, icon)
  local text = desktop.set("", "Type", "Application")
  for _, pair in ipairs {
    { "Name", name }, { "Comment", url }, { "Exec", desktop.exec(M.command(browser, url, slug)) }, { "Icon", icon },
    { "Terminal", "false" }, { "Categories", "Network;" }, { "StartupNotify", "true" },
    { "StartupWMClass", PREFIX .. slug }, { URL_KEY, url },
  } do text = desktop.set(text, pair[1], pair[2]) end
  return text
end

--- Makes the app: `done(row)`, or nil and why.
function M.add(name, url, file, done)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  if name == "" then done(nil, "Give it a name") return end
  local address = M.address(url)
  if not address then done(nil, "That is no web address") return end
  local browser, why = M.browser()
  if not browser then done(nil, why) return end
  local slug = M.slug(name)
  local path = entry_path(slug)
  if morf.fs.exists(path) then done(nil, name .. " is already there") return end
  if sys.dry() then
    morf.log("info", "eva: write " .. path .. " (dry run)")
    done({ slug = slug, name = name, url = address, path = path, dry = true })
    return
  end
  M.busy:set(true)
  local function finish(icon)
    M.busy:set(false)
    if not icon then done(nil, "Could not make an icon") return end
    if not morf.fs.write(path, M.entry(name, address, slug, browser, icon), { atomic = true, parents = true, mode = 420 }) then
      done(nil, "Could not write " .. path)
      return
    end
    M.refresh()
    done(row_of(path))
  end
  local function tile() letter_tile(name, slug, finish) end
  if file and file ~= "" then
    file_icon(file, slug, function(icon)
      if icon then finish(icon) return end
      M.busy:set(false)
      done(nil, "Cannot read the picture " .. file)
    end)
    return
  end
  site_icon(address, slug, function(icon)
    if icon then finish(icon) else tile() end
  end)
end

--- The app `name` means, by its name or its slug.
function M.find(name)
  local wanted = tostring(name or ""):lower()
  for _, row in ipairs(M.read()) do
    if row.name:lower() == wanted or row.slug == wanted or row.slug == M.slug(name) then return row end
  end
end

--- Takes the app and its icon away.
function M.remove(row)
  if sys.dry() then
    morf.log("info", "eva: remove " .. row.path .. " (dry run)")
    return
  end
  morf.fs.remove(row.path)
  if row.icon:sub(1, #icon_dir()) == icon_dir() then morf.fs.remove(row.icon) end
  M.refresh()
end

--- Opens the app.
function M.open(row)
  local browser, why = M.browser()
  if not browser then M.message:set(why) return end
  sys.detach(M.command(browser, row.url, row.slug))
end

--- What the window's form asks.
function M.submit()
  M.message:set("")
  M.add(M.name:get(), M.url:get(), nil, function(row, why)
    if not row then M.message:set(why) return end
    M.name:set("")
    M.url:set("")
    M.message:set(row.name .. " is an app now")
  end)
end

--- `done(text, why)` with the answer to `args`.
function M.job(args, done)
  local how = args[1]
  if how == "add" then
    local name, url, file = args[2], args[3], nil
    if args[4] == "--icon" then file = args[5] end
    if not name or not url then done(nil, "usage: eva-webapp add NAME URL [--icon FILE]") return end
    M.add(name, url, file, function(row, why)
      if not row then done(nil, why) return end
      done(row.path)
    end)
  elseif how == "list" then
    local lines = {}
    for _, row in ipairs(M.read()) do lines[#lines + 1] = row.name .. "  " .. row.url end
    done(#lines > 0 and table.concat(lines, "\n") or "no web apps")
  elseif how == "remove" then
    local row = M.find(args[2])
    if not row then done(nil, "nothing called " .. tostring(args[2])) return end
    M.remove(row)
    done("removed " .. row.name)
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

return M
