-- The Backups page: which tool, what it holds, making one, and getting one file
-- back. Replacing a file takes a second press naming it. No nodes.
local morf = require("morf")
local config = require("config")
local backups = require("lib.services.backups")
local page_model = require("page_model")
local M = {}

function M.new(active)
  local model = page_model.new("backups", active)
  local name = "eva.backups."
  model.rows = morf.signal(name .. "rows", {})
  model.chosen = morf.signal(name .. "chosen", false)
  model.path = morf.signal(name .. "path", "")
  model.confirming = morf.signal(name .. "confirming", false)
  model.tools = morf.signal(name .. "tools", {})
  model.loading = morf.signal(name .. "loading", false)
  model.locked = morf.signal(name .. "locked", false)
  model.needs = backups.needs
  local serial = 0

  --- The tool in use: the one chosen in the settings, or the first here.
  function model.tool()
    local wanted, tools = config.get("backups.tool"), model.tools:get()
    for _, row in ipairs(tools) do if row.id == wanted then return row.id end end
    return tools[1] and tools[1].id or nil
  end
  function model.set_tool(id)
    config.set("backups.tool", id)
    model.refresh()
  end
  --- Whether any tool is here.
  function model.any() return model.tool() ~= nil end

  --- Reads what the tool holds. `asked`: a person pressed for it, and polkit
  --- may ask them for a password.
  function model.refresh(asked)
    local tool = model.tool()
    model.chosen:set(false)
    model.confirming:set(false)
    model.locked:set(false)
    if not tool then model.rows:set({}) return end
    serial = serial + 1
    local mine = serial
    model.loading:set(true)
    backups.list(tool, function(rows, why, needs_root)
      if mine ~= serial then return end
      model.loading:set(false)
      if rows then model.rows:set(rows) return end
      model.rows:set({})
      model.locked:set(needs_root == true)
      if needs_root then model.say("") else model.say(tostring(why), true) end
    end, asked == true)
  end
  function model.unlock() model.refresh(true) end
  model.on_show(function()
    model.tools:set(backups.available())
    model.refresh()
  end)

  --- Makes one now: not a change to anything there is, so it asks nothing.
  function model.create()
    local tool = model.tool()
    if not tool then return false end
    return model.action(function(done) backups.create(tool, done) return true end, function()
      model.say("Made one.")
      model.refresh()
    end)
  end

  function model.choose(row)
    model.chosen:set(model.chosen:get() ~= row.id and row.id or false)
    model.confirming:set(false)
    model.say("")
  end
  local function selected()
    for _, row in ipairs(model.rows:get()) do
      if row.id == model.chosen:get() then return row end
    end
  end
  model.selected = selected
  function model.set_path(path)
    model.path:set(path)
    model.confirming:set(false)
  end

  --- A copy beside the file: nothing is lost, so it asks nothing.
  function model.restore_copy()
    local row = selected()
    if not row then return false end
    return model.action(function(done)
      backups.restore(model.tool(), row, model.path:get(), "copy", done)
      return true
    end, function(where) model.say("Restored to " .. tostring(where)) end)
  end

  --- The first press asks, the second replaces the file.
  function model.restore_replace()
    local row = selected()
    if not row or model.path:get():match("^%s*$") then
      model.say("Give the file's whole path first.", true)
      return false
    end
    if not model.confirming:get() then
      model.confirming:set(true)
      model.say("This overwrites " .. model.path:get() .. " with the one in the snapshot. Press again to do it.", true)
      return false
    end
    model.confirming:set(false)
    return model.action(function(done)
      backups.restore(model.tool(), row, model.path:get(), "replace", done)
      return true
    end, function(where) model.say("Replaced " .. tostring(where)) end)
  end
  function model.keep_file()
    model.confirming:set(false)
    model.say("")
  end
  return model
end

return M
