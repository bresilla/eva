-- eva-disk's window: a folder as a treemap, its boxes layers of one distance field
-- that run together on the theme's seam and springs as they change, breadcrumbs
-- back up, and each mount's use.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local fit = require("themes.layouts.fit")
local controls = require("common.controls")
local model = require("model")
local S, C = theme.space, theme.color

local M = {}

local CRUMB_H = 36
local MOUNT_H = 64
local LABEL_W = 56
local LABEL_H = 40
local GUTTER = S.m

local function get(v) if type(v) == "function" then return v() end return v end

local function box_node(index)
  local function item() return model.boxes:get()[index] end
  local function room() local box = item() return box ~= nil and box.w >= LABEL_W and box.h >= LABEL_H end
  local spring = theme.spring.spatial
  return kit.card {
    id = "disk-box-" .. index, radius = kit.round(S.m), clip = true,
    visible = function() return item() ~= nil end,
    x = function() local box = item() return box and box.x or 0 end,
    y = function() local box = item() return box and box.y or 0 end,
    width = function() local box = item() return box and box.w or 0 end,
    height = function() local box = item() return box and box.h or 0 end,
    behavior = { x = spring, y = spring, width = spring, height = spring },
    color = function()
      local box = item()
      if not box then return C.primary:alpha(0) end
      if box.others then return C.onSurface:alpha(0.08) end
      local depth = 0.14 + math.min(0.34, box.share * 0.6)
      return (box.dir and C.primary or C.tertiary):alpha(depth)
    end,
    kit.action {
      id = "disk-press-" .. index, anchors = { fill = true }, cursor = "pointer",
      accessible_name = "Open", on_clicked = function() model.press(index) end,
      ui.Column {
        x = S.s, y = S.s, gap = S.xxs, visible = room,
        kit.text {
          id = "disk-name-" .. index, font_size = P.SUB, font_weight = 500, color = kit.ink("hi"), elide = "right",
          width = function() local box = item() return math.max(1, (box and box.w or 0) - 2 * S.s) end,
          text = function() local box = item() return box and box.name or "" end,
        },
        kit.text {
          id = "disk-size-" .. index, font_size = P.SUB, color = kit.ink("lo"), elide = "right",
          width = function() local box = item() return math.max(1, (box and box.w or 0) - 2 * S.s) end,
          text = function() local box = item() return box and model.size(box.size) or "" end,
        },
      },
    },
  }
end

local function folder_page(w, h)
  local top = CRUMB_H + L.lh(theme.size.small) + S.s
  local function body_h() return math.max(1, get(h) - top) end
  morf.effect("disk.area", function() model.set_area(math.floor(get(w)), math.floor(body_h())) end)
  local function crumbs_w() return math.max(1, get(w) - S.TARGET * 3 - S.s * 3) end
  local function crumbs() return model.tail(model.crumbs(model.path:get()), crumbs_w()) end
  local crumb_bar = kit.widgets.breadcrumbs {
    id = "disk-crumbs", accessible_name = "Path", items = crumbs, item_height = CRUMB_H, gap = S.xxs, height = CRUMB_H,
    width = crumbs_w,
    current = function() return #crumbs() end,
    item_id = function(index) return "disk-crumb-" .. index end,
    on_current_changed = function(index)
      local crumb = crumbs()[index]
      if crumb and crumb.path ~= model.path:get() then model.open(crumb.path) end
    end,
  }
  local field = controls.cards({
    id = "disk", width = w, height = body_h, busy = function() return model.moving:get() end,
  }, function()
    local boxes = { width = w, height = body_h }
    for index = 1, model.BOXES do boxes[index] = box_node(index) end
    return ui.Item(boxes)
  end)
  return ui.Item {
    id = "disk-folder", width = w, height = h,
    ui.Item {
      width = w, height = CRUMB_H,
      ui.Item { width = crumbs_w, height = CRUMB_H, clip = true, crumb_bar },
      ui.Row {
        anchors = { right = true, vertical_center = true }, gap = S.s,
        L.icon_button {
          id = "disk-up", icon = "arrow_upward", name = "Up a folder", width = S.TARGET, height = S.TARGET,
          on_clicked = function() model.up() end,
        },
        L.icon_button {
          id = "disk-refresh", icon = "refresh", name = "Scan again", width = S.TARGET, height = S.TARGET,
          on_clicked = function() model.refresh() end,
        },
        L.icon_button {
          id = "disk-reveal", icon = "folder_open", name = "Open in the file manager", width = S.TARGET, height = S.TARGET,
          on_clicked = function() model.reveal() end,
        },
      },
    },
    ui.Item {
      y = CRUMB_H + S.xs, width = w, height = L.lh(theme.size.small),
      controls.note {
        id = "disk-note", width = w,
        text = function()
          if model.message:get() ~= "" then return model.message:get() end
          local count = #model.entries:get()
          local words = ("%s in %d %s"):format(model.size(model.total:get()), count, count == 1 and "entry" or "entries")
          return model.scanning:get() and ("Scanning, %s so far"):format(words) or words
        end,
      },
    },
    ui.Item {
      y = top, width = w, height = body_h,
      field,
      P.empty {
        id = "disk-empty", icon = "folder_off", title = "Nothing here", width = w,
        text = "This folder is empty, or cannot be read.",
        visible = function() return not model.scanning:get() and #model.entries:get() == 0 end,
      },
    },
  }
