-- The shell's font: the installed families, listed only when a picker opens with no
-- background scan, and `set`, the one way the UI font changes.
local morf = require("morf")
local M = {
  opened = morf.signal("appearance.fonts.opened", false),
  query = morf.signal("appearance.fonts.query", ""),
  page = morf.signal("appearance.fonts.page", 1),
  rows = morf.signal("appearance.fonts.rows", {}),
  status = morf.signal("appearance.fonts.status", ""),
}
local families, loading = nil, false
function M.filter(query)
  M.query:set(query)
  M.page:set(1)
  local rows, needle = {}, query:lower()
  for _, family in ipairs(families or {}) do
    if family:lower():find(needle, 1, true) then rows[#rows + 1] = family end
  end
  M.rows:set(rows)
end
function M.open()
  M.opened:set(true)
  if families or loading then return end
  loading = true
  M.status:set("Loading installed fonts…")
  morf.process.run({"fc-list", "--format", "%{family[0]}\n"}, {timeout_ms=5000,max_output=262144}, function(result)
    loading = false
    if not result.ok then M.status:set("Could not read installed fonts. Open again to retry.") return end
    families = {}
    local seen = {}
    for family in (result.stdout or ""):gmatch("[^\r\n]+") do
      family = family:match("^%s*(.-)%s*$")
      if family ~= "" and M.fit(family) and not seen[family:lower()] then
        seen[family:lower()] = true
        families[#families + 1] = family
      end
    end
    table.sort(families, function(a,b) return a:lower()<b:lower() end)
    M.status:set("")
    M.filter(M.query:get())
  end)
end
function M.close() M.opened:set(false) end
function M.step(delta, size)
  M.page:set(math.max(1, math.min(math.max(1, math.ceil(#M.rows:get()/size)), M.page:get()+delta)))
end

--- Whether `family` can be a family's name, "" being the theme's own font.
function M.fit(family)
  return type(family) == "string" and #family <= 200 and not family:find("%c")
end

--- Whether this machine has `family`, once the families are listed.
function M.has(family)
  for _, installed in ipairs(families or {}) do
    if family == installed then return true end
  end
  return false
end

--- The shell's font, "" for the theme's own: the running shell's where one answers,
--- else the file it starts from. `via` is a tool's `common.sys`: `done(font, up)`.
function M.current(via, done)
  via.shell({ "appearance", "state" }, { read = true }, function(state)
    if type(state) == "table" then done(state.font or "", true) return end
    done(require("themes").preferences.get("font") or "", false)
  end)
end

local function named(family) return family ~= "" and family or "the theme's own font" end

-- A font file on this shell: it wins over a family, and takes a reload to build.
local function set_file(path, done)
  path = path:gsub("^~/", morf.fs.home() .. "/")
  if path ~= "" and not morf.fs.is_file(path) then return done(false, "No font file at " .. path) end
  require("config").set("appearance.font_file", path)
  if path ~= "" then
    local kept = require("themes").preferences
    kept.set("font", "")
    kept.flush()
  end
  done(true, "The shell is changing font")
  require("themes.session").hold()
  morf.reload()
end

-- A family inside the shell: the switcher covers the panels, reloads and keeps it.
local function set_in_shell(family, done)
  local switcher = require("themes.switcher")
  if family == (require("themes").font or "") then return done(true, "The shell already uses " .. named(family)) end
  if switcher.request_font(family) then return done(true, "The shell is changing to " .. named(family)) end
  done(false, switcher.message:get())
end

-- A family from a tool: the `appearance` verb with the shell up, which does the same
-- as above, and the file it starts from with it down.
local function set_from_tool(family, via, done)
  M.current(via, function(font, up)
    if not up then
      if via.dry() then return done(true, "Would save " .. named(family)) end
      local kept = require("themes").preferences
      kept.set("font", family)
      kept.flush()
      return done(true, "Saved " .. named(family) .. ": the shell takes it when it starts")
    end
    if font == family then return done(true, "The shell already uses " .. named(family)) end
    via.shell({ "appearance", "font:" .. family }, nil, function(reply, why)
      if reply == true then return done(true, "The shell is changing to " .. named(family)) end
      if why == "dry run" then return done(true, "Would ask the shell for " .. named(family)) end
      -- A refusal: the reason is in the shell's state.
      via.shell({ "appearance", "state" }, { read = true }, function(state)
        local reason = type(state) == "table" and state.message or ""
        done(false, reason ~= "" and reason or "The shell did not take it")
      end)
    end)
  end)
end

--- Sets the UI font, for the Look page, the Lule picker and eva-fonts alike.
--- `choice` is `{ family = name }`, "" for the theme's own, or `{ file = path }`, ""
--- for the installed faces; `choice.via` is a tool's `common.sys`, for a caller
--- outside the shell. `done(ok, words)`.
function M.set(choice, done)
  done = done or function() end
  if choice.file then return set_file(choice.file, done) end
  if not M.fit(choice.family) then return done(false, "That is not a family's name") end
  if choice.via then return set_from_tool(choice.family, choice.via, done) end
  set_in_shell(choice.family, done)
end

--- Sets the family a picker offered, shutting it once that is taken.
function M.choose(family)
  if family ~= "" and not M.has(family) then return end
  M.set({ family = family }, function(ok) if ok then M.close() end end)
end
return M
