-- Real CLI tests use only a scratch TASKRC and TASKDATA, never the user's.
-- morf test --no-dbus tests/lib_taskwarrior_spec.lua
local test = morf.test
local function on_path(name)
  for dir in (morf.env("PATH") or "/usr/local/bin:/usr/bin:/bin"):gmatch("[^:]+") do
    if morf.fs.is_file(dir .. "/" .. name) then return true end
  end
  return false
end
local HOST = [[
  local lib = require("lib.integrations.taskwarrior")
  local root = morf.env("TASK_TEST_ROOT")
  local client = lib.new { env = { TASKRC = root .. "/taskrc", TASKDATA = root .. "/data" } }
  morf.ipc.refresh = client.refresh
  morf.ipc.tasks = function() return morf.json.encode(client.tasks:get()) end
  morf.ipc.error = function() return client.error:get() end
  morf.ipc.missing = function() return client.missing:get() end
  morf.ipc.busy = function() return client.busy:get() end
  morf.ipc.save = function(id, json) return client.save(id ~= "" and id or nil, morf.json.decode(json)) end
  morf.ipc.action = client.action
  morf.ipc.date = lib.date
]]
local count = 0
local function load()
  count = count + 1
  local root = morf.env("XDG_CACHE_HOME") .. "/taskwarrior-spec-" .. count
  assert(morf.fs.write(root .. "/taskrc", "confirmation=off\n"))
  test.load { source = HOST, env = { TASK_TEST_ROOT = root } }
end
local function settled()
  test.wait(function() return not test.ipc("busy") end, 5000, "Taskwarrior command")
  test.eq(test.ipc("error"), "")
end
local function tasks() return morf.json.decode(test.ipc("tasks")) end
local function save(id, fields)
  test.eq(test.ipc("save", id or "", morf.json.encode(fields)), true)
  settled()
end

