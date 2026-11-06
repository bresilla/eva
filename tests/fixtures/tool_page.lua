-- A host for one tool's page alone, as the Tools window shows it, for the specs:
-- the page of the tool EVA_TEST_TOOL names, EVA_TEST_PAGE ("WxH", 600x660 by
-- default) in size, its words (`eva-disk FOLDER`) from the arguments, and its
-- verbs as this configuration's own. Load it as the source of shell/init.lua.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")

local name = morf.env("EVA_TEST_TOOL")
local w, h = (morf.env("EVA_TEST_PAGE") or "600x660"):match("(%d+)x(%d+)")
w, h = tonumber(w), tonumber(h)
morf.surface.blend = "srgb"
require("themes.ui_scale").apply()
require("apps.common.frame").follow_scheme()

local registry = require("tools_registry")
local entry = registry.BY_KEY[name]
local module = entry and entry.page or ("apps." .. name .. ".page")
local page = require(module)
if page.open and #(morf.args or {}) > 0 then page.open(morf.args) end
ui.Rect { id = "tool-page-root", anchors = { fill = true }, color = function() return theme.color.surface end,
  ui.Item { id = "tool-page", width = w, height = h, page.build(w, h) },
  page.actions and ui.Item { id = "tool-page-actions", x = w, page.actions() } or nil }
if page.shown then page.shown(true) end
for verb, handler in pairs(page.verbs or {}) do morf.ipc[verb] = handler end
