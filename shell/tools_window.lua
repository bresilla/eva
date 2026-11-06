-- The Tools window: every tool of shell/tools_registry.lua, a page each, in one
-- shell surface over everything (shell/window_host.lua), the way Settings is.
-- Its state and pages are shell/tools_model.lua's.
return require("window_host").new(require("tools_model"))
