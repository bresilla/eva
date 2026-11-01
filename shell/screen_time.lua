-- Screen time on screen: the warning over everything. The counting and the rules
-- are shell/screen_time_model.lua's.
local model = require("screen_time_model")
local M = setmetatable({}, { __index = model })

M.node = require("themes").view("screen_time_notice").build(model)

return M