end

local function mount_row(index, width)
  local function item() return model.mounts()[index] end
  local meter = width
  return ui.Item {
    id = "disk-mount-" .. index, width = width, height = function() return item() and MOUNT_H or 0 end,
    visible = function() return item() ~= nil end,
    kit.action {
      id = "disk-mount-press-" .. index, width = width, height = MOUNT_H, cursor = "pointer",
      on_clicked = function()
        local mount = item()
        if not mount then return end
        model.tab:set(1)
        model.open(mount.mount)
      end,
      ui.Column {
        width = width, gap = S.xs, anchors = { vertical_center = true },
        ui.Item {
          width = width, height = L.lh(theme.size.normal),
          kit.text {
            id = "disk-mount-name-" .. index, width = width * 0.5, elide = "right", font_size = theme.size.normal, font_weight = 500,
            color = kit.ink("hi"), text = function() local mount = item() return mount and mount.mount or "" end,
          },
          kit.text {
            id = "disk-mount-use-" .. index, anchors = { right = true }, width = width * 0.5, elide = "left",
            horizontal_alignment = "right", font_size = P.SUB, color = kit.ink("lo"),
            text = function()
              local mount = item()
              if not mount then return "" end
              return ("%s of %s, %s"):format(model.size(mount.used), model.size(mount.total), mount.type)
            end,
          },
        },
        kit.meter {
          width = meter, height = S.s,
          value = function() local mount = item() return mount and mount.percent / 100 or 0 end,
          color = kit.level(function() local mount = item() return mount and mount.percent or 0 end),
        },
      },
    },
  }
end

local function mounts_body(whole, h)
  local width = whole - GUTTER
  local inner = width - 2 * P.PAD
  local rows = { width = inner, gap = S.xs }
  for index = 1, 16 do rows[index] = mount_row(index, inner) end
  return (kit.scroll {
    id = "disk-mounts-scroll", width = whole, height = h, clip = true,
    P.section { id = "disk-mounts", title = "Mounts", width = width, ui.Column(rows) },
  })
end

local function mounts_page(w, h)
  return fit.width { id = "disk-mounts-page", width = w, height = h, build = function(width) return mounts_body(width, h) end }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local top = S.TARGET + S.s
  local function body_h() return math.max(1, h() - top) end
  local go = 96
  return ui.Item {
    id = "disk-root", width = w, height = h,
    ui.Row {
      gap = S.s, align = "center",
      controls.entry {
        id = "disk-path", width = function() return math.max(1, w() - go - S.s) end, value = model.draft,
        placeholder = "A folder", on_accepted = function(value) model.open(value) end,
      },
      P.button { id = "disk-go", label = "Scan", width = go, tone = "primary", on_clicked = function() model.open(model.draft:get()) end },
    },
    ui.Item {
      y = top, width = w, height = body_h,
      (controls.pages {
        id = "disk", width = w, height = body_h, tab = model.tab,
        tabs = {
          { key = "folder", name = "Folder", icon = "folder", build = folder_page },
          { key = "mounts", name = "Mounts", icon = "hard_drive", build = mounts_page },
        },
      }),
    },
  }
end

return M