test.describe("taskwarrior", function()
  if not on_path("task") then
    test.skip("real task CRUD", "task executable is not installed")
  else
    test.it("adds, schedules, edits, starts, stops, completes and deletes real tasks", function()
      load()
      test.ipc("refresh") settled()
      test.eq(#tasks(), 0)
      local description = "Call Alex; +tag due:tomorrow $(literal)"
      save(nil, { description = description, project = "work.website", priority = "H",
        tags = "work,calls", scheduled = "2030-10-01T09:30", due = "2030-10-02T17:00" })
      local first = tasks()[1]
      test.eq(first.description, description)
      test.eq(first.project, "work.website")
      test.eq(first.priority, "H")
      test.eq(test.ipc("date", first.scheduled), "2030-10-01T09:30")
      test.eq(test.ipc("date", first.due), "2030-10-02T17:00")
      save(first.uuid, { description = "Updated task", priority = "L", tags = "home", due = "", scheduled = "" })
      first = tasks()[1]
      test.eq(first.description, "Updated task")
      test.eq(first.project, "work.website", "unmodified fields survive editing")
      test.eq(first.tags, { "home" })
      test.eq(first.due, nil)
      test.eq(first.scheduled, nil)
      test.ipc("action", first.uuid, "start") settled()
      test.truthy(tasks()[1].start)
      test.ipc("action", first.uuid, "stop") settled()
      test.eq(tasks()[1].start, nil)
      test.ipc("action", first.uuid, "done") settled()
      test.eq(#tasks(), 0)
      save(nil, { description = "Temporary task", wait = "2030-11-01" })
      test.eq(#tasks(), 1, "waiting tasks are included")
      test.ipc("action", tasks()[1].uuid, "delete") settled()
      test.eq(#tasks(), 0)
      save(nil, { description = "Weekly review", due = "today+9h", recur = "weekly", ["until"] = "today+30d" })
      test.truthy(#tasks() > 0, "the first recurring occurrence should be visible")
      test.eq(tasks()[1].description, "Weekly review")
      test.eq(tasks()[1].recur, "weekly")
    end)

    test.it("makes a fresh machine work: no rc at all gets one of eva's", function()
      local home = morf.env("XDG_CACHE_HOME") .. "/taskwarrior-fresh-home"
      test.load { source = [[
        local lib = require("lib.integrations.taskwarrior")
        local client = lib.new()
        morf.ipc.refresh = client.refresh
        morf.ipc.error = function() return client.error:get() end
        morf.ipc.busy = function() return client.busy:get() end
        morf.ipc.count = function() return #client.tasks:get() end
        morf.ipc.loaded = function() return client.loaded:get() end
        morf.ipc.save = function(text) return client.save(nil, { description = text }) end
        morf.ipc.rc = function() local e = lib.environment() return e and e.TASKRC or "" end
      ]], env = { HOME = home, TASKRC = "", TASKDATA = "", XDG_CONFIG_HOME = home .. "/.config" } }
      test.ipc("refresh") settled()
      test.truthy(test.ipc("loaded"))
      test.eq(test.ipc("count"), 0)
      test.truthy(test.ipc("save", "First task"))
      settled()
      test.wait(function() return test.ipc("count") == 1 end, 5000, "the new task")
      test.truthy(morf.fs.is_file(test.ipc("rc")), "eva's rc is written")
      test.truthy(morf.fs.read(test.ipc("rc")):find("data.location=" .. home .. "/.task", 1, true),
        "the rc names the home this run resolved")
      test.falsy(morf.fs.is_file(home .. "/.taskrc"), "the person's home keeps no rc of ours")
      test.truthy(morf.fs.is_file(home .. "/.task/taskchampion.sqlite3"), "the tasks stayed in the sandbox")
    end)

    test.it("leaves a person's own rc and TASKRC alone", function()
      local home = morf.env("XDG_CACHE_HOME") .. "/taskwarrior-own-home"
      assert(morf.fs.write(home .. "/.taskrc", "confirmation=off\n", { parents = true }))
      local SOURCE = [[
        local lib = require("lib.integrations.taskwarrior")
        morf.ipc.rc = function() return lib.environment() == nil end
      ]]
      test.load { source = SOURCE, env = { HOME = home, TASKRC = "", XDG_CONFIG_HOME = home .. "/.config" } }
      test.truthy(test.ipc("rc"), "~/.taskrc is the person's")
      test.load { source = SOURCE, env = { HOME = home .. "/none", TASKRC = "/some/where/rc" } }
      test.truthy(test.ipc("rc"), "TASKRC is the person's, even if it names nothing yet")
    end)
  end

  test.it("says nothing of its own when task is not installed, and flags it", function()
    test.load { source = [[
      local client = require("lib.integrations.taskwarrior").new { command = "/nonexistent/task" }
      morf.ipc.refresh = client.refresh
      morf.ipc.error = function() return client.error:get() end
      morf.ipc.missing = function() return client.missing:get() end
      morf.ipc.busy = function() return client.busy:get() end
    ]] }
    test.ipc("refresh")
    test.wait(function() return not test.ipc("busy") end, 1000)
    test.eq(test.ipc("error"), "")
    test.eq(test.ipc("missing"), true)
  end)

  test.it("rejects unscoped mutations and reports CLI errors", function()
    load()
    test.eq(test.ipc("action", "", "delete"), false)
    test.eq(test.ipc("save", "", '{"description":""}'), false)
    test.eq(test.ipc("save", "", '{"description":"Repeat","recur":"weekly"}'), false)
    test.stub_run("task", { code = 1, stderr = "Task database locked" })
    test.ipc("refresh")
    test.wait(function() return not test.ipc("busy") end, 1000)
    test.eq(test.ipc("error"), "The task list could not be opened.")
  end)

  test.it("speaks plainly for every way task fails, and keeps its words off the page", function()
    local CASES = {
      { "'notadate' is not a valid date in the 'Y-M-D' format.", "A date there could not be read. Try tomorrow or 2026-10-01T09:00." },
      { "Invalid dependency value: 'zzz'", "A task it depends on could not be found." },
      { "The duration value 'sometimes' is not supported.", "That repeat could not be read. Try daily, weekly or monthly." },
      { "Could not read include file '/nonexistent/x'.", "Taskwarrior's settings could not be read." },
      { "Cannot proceed without rc file.", "Taskwarrior's settings could not be read." },
      { 'Task Database Error: Cannot create directory "/home/x/.task": Permission denied (os error 13)',
        "The task list could not be opened." },
      { "something task has never said before", "Tasks could not be read just now." },
    }
    load()
    for _, case in ipairs(CASES) do
      test.stub_run("task", { code = 2, stderr = case[1] })
      test.ipc("refresh")
      test.wait(function() return not test.ipc("busy") end, 1000)
      test.eq(test.ipc("error"), case[2], case[1])
    end
  end)


end)
