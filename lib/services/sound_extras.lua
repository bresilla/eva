-- What morf.audio leaves out: sound cards' profiles and a Bluetooth headset's
-- codec, through PipeWire's `pw-dump` and `wpctl`, and the event sound theme.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

-- Bluetooth codecs, by the word in a profile's name.
local CODECS = { sbc = "SBC", sbc_xq = "SBC XQ", aac = "AAC", aptx = "aptX", aptx_hd = "aptX HD", aptx_ll = "aptX LL",
  ldac = "LDAC", lc3 = "LC3", opus_05 = "Opus", faststream = "FastStream", lhdc = "LHDC", msbc = "mSBC", cvsd = "CVSD" }

--- The codec a profile name carries, as a person calls it, or nil.
function M.codec(profile)
  local word = tostring(profile):match("^a2dp%-sink%-(.+)$") or tostring(profile):match("^a2dp%-source%-(.+)$")
    or tostring(profile):match("^headset%-head%-unit%-(.+)$")
  if word then return CODECS[word] or word:upper() end
  if profile == "a2dp-sink" then return "SBC" end
end

--- `pw-dump`'s devices as `{ key, id, name, title, bluetooth, active, codec,
--- profiles = { { key, index, name, codec } } }`. What is off or unavailable
--- is left out.
function M.parse_cards(text)
  local ok, list = pcall(morf.json.decode, text or "")
  local out = {}
  for _, object in ipairs(ok and type(list) == "table" and list or {}) do
    local info = type(object) == "table" and object.type == "PipeWire:Interface:Device" and object.info
    if info then
      local props, params = info.props or {}, info.params or {}
      local name = props["device.name"] or tostring(object.id)
      local current = (params.Profile or {})[1] or {}
      local row = { key = name, id = object.id, name = name, title = props["device.description"] or name,
        bluetooth = props["device.api"] == "bluez5" or name:find("^bluez_card") ~= nil, active = current.name or "",
        profiles = {} }
      for _, profile in ipairs(params.EnumProfile or {}) do
        if profile.name ~= "off" and profile.available ~= "no" then
          row.profiles[#row.profiles + 1] = { key = profile.name, index = profile.index, name = profile.description or profile.name,
            codec = M.codec(profile.name), priority = tonumber(profile.priority) or 0 }
        end
      end
      table.sort(row.profiles, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.key < b.key
      end)
      row.codec = M.codec(row.active)
      out[#out + 1] = row
    end
  end
  return out
end

--- `done(cards)`.
function M.cards(done)
  if not host.installed("pw-dump") then return done {} end
  host.read({ "pw-dump" }, function(text) done(M.parse_cards(text)) end)
end

--- Sets a card's profile: its codec, for a Bluetooth headset.
function M.set_profile(card, profile, done)
  host.act({ "wpctl", "set-profile", tostring(card.id), tostring(profile.index) }, done)
end

-- --------------------------------------------------------------- the theme --

local SAMPLES = { "bell", "message", "dialog-information", "complete", "audio-volume-change" }
local EXTENSIONS = { "oga", "ogg", "wav" }

--- The folders sound themes live in.
function M.folders()
  local home = morf.fs.home()
  local out = { (morf.env("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/sounds" }
  for dir in (morf.env("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"):gmatch("[^:]+") do out[#out + 1] = dir .. "/sounds" end
  return out
end

--- The themes installed: `{ key, name, path }`.
function M.themes(folders)
  local fake = host.fake() and require("lib.services.host_fake")
  if fake then return fake.sound_themes() end
  local seen, out = {}, {}
  for _, folder in ipairs(folders or M.folders()) do
    local ok, entries = pcall(morf.fs.list, folder, { follow = true })
    for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
      local key = type(entry) == "table" and entry.name or entry
      local index = folder .. "/" .. key .. "/index.theme"
      if not seen[key] and morf.fs.exists(index) then
        seen[key] = true
        local read, text = pcall(morf.fs.read, index)
        out[#out + 1] = { key = key, name = read and tostring(text):match("\nName=([^\n]+)") or key, path = folder .. "/" .. key }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- A sound of `theme` to play: the first of the usual events it has.
function M.sample(theme)
  for _, event in ipairs(SAMPLES) do
    for _, extension in ipairs(EXTENSIONS) do
      local path = theme.path .. "/stereo/" .. event .. "." .. extension
      if morf.fs.exists(path) then return path end
    end
  end
end

--- Plays a theme's sample. `done(ok, why)`.
function M.preview(theme, done)
  local path = M.sample(theme)
  if not path then return done(nil, "This theme has no sample to play") end
  if not host.installed("pw-play") then return done(nil, "Playing a sample needs pw-play") end
  host.act({ "pw-play", path }, done)
end

--- Makes `key` the desktop's sound theme: the toolkits read it from these.
function M.apply(key, done)
  local home = morf.env("XDG_CONFIG_HOME") or (morf.fs.home() .. "/.config")
  if host.held("sound theme " .. key) then return done(true) end
  if host.installed("gsettings") then
    host.act({ "gsettings", "set", "org.gnome.desktop.sound", "theme-name", key })
  end
  local path = home .. "/gtk-3.0/settings.ini"
  if host.managed(path) then return done(nil, "gtk-3.0/settings.ini is managed by Home Manager") end
  local ok, text = pcall(morf.fs.read, path)
  text = ok and type(text) == "string" and text or "[Settings]\n"
  if text:find("gtk%-sound%-theme%-name%s*=") then
    text = text:gsub("gtk%-sound%-theme%-name%s*=[^\n]*", "gtk-sound-theme-name=" .. key)
  else
    text = text:gsub("%s*$", "") .. "\ngtk-sound-theme-name=" .. key .. "\n"
  end
  morf.fs.mkdir(home .. "/gtk-3.0")
  local wrote, why = pcall(morf.fs.write, path, text)
  done(wrote or nil, not wrote and tostring(why) or nil)
end

return M
