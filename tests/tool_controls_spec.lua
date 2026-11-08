-- What a tool's page is built from (apps/common/controls.lua, sys.lua), in both
-- themes, through a tool that uses all of it. The clock's own spec covers them in
-- real use.
--
--     morf test --no-dbus tests/tool_controls_spec.lua

local test = morf.test

local TOOL = [[
  local morf = require("morf")
  local ui = require("morf.ui")
  local controls = require("apps.common.controls")
  local sys = require("apps.common.sys")
  local kit = require("kit")
  local P = require("themes.layouts.page")
  local tab = morf.signal("spec.tab", 1)
  local choice = morf.signal("spec.choice", 2)
  local draft = morf.signal("spec.draft", "hello")
  local busy = morf.signal("spec.busy", false)
  local rows = morf.signal("spec.rows", { "one", "two" })
  local function build(w, h)
      local node = controls.pages {
        id = "spec", width = w, height = h, tab = tab,
        tabs = {
          { key = "first", name = "First", icon = "alarm", build = function(pw, ph)
            return ui.Column {
              width = pw, gap = 8,
              controls.segments { id = "spec-choice", width = pw, items = { "A", "B", "C" },
                current = function() return choice:get() end, on_changed = function(index) choice:set(index) end },
              controls.entry { id = "spec-entry", width = pw, value = draft, placeholder = "Say" },
              controls.note { id = "spec-note", width = pw, text = function() return draft:get() end },
            }
          end },
          { key = "second", name = "Second", icon = "timer", build = function(pw, ph)
            return controls.list {
              id = "spec-list", width = pw, height = ph, count = 4, items = function() return rows:get() end,
              build = function(index, item)
                return kit.text { id = "spec-row-text-" .. index, text = function() return item() or "" end }
              end,
            }
          end },
          { key = "third", name = "Third", icon = "public", build = function(pw, ph)
            return controls.cards({ id = "spec", width = pw, height = ph, busy = function() return busy:get() end }, function()
              return ui.Column { width = pw, gap = 12,
                P.section { id = "spec-card-1", width = pw, title = "One", kit.text { text = "a" } },
                P.section { id = "spec-card-2", width = pw, title = "Two", kit.text { text = "b" } },
              }
            end)
          end },
        },
      }
      return node
  end
  -- As a page of the Tools window holds it.
  ui.Rect { anchors = { fill = true }, color = function() return require("theme").color.surface end,
    ui.Item { width = 608, height = 600, build(function() return 608 end, function() return 600 end) } }
  morf.ipc.tab = function(index) tab:set(tonumber(index)) return true end
  morf.ipc.draft = function(text) draft:set(text) return true end
  morf.ipc.choice = function() return choice:get() end
  morf.ipc.rows = function(n)
    local list = {}
    for i = 1, tonumber(n) do list[i] = "row " .. i end
    rows:set(list)
    return true
  end
  morf.ipc.busy = function(on) busy:set(on == "on") return true end
  morf.ipc.dry = function() return sys.dry() end
  morf.ipc.state_path = function() return sys.state("x", "y.json") end
  morf.ipc.saved = function()
    sys.save(sys.state("x", "y.json"), { a = 1 })
    return sys.load(sys.state("x", "y.json"), {}).a
  end
  morf.ipc.missing = function() return sys.load(sys.state("x", "none.json"), { b = 2 }).b end
  morf.ipc.run = function()
    local seen
    sys.run({ "rm", "-rf", "/nowhere" }, {}, function(result) seen = result.dry end)
    return seen
  end
  morf.ipc.has = function(name) return sys.has(name) end
  morf.ipc.compositor = function() return sys.compositor() end
]]

local function tool(style, name)
  local state = morf.env("XDG_STATE_HOME") .. "/controls-" .. name
  morf.fs.mkdir(state)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
  test.load("../shell/init.lua", { source = TOOL, env = { EVA_DRY_RUN = "1", XDG_STATE_HOME = state, EVA_STYLE = style,
    EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_APPEARANCE = appearance } })
  test.settle(500)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("slides its pages on a spring in " .. style, function()
    tool(style, "pages-" .. style)
    local start = test.get({ id = "spec-pages" }).x
    local width = test.get({ id = "spec-paged" }).width
    test.ipc("tab", "2")
    test.advance(48)
    local moving = test.get({ id = "spec-pages" }).x
    test.truthy(moving < start and moving > start - width)
    test.settle(1500)
    test.truthy(math.abs(test.get({ id = "spec-pages" }).x - (start - width)) < 1)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("shows as many rows as there are in " .. style, function()
    tool(style, "rows-" .. style)
    test.ipc("tab", "2")
    test.settle(800)
    test.eq(test.get({ id = "spec-row-text-2" }).text, "two")
    test.ipc("rows", "3")
    test.settle(200)
    test.eq(test.get({ id = "spec-row-text-3" }).text, "row 3")
    test.falsy(test.get({ id = "spec-list-row-4" }).visible)
  end)

  test.it("keeps a choice and a line in " .. style, function()
    tool(style, "choice-" .. style)
    test.eq(test.ipc("choice"), 2)
    test.eq(test.get({ id = "spec-note" }).text, "hello")
    test.ipc("draft", "changed")
    test.settle(100)
    test.eq(test.get({ id = "spec-note" }).text, "changed")
  end)

  test.it("makes its cards one field in " .. style, function()
    tool(style, "cards-" .. style)
    test.truthy(test.find { id = "spec-cards" })
    test.truthy(test.find { id = "spec-card-1-card" })
    test.ipc("busy", "on")
    test.settle(400)
    test.ipc("busy", "off")
    test.settle(400)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("holds back a machine action when dry, and reads when asked", function()
  tool("material", "sys")
  test.truthy(test.ipc("dry"))
  test.truthy(test.ipc("run"))
  test.falsy(test.ipc("has", "no-such-program-here"))
end)

test.it("keeps a file in eva's state folder, private", function()
  tool("material", "files")
  test.eq(test.ipc("saved"), 1)
  test.eq(test.ipc("missing"), 2)
  test.contains(test.ipc("state_path"), "/eva/x/y.json")
  test.eq((morf.fs.stat(test.ipc("state_path")).mode or 0) & 63, 0)
end)
