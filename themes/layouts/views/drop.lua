-- The Drop page (https://github.com/termworks/drop), in the page template
-- (themes/layouts/page.lua): this machine and whether `drop serve` runs, the
-- people and machines it knows, what one of them offers, and what is on its
-- way. Files dropped on a row go there; dropped on the page, to the row on
-- show, or to the next one pressed.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local widgets = require("planner_widgets")
local C = theme.color
local S = theme.space
local M = {}

local WIDE = 900

local function get(v) if type(v) == "function" then return v() end return v end
local function safe(id) return tostring(id):gsub("[^%w]", "-") end

function M.build(model, active, w, h)
  local function ready() return model.stage() == "ready" end
  local function wide() return get(w) >= WIDE end
  local function pane_w() return wide() and (get(w) - P.GAP) // 2 or get(w) end
  local function inner() return P.inner(pane_w()) end
  local stamp = tostring({})
  local hovering = morf.signal("eva.drop.hovering." .. stamp, "")
  local adding_kind = morf.signal("eva.drop.kind." .. stamp, "folder")
  local adding_level = morf.signal("eva.drop.level." .. stamp, "me")
  local function serving() return model.serving:get() == "yes" end

  -- A row that takes files: a drop on it sends them there.
  local function droppable(row_node, id, on_paths)
    return ui.Item { width = inner, height = function() return row_node.height end, row_node,
      ui.DropArea { id = "drop-target-" .. id, anchors = { fill = true }, keys = { "files" },
        on_entered = function() hovering:set(id) end,
        on_exited = function() if hovering:get() == id then hovering:set("") end end,
        on_dropped = function(drop) on_paths(drop.paths) end } }
  end

  -- ------------------------------------------------------------ this machine --
  local status = P.section { id = "drop-status", width = pane_w, title = "This machine",
    P.row { id = "drop-identity", width = inner, icon = "fingerprint",
      title = function() local id = model.identity:get() return id ~= "" and id or "Reading…" end,
      subtitle = "Your identity on drop" },
    P.row { id = "drop-serve", width = inner, icon = "cell_tower", on = serving,
      title = function()
        local state = model.serving:get()
        if state == "yes" then return "drop serve is running" end
        if state == "no" then return "drop serve is not running" end
        return "Checking drop serve"
      end,
      subtitle = function()
        return serving() and "Reachable: people can send to this machine"
          or "Nothing can reach this machine until it runs"
      end,
      trailing = P.button { id = "drop-start-serve", label = "Start", icon = "play_arrow", tone = "primary",
        visible = function() return model.serving:get() == "no" end, on_clicked = model.start_serve } },
  }

  -- --------------------------------------------------------- people, machines --
  local targets = ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner, model = model.targets,
    delegate = function(row)
      local id = safe(row.id)
      local node = P.row { id = "drop-person-" .. id, width = inner,
        icon = function()
          local reach = model.reachable(row.id)
          return reach == "yes" and "link" or reach == "no" and "link_off" or "person"
        end,
        on = function() return model.selected:get() == row.id or hovering:get() == id end,
        title = row.title,
        subtitle = function()
          local reach = model.reachable(row.id)
          local words = reach == "yes" and "Reachable" or reach == "no" and "Not reachable"
            or reach == "checking" and "Checking…" or nil
          return row.detail .. (words and (" · " .. words) or "")
        end,
        on_clicked = function() model.select(row.id) end }
      return droppable(node, id, function(paths)
        model.select(row.id)
        model.send(paths)
      end)
    end }
  local nobody = kit.text { id = "drop-nobody", width = inner, wrap = true, font_size = P.SUB, color = kit.ink("lo"),
    text = "Nobody yet. Pair somebody nearby, or trade a code.",
    visible = function() return model.loaded:get() and model.targets:len() == 0 end }
  local code_node, code_input = widgets.field("drop-take-code", "Their code", "A code somebody shows you", inner, nil,
    function(text) if model.take_code(text) then code_input.text = "" end end)
  local people = P.section { id = "drop-people", width = pane_w, title = "People and machines",
    note = function() return tostring(model.targets:len()) end,
    targets, nobody,
    kit.text { id = "drop-my-code", width = inner, font_family = theme.mono, font_size = L.SIZE.title,
      color = function() return C.primary end, text = function() return model.code:get() end,
      visible = function() return model.code:get() ~= "" end },
    P.buttons { id = "drop-people-buttons", width = inner,
      { id = "drop-check", label = "Check who answers", icon = "wifi_find", enabled = serving, on_clicked = model.check_all },
      { id = "drop-offer", label = function() return model.code:get() ~= "" and "Stop" or "Show my code" end, icon = "qr_code",
        on_clicked = function() if model.code:get() ~= "" then model.stop_offer() else model.offer_code() end end },
    },
    code_node,
  }

  -- ------------------------------------------------------------------ nearby --
  local asking = ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner, model = model.asking,
    delegate = function(row)
      return P.row { id = "drop-ask-" .. safe(row.id), width = inner, icon = "contact_page", title = row.name,
        subtitle = "Asks " .. row.says .. " · number " .. row.check,
        trailing = ui.Row { gap = S.xs,
          P.button { id = "drop-ask-yes-" .. safe(row.id), label = "Yes", tone = "primary",
            on_clicked = function() model.decide(row.name, true) end },
          P.button { id = "drop-ask-no-" .. safe(row.id), label = "No", on_clicked = function() model.decide(row.name, false) end } } }
    end }
  local devices = ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner, model = model.nearby,
    delegate = function(row)
      return P.row { id = "drop-near-" .. safe(row.id), width = inner, icon = "devices", title = row.name,
        subtitle = row.id:sub(-12),
        trailing = P.button { id = "drop-pair-" .. safe(row.id), label = "Pair", on_clicked = function() model.pair(row.name) end } }
    end }
  local nearby = P.section { id = "drop-nearby", width = pane_w, title = "Nearby",
    asking, devices,
    kit.text { id = "drop-nearby-empty", width = inner, wrap = true, font_size = P.SUB, color = kit.ink("lo"),
      text = function()
        return serving() and "Nothing on this network that is not already yours or paired."
          or "drop serve hears what is nearby: start it to look."
      end,
      visible = function() return model.nearby:len() == 0 and model.asking:len() == 0 end },
  }

  -- ------------------------------------------------------------- a target --
  local remote = ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner, model = model.remote,
    delegate = function(row)
      return P.row { id = "drop-topic-" .. safe(row.id), width = inner,
        icon = row.kind == "folder" and "folder" or row.kind == "chat" and "chat" or row.kind == "inbox" and "inbox" or "topic",
        title = row.path, subtitle = row.kind .. (row.about ~= "" and (" · " .. row.about) or ""),
        trailing = row.kind == "folder" and P.chevron() or nil,
        on_clicked = row.kind == "folder" and function() model.browse(row.path) end or nil }
    end }
  local files = ui.Repeater { as = "column", gap = S.xs, width = inner, model = model.files,
    delegate = function(row)
      return P.row { id = "drop-file-" .. safe(row.id), width = inner, height = 48,
        icon = row.folder and "folder" or "draft", title = row.name,
        subtitle = row.folder and row.when or (row.size .. " · " .. row.when),
        trailing = row.folder and P.chevron() or kit.icon("download", 20, kit.ink("lo")),
        on_clicked = function() model.open_file(row) end }
    end }
  local log = ui.Repeater { as = "column", gap = S.xs, width = inner, model = model.log,
    delegate = function(row)
      return kit.text { text = row.text, width = inner, wrap = true, font_size = P.SUB, font_family = theme.mono,
        color = kit.ink("hi") }
    end }
  local say_node, say_input = widgets.field("drop-say", "Say something", "A message; one for an offline machine waits for it", inner, nil,
    function(text) if model.message(text) then say_input.text = "" end end)
  local path_node, path_input = widgets.field("drop-path", "Or a path", "~/report.pdf", inner, nil,
    function(text) if model.send { text } then path_input.text = "" end end)

  local chooser, chooser_open = nil, morf.signal("eva.drop.chooser." .. stamp, false)
  local function chooser_node()
    if chooser then return chooser end
    chooser = require("themes.kit.composites").file_chooser { id = "drop-chooser", width = inner, height = 360, mode = "open",
      path = "~", on_accepted = function(path)
        chooser_open:set(false)
        model.send { path }
      end, on_cancelled = function() chooser_open:set(false) end }
    return chooser
  end
  local chooser_box = ui.Item { width = inner, height = function() return chooser_open:get() and 360 or 0 end,
    visible = function() return chooser_open:get() end, clip = true }
  morf.effect("drop.chooser", function()
    if chooser_open:get() and not chooser then ui.reparent(chooser_node(), chooser_box) end
  end, { owner = chooser_box })

  local selected = P.section { id = "drop-selected", width = pane_w,
    title = function() local t = model.target() return t and (t.title .. " · " .. t.detail) or "Choose somebody" end,
    visible = function() return model.target() ~= nil end,
    P.row { id = "drop-reach", width = inner, icon = "link",
      on = function() local t = model.target() return t ~= nil and model.reachable(t.id) == "yes" end,
      title = function()
        local t = model.target()
        local reach = t and model.reachable(t.id)
        if reach == "yes" then return "Reachable" end
        if reach == "no" then return "Not reachable now" end
        return "Checking…"
      end,
      subtitle = "A message for a machine that is off waits for it" },
    remote,
    kit.text { id = "drop-folder", width = inner, font_size = P.SUB, color = kit.ink("lo"), elide = "right",
      text = function() return model.folder:get() end, visible = function() return model.folder:get() ~= "" end },
    P.button { id = "drop-up", label = "Up", icon = "arrow_upward", visible = function() return model.folder:get() ~= "" end,
      on_clicked = model.up },
    files,
    P.row { id = "drop-send-here", width = inner, icon = "upload_file", title = "Drop a file on this page to send it",
      on = function() return hovering:get() == "page" end,
      trailing = P.button { id = "drop-choose", label = "Choose", icon = "folder_open",
        on_clicked = function() chooser_open:set(not chooser_open:get()) end } },
    chooser_box,
    path_node,
    log, say_node,
  }

  local pending = P.section { id = "drop-pending", width = pane_w, title = "Waiting to be sent",
    visible = function() return model.pending:get() ~= "" end,
    P.row { id = "drop-pending-row", width = inner, icon = "outbox", title = function() return model.pending:get() end,
      subtitle = "Press somebody to send it to them",
      trailing = P.button { id = "drop-pending-cancel", label = "Cancel", on_clicked = model.cancel_pending } },
  }

  local transfers = P.section { id = "drop-transfers", width = pane_w, title = "On its way",
    visible = function() return model.transfers:len() > 0 end,
    ui.Repeater { as = "column", gap = S.xs, width = inner, model = model.transfers,
      delegate = function(row)
        local title = kit.text { text = row.name, font_size = theme.size.normal, width = inner, elide = "right", color = kit.ink("hi") }
        local detail = kit.text { text = row.to .. " · " .. row.state, font_size = P.SUB, width = inner, elide = "right", color = kit.ink("lo") }
        return ui.Column { id = "drop-transfer-" .. row.id, width = inner, gap = S.xxs, title, detail },
          function(next) detail.text = next.to .. " · " .. next.state end
      end },
  }

  local received = P.section { id = "drop-received", width = pane_w, title = "Received",
    visible = function() return model.received:len() > 0 end,
    ui.Repeater { as = "column", gap = S.xs, width = inner, model = model.received,
      delegate = function(row)
        return ui.MouseArea { id = "drop-received-" .. safe(row.id), width = inner, height = 48, cursor = "grab",
          on_pressed = function() morf.drag.start { paths = { row.path } } end,
          P.row { width = inner, height = 48, icon = "draft", title = row.name, subtitle = row.when } }
      end },
  }

  -- ------------------------------------------------------------------ topics --
  local topic_rows = ui.Repeater { as = "column", gap = S.xs, width = inner, model = model.topics,
    delegate = function(row)
      return P.row { id = "drop-mine-" .. safe(row.id), width = inner, height = 48, icon = "topic", title = row.path,
        subtitle = row.kind .. " · open to " .. row.access,
        trailing = kit.action { id = "drop-mine-rm-" .. safe(row.id), width = 32, height = 32, cursor = "pointer",
          accessible_name = "Remove " .. row.path, on_clicked = function() model.remove_topic(row.path) end,
          kit.icon("close", 18, kit.ink("lo"), { anchors = { center_in = true } }) } }
    end }
  local kinds = { id = "drop-kinds", width = inner }
  for _, kind in ipairs { "chat", "inbox", "folder", "note" } do
    kinds[#kinds + 1] = { id = "drop-kind-" .. kind, label = kind, group = "drop-kind",
      selected = function() return adding_kind:get() == kind end, on_clicked = function() adding_kind:set(kind) end }
  end
  local levels = { id = "drop-levels", width = inner }
  for _, level in ipairs(model.LEVELS) do
    levels[#levels + 1] = { id = "drop-level-" .. level, label = level, group = "drop-level",
      selected = function() return adding_level:get() == level end, on_clicked = function() adding_level:set(level) end }
  end
  local topic_node, topic_input = widgets.field("drop-topic-name", "Add a topic", "A name", inner, nil, function(text)
    if model.add_topic(text, adding_kind:get(), adding_level:get()) then topic_input.text = "" end
  end)
  local topics = P.section { id = "drop-topics", width = pane_w, title = "What this machine offers",
    note = function() return tostring(model.topics:len()) end,
    topic_rows, topic_node, P.buttons(kinds), P.buttons(levels) }

  local said = kit.text { id = "drop-said", width = pane_w, wrap = true, font_size = P.SUB, color = kit.ink("lo"),
    text = function() return model.said:get() end, visible = function() return model.said:get() ~= "" end }

  -- ------------------------------------------------------------------ the page --
  local left = ui.Column { width = pane_w, gap = P.GAP, status, people, nearby, topics, ui.Item { width = 1, height = P.GAP } }
  local right = ui.Column { width = pane_w, gap = P.GAP, said, pending, selected, transfers, received }
  local columns = ui.Item { width = w,
    height = function()
      if wide() then return math.max(left.layout_height or 0, right.layout_height or 0) end
      return (right.layout_height or 0) + (left.layout_height or 0) + P.GAP
    end,
    ui.Item { width = pane_w, y = function() return wide() and 0 or (right.layout_height or 0) + P.GAP end, left },
    ui.Item { width = pane_w, x = function() return wide() and pane_w() + P.GAP or 0 end, right },
  }
  local body = kit.scroll { id = "drop-scroll", width = w, height = h, clip = true,
    visible = ready, columns }

  local gate = ui.Item { width = w, height = h, visible = function() return not ready() end,
    P.empty { id = "drop-placeholder", width = w, icon = "forum",
      title = function()
        return model.stage() == "missing" and "drop is not installed" or "Drop has no identity on this machine"
      end,
      text = function()
        if model.stage() == "missing" then return "Files, chat and folders with your people and machines, peer to peer. Install drop to use this page." end
        return "Setting up makes this machine's own key, the first time anything runs. Nothing has run yet."
      end,
      action = { id = "drop-set-up", label = "Set up Drop", icon = "key", tone = "primary",
        visible = function() return model.stage() == "first-run" end, on_clicked = model.set_up } } }

  local target = ui.DropArea { id = "drop-page-target", anchors = { fill = true }, keys = { "files" },
    on_entered = function() hovering:set("page") end,
    on_exited = function() if hovering:get() == "page" then hovering:set("") end end,
    on_dropped = function(drop) model.send(drop.paths) end }

  return ui.Item { id = "drop-page", width = w, height = h, target, gate, body }
end
return M
