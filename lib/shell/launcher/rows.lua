-- The rows every mode builds. A row is `{ kind = "menu", id, name, description,
-- material | icon | swatch | glyph | image, run, actions, tag, complete, path,
-- preview, pin }`: Return runs `run`; the action panel lists `actions`, each
-- `{ name, material, run }`; `tag` is the small word at its end; Tab puts
-- `complete` in the field; `path` is the file it stands for; `preview` is what
-- quick look shows; `pin` is the name it is pinned by. A run returns "close",
-- "keep", or a new query for the field.

local morf = require("morf")
local run = require("lib.shell.launcher.run")
local asker = require("lib.shell.launcher.asker")

local M = {}

local home = (morf.env and morf.env("HOME")) or morf.fs.home()
M.home = home

--- Moves as an answer lands; the search runs again on it.
M.revision = morf.signal("eva.providers.revision", 0)
function M.bump() M.revision:set(M.revision:get() + 1) end

--- Asks what takes a while: `ask(slot, question, start, options)`, see
--- lib/shell/launcher/asker.lua.
M.ask = asker.new { on_answer = M.bump }

--- The first program of `names` that is on PATH.
function M.first_of(names)
  for _, name in ipairs(names) do
    if run.has(name) then return name end
  end
end

--- Asks `argv` and hands its output through `parse`. nil and false until it
--- answers; a failed run answers `failed` (`{}` by default).
function M.ask_run(slot, question, argv, parse, options)
  options = options or {}
  return M.ask(slot, question, function(done)
    return morf.process.run(argv, { timeout_ms = options.timeout_ms or 8000, max_output = options.max_output,
      env = options.env, cwd = options.cwd }, function(result)
      if result and (result.ok or options.any_exit) then done(parse(tostring(result.stdout or ""), result))
      else done(options.failed or {}) end
    end)
  end, options)
end

function M.row(t)
  t.kind = t.kind or "menu"
  return t
end

--- `path` with the home folder written `~`.
function M.tilde(path)
  if path:sub(1, #home) == home then return "~" .. path:sub(#home + 1) end
  return path
end

--- `path` with a leading `~` written out.
function M.untilde(path)
  if path == "~" then return home end
  if path:sub(1, 2) == "~/" then return home .. path:sub(2) end
  return path
end

--- `list` fuzzily matched on `term` (`key` is morf.text.fuzzy's), best first.
function M.fuzzy(list, term, key)
  if term == "" then return list end
  local out = {}
  for _, hit in ipairs(morf.text.fuzzy(term, list, { key = key or { "name", { "description", 0.4 } } })) do
    out[#out + 1] = hit.item
  end
  return out
end

--- A row that says something and does nothing.
function M.note(id, name, description, material)
  return M.row { id = id, name = name, description = description, material = material or "info",
    run = function() return "keep" end, silent = true }
end

--- A row whose Return copies `value`.
function M.copy(id, name, description, material, value)
  value = value == nil and name or value
  return M.row { id = id, name = name, description = description, material = material or "content_copy",
    run = function() return run.copy(value) end, copy = value }
end

local IMAGE = { png = true, jpg = true, jpeg = true, webp = true, gif = true, bmp = true, svg = true, avif = true }

--- Whether `path` is a picture.
function M.is_image(path)
  return IMAGE[(path:match("%.([^./]+)$") or ""):lower()] == true
end

--- The row for a file or a folder.
function M.file(path, folder, tag)
  local name = path:match("([^/]+)/?$") or path
  local parent = path:match("^(.*)/[^/]*$") or home
  if parent == "" then parent = "/" end
  return M.row {
    id = "file:" .. path, name = name, description = M.tilde(path), path = path, folder = folder, tag = tag,
    image = (not folder and M.is_image(path)) and path or nil,
    material = folder and "folder" or "draft", pin = "file:" .. path,
    preview = { path = path, folder = folder },
    run = function() return run.open(path) end,
    actions = {
      { name = "Open", material = "open_in_new", run = function() return run.open(path) end },
      { name = "Open with…", material = "apps", run = function()
        return require("launcher_modes.files").open_with(path)
      end },
      { name = "Open a terminal there", material = "terminal",
        run = function() return run.terminal(nil, folder and path or parent) end },
    },
  }
end

return M
