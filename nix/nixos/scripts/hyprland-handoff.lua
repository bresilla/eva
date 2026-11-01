-- What the greeter's compositor and the session's agree on: the colour behind
-- everything, and each output as the session left it. Loaded after
-- hyprland-scale.lua, whose hl.monitor keeps the rules these set.
local M = {}

--- `rgb(rrggbb)` from the file `path` holding `#rrggbb`, else `fallback`.
function M.background(path, fallback)
    local file = io.open(path, "r")
    if not file then return fallback end
    local hex = (file:read("*l") or ""):match("^#(%x%x%x%x%x%x)%s*$")
    file:close()
    return hex and ("rgb(" .. hex:lower() .. ")") or fallback
end

-- One output a line, tab separated: key, mode, position, scale, transform.
local function parse(line)
    local key, mode, position, scale, transform =
        line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
    if not key or key:find("%c") then return nil end
    if not (key:match("^desc:.+") or key:match("^[%w_.%-]+$")) then return nil end
    if not mode:match("^%d+x%d+@%d+%.?%d*$") or not position:match("^%-?%d+x%-?%d+$") then return nil end
    scale, transform = tonumber(scale), tonumber(transform)
    if not scale or scale < .25 or scale > 8 then return nil end
    if not transform or transform < 0 or transform > 7 or transform % 1 ~= 0 then return nil end
    return { output = key, mode = mode, position = position, scale = scale, transform = math.floor(transform) }
end

--- The lines for `monitors`. Outputs sharing a description are keyed on their
--- connectors.
local function describe(monitors)
    local seen = {}
    for _, screen in ipairs(monitors) do
        if screen.description ~= "" then seen[screen.description] = (seen[screen.description] or 0) + 1 end
    end
    local lines = {}
    for _, screen in ipairs(monitors) do
        if not screen.is_mirror then
            local key = seen[screen.description] == 1 and "desc:" .. screen.description or screen.name
            lines[#lines + 1] = ("%s\t%dx%d@%.3f\t%dx%d\t%.6f\t%d"):format(key, screen.width, screen.height,
                screen.refresh_rate, screen.x, screen.y, screen.scale, screen.transform)
        end
    end
    return lines
end

--- Sets a monitor rule for every valid line of `path`.
function M.adopt(path)
    local file = io.open(path, "r")
    if not file then return end
    for line in file:lines() do
        local rule = parse(line)
        if rule then hl.monitor(rule) end
    end
    file:close()
end

--- Keeps `path` up to date with the outputs, once they have settled.
function M.record(path)
    local pending
    local function save()
        local lines = describe(hl.get_monitors())
        if #lines == 0 then return end
        local fresh = path .. ".new"
        local file = io.open(fresh, "w")
        if not file then return end
        file:write(table.concat(lines, "\n"), "\n")
        file:close()
        os.rename(fresh, path)
    end
    local function soon()
        if pending and pending:is_enabled() then pending:set_enabled(false) end
        -- Later than hyprland-scale.lua's 400 ms timer.
        pending = hl.timer(save, { timeout = 800, type = "oneshot" })
    end
    for _, event in ipairs { "hyprland.start", "monitor.added", "monitor.layout_changed" } do
        hl.on(event, soon)
    end
end

--- Creates the file `path` when the layer `namespace` first maps.
function M.announce(namespace, path)
    local told = false
    hl.on("layer.opened", function(layer)
        if told or layer.namespace ~= namespace then return end
        told = true
        local file = io.open(path, "w")
        if file then file:close() end
    end)
end

return M
