-- Workspace names, layouts, scratchpads and the workspace display, read back
-- from the window stand-in.
local test = morf.test

local SCENE = [[{"focus":1,"workspaces":[{"id":1},{"id":2}],"clients":[
  {"class":"zzterm","title":"one","workspace":1},
  {"class":"zzweb","title":"web","workspace":2},
  {"class":"zzmusic","title":"tunes","workspace":"special:music"}]}]]

local function load()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, env = { EVA_FAKE_WINDOWS = SCENE, EVA_DRY_RUN = "1" } })
  test.advance(200)
end

local function last_wire()
  local wire = test.ipc("windows", "wire")
  return wire[#wire] or ""
end

test.it("a workspace is named on the compositor, and the name stays in the settings", function()
  load()
  test.eq(test.ipc("workspace_name"), "1")
  test.ipc("workspace_name", "code")
  test.advance(16)
  test.contains(last_wire(), 'hl.dsp.workspace.rename({ workspace = "1", name = "code" })')
  test.eq(test.ipc("workspace_name"), "code")
  test.ipc("overview", "open") test.settle(3000)
  test.contains(test.text_of(test.get("overview-desk-1")), "code")
  test.ipc("workspace_name", "") test.advance(16)
  test.eq(test.ipc("workspace_name"), "1")
end)

test.it("the bar numbers a workspace as a whole number", function()
  load()
  test.ipc("bar", "show", "on")
  test.settle(500)
  test.eq(test.text_of(test.get("bar-workspace-1")), "1")
  test.eq(test.text_of(test.get("bar-workspace-2")), "2")
end)

test.it("a double press on a desk asks for a name", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  local desk = test.get("overview-desk-area-2")
  local x, y = desk.x + desk.width / 2, desk.y + desk.height / 2
  test.click(x, y) test.click(x, y) test.advance(50)
  test.truthy(test.get("overview-naming").visible, "no field")
  test.type("mail\n") test.advance(50)
  test.falsy(test.find({ id = "overview-naming", visible = true }))
  test.eq(test.ipc("workspace_name", nil, "2"), "mail", "the name did not reach the workspace pressed")
end)

test.it("each workspace tiles its own way, live", function()
  load()
  test.eq(test.ipc("workspace_layout"), "dwindle")
  test.ipc("workspace_layout", "monocle") test.advance(200)
  test.contains(last_wire(), "j/workspaces")
  local wire = table.concat(test.ipc("windows", "wire"), "\n")
  test.contains(wire, 'hl.workspace_rule({ workspace = "1", layout = "monocle" })')
  test.eq(test.ipc("workspace_layout"), "monocle")
  test.ipc("workspace_layout", "next") test.advance(200)
  test.eq(test.ipc("workspace_layout"), "dwindle")
  test.ipc("overview", "open") test.settle(3000)
  test.click("overview-layout-master") test.advance(200)
  test.eq(test.ipc("workspace_layout"), "master")
  test.eq(test.ipc("workspace_layout", nil, "2") ~= nil, true)
  test.eq(#test.logs("warn"), 0)
end)

test.it("scratchpads are listed, toggled and sent to", function()
  load()
  local list = test.ipc("scratchpad", "list")
  test.eq(list[1].name, "music")
  test.eq(list[1].count, 1.0)
  test.ipc("scratchpad", "music") test.advance(16)
  test.contains(last_wire(), 'hl.dsp.workspace.toggle_special("music")')
  test.truthy(test.ipc("scratchpad", "list")[1].shown)
  test.ipc("scratchpad", "send", "music") test.advance(16)
  test.eq(test.ipc("scratchpad", "list")[1].count, 2.0)
end)

test.it("a card dragged onto a desk or a scratchpad moves its window there", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  local card = test.get("overview-card-area-1")
  local desk = test.get("overview-desk-area-2")
  test.drag({ card.x + 80, card.y + 80 }, { desk.x + 40, desk.y + 40 }, { steps = 8 })
  test.advance(100)
  local one
  for _, w in ipairs(test.ipc("windows")) do if w.title == "one" then one = w end end
  test.eq(one.workspace, 2)
end)

test.it("changing workspace shows its name and what is on it", function()
  load()
  test.ipc("workspace_name", "web", "2")
  test.advance(3000)
  test.ipc("workspace", "2")
  test.advance(500)
  local shown = test.find(function(n) return n.text == "web" and n.visible end)
  test.truthy(shown, "no workspace display")
end)
