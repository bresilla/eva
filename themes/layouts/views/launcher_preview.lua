-- Quick look: what the chosen result holds, in a pane beside the list where there
-- is room and over it where there is not. A picture is prepared off the loop, a
-- file read off it, and a command's output arrives when it does; what the pane
-- shows belongs to the newest row.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local C = theme.color
local S = theme.space
local V = {}

local READ_LIMIT = 64 * 1024
local SHOWN_BYTES = 8 * 1024

local function plain(text)
  if not text or text:find("\0", 1, true) then return nil end
  return text:sub(1, SHOWN_BYTES)
end

local function size_of(bytes)
  for _, unit in ipairs { { 1 << 30, "GiB" }, { 1 << 20, "MiB" }, { 1 << 10, "KiB" } } do
    if bytes >= unit[1] then return ("%.1f %s"):format(bytes / unit[1], unit[2]) end
  end
  return bytes .. " bytes"
end

local function details(path)
  local ok, stat = pcall(morf.fs.stat, path)
  if not ok or type(stat) ~= "table" then return "" end
  local words = {}
  if stat.size then words[#words + 1] = size_of(stat.size) end
  if stat.modified then words[#words + 1] = morf.time.format("%-d %b %Y, %H:%M", stat.modified) end
  return table.concat(words, "  ·  ")
end

--- The pane, `width` by `height` (fns).
function V.build(M, width, height)
  local state = morf.state { title = "", note = "", text = "", image = "" }
  local generation = 0
  local preview

  local function clear_image()
    if preview then pcall(preview.close) preview = nil end
    state.image = ""
  end

  local function show_image(path, serial)
    clear_image()
    if path:lower():match("%.svg$") then state.image = path return end
    local ok, opened = pcall(morf.image.preview, path)
    if not ok or not opened then return end
    preview = opened
    local side = math.max(64, math.floor(width() - 2 * S.m))
    local scale = math.floor(((morf.screens[1] or {}).density_scale or 1) * 120 + 0.5)
    pcall(preview.cover, side, side, scale, function(done, result)
      if done and serial == generation then state.image = result.path end
    end)
  end

  local function show_folder(path)
    local ok, entries = pcall(morf.fs.list, path)
    local names = {}
    for i, e in ipairs(ok and type(entries) == "table" and entries or {}) do
      if i > 80 then break end
      names[#names + 1] = (e.is_dir and "▸ " or "  ") .. (e.name or "")
    end
    table.sort(names)
    state.text = table.concat(names, "\n")
  end

  local function show_file(path, serial)
    if not morf.fs.is_file(path) then return end
    morf.fs.read_async({ path }, function(_, contents)
      if serial ~= generation then return end
      local text = type(contents) == "table" and contents[1] or nil
      local shown = type(text) == "string" and plain(text) or nil
      state.text = shown or ""
      if not shown then state.note = state.note .. "  ·  no preview" end
    end, READ_LIMIT)
  end

  local function show_command(preview_spec, serial)
    state.text = "…"
    morf.process.run(preview_spec.command, { env = preview_spec.env, timeout_ms = 5000 }, function(result)
      if serial ~= generation then return end
      state.text = plain(tostring(result and result.stdout or "")) or ""
    end)
  end

  local function show(row)
    generation = generation + 1
    local serial = generation
    clear_image()
    state.text, state.note = "", ""
    if not row then return end
    local spec = row.preview
    state.title = spec.title or tostring(row.name or "")
    if spec.svg then state.image = spec.svg
    elseif spec.text then state.text = spec.text
    elseif spec.command then show_command(spec, serial)
    elseif spec.path then
      state.note = details(spec.path)
      if spec.folder then show_folder(spec.path)
      elseif require("lib.shell.launcher.rows").is_image(spec.path) then show_image(spec.path, serial)
      else show_file(spec.path, serial) end
    end
  end

  local showing
  morf.effect("eva.launcher.preview.follow", function()
    local row = M.previewed()
    if row == showing then return end
    showing = row
    show(row)
  end)

  local picture = ui.Image {
    id = "launcher-preview-image", width = function() return width() - 2 * S.m end,
    height = function() return math.min(width() - 2 * S.m, height() - V.HEAD) end,
    fill_mode = "preserve_aspect_fit", source = function() return state.image end,
    visible = function() return state.image ~= "" end,
  }
  local words = kit.text {
    id = "launcher-preview-text", width = function() return width() - 2 * S.m end, wrap = true,
    font_size = theme.size.small, font_family = theme.mono or theme.font,
    color = function() return C.onSurface end, text = function() return state.text end,
    visible = function() return state.image == "" and state.text ~= "" end,
  }
  return kit.surface {
    id = "launcher-preview", width = width, height = height, radius = kit.round(14), clip = true,
    color = function() return C.surfaceContainer end,
    ui.Column { x = S.m, y = S.m, gap = S.s,
      kit.text { id = "launcher-preview-title", width = function() return width() - 2 * S.m end, elide = "right",
        font_size = theme.size.normal, font_weight = 600, color = function() return C.onSurface end,
        text = function() return state.title end },
      kit.text { width = function() return width() - 2 * S.m end, elide = "right", font_size = theme.size.smaller,
        color = function() return C.onSurfaceVariant end, text = function() return state.note end,
        visible = function() return state.note ~= "" end },
      picture, words,
    },
  }
end

V.HEAD = 64

--- The words the launcher shows large, over its whole panel.
function V.large(M, width, height)
  return ui.Item {
    id = "launcher-large", width = width, height = height, visible = function() return M.large_type:get() ~= "" end,
    z = 10,
    ui.Rect { anchors = { fill = true }, radius = kit.round(16), color = function() return C.surfaceContainerHighest end },
    ui.MouseArea { anchors = { fill = true }, on_clicked = function() M.large_type:set("") end },
    kit.text {
      id = "launcher-large-text", anchors = { center_in = true }, width = function() return width() - 2 * S.xl end,
      wrap = true, horizontal_alignment = "center", font_weight = 700, color = function() return C.onSurface end,
      font_size = function()
        local length = utf8.len(M.large_type:get()) or #M.large_type:get()
        return math.max(28, math.min(96, math.floor(width() / math.max(length, 1) * 1.6)))
      end,
      text = function() return M.large_type:get() end,
    },
  }
end

return V
