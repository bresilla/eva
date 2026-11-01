-- eva-monitor's window: the processes, the machine's resources, its sensors.
-- The rows are the engine's list view, a pool rebound as it scrolls.
local morf = require("morf")
local ui = require("morf.ui")
local unicase = require("lib.util.unicase")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local fit = require("themes.layouts.fit")
local controls = require("common.controls")
local model = require("model")
local S, C = theme.space, theme.color

local M = {}

local ROW_H = 56
local CPU_W = 68
local MEMORY_W = 88
local PID_W = 88
local WIDE = fit.WIDE
local MEDIUM = 600
local CHART_H = 96
local CORE_MAX = 16
local CORE_H = 56
local TILE_H = 70
local DEVICE_H = 52
local SENSOR_H = 48
-- Room a page leaves its scroll bar.
local GUTTER = S.m
local STATES = { R = "running", S = "sleeping", D = "in disk wait", Z = "zombie", T = "stopped", t = "traced", I = "idle" }

local function get(v) if type(v) == "function" then return v() end return v end

local function percent(value) return ("%.1f%%"):format(tonumber(value) or 0) end
local function size(value) return model.perf.size(value) end
local function rate(value) return model.perf.rate(value) end

-- -------------------------------------------------------------- processes --

local function process_row(_, s)
  local function row() return s.row() or {} end
  local function wide() return s.width() >= MEDIUM end
  local function right() return CPU_W + MEMORY_W + (wide() and PID_W or 0) + S.m end
  local function text_w() return math.max(1, s.width() - right() - S.s) end
  local index = s.index()
  local node = ui.Item {
    width = function() return s.width() end, height = ROW_H,
    ui.Rect {
      anchors = { fill = true }, radius = kit.round(S.m),
      color = function()
        if s.current() then return C.primary:alpha(0.14) end
        return s.hovered() and C.onSurface:alpha(0.05) or C.onSurface:alpha(0)
      end,
      behavior = { color = { duration = theme.duration.small } },
    },
    ui.Column {
      x = S.s, width = text_w, clip = true, gap = S.xxs, anchors = { vertical_center = true },
      kit.text {
        id = "monitor-name-" .. index, width = text_w, elide = "right", font_size = theme.size.normal, font_weight = 500,
        color = kit.ink("hi"), text = function() return row().name or "" end,
      },
      kit.text {
        id = "monitor-command-" .. index, width = text_w, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
        text = function() return row().command or "" end,
      },
    },
    ui.Row {
      anchors = { right = true, right_margin = S.s, vertical_center = true }, align = "center",
      ui.Column {
        width = CPU_W, gap = S.xs,
        kit.text {
          id = "monitor-cpu-" .. index, width = CPU_W, horizontal_alignment = "right", font_size = theme.size.normal,
          color = kit.ink("hi"), text = function() return percent(row().cpu) end,
        },
        ui.Item {
          width = CPU_W, height = S.xs,
          kit.meter {
            x = S.s, width = CPU_W - S.s, height = S.xs,
            value = function() return math.min(1, (row().cpu or 0) / 100) end,
            color = kit.level(function() return row().cpu or 0 end),
          },
        },
      },
      kit.text {
        id = "monitor-memory-" .. index, width = MEMORY_W, horizontal_alignment = "right", font_size = theme.size.normal,
        color = kit.ink("hi"), text = function() return size(row().memory) end,
      },
      kit.text {
        id = "monitor-pid-" .. index, width = function() return wide() and PID_W or 1 end, horizontal_alignment = "right",
        visible = wide, font_size = theme.size.normal, color = kit.ink("lo"),
        text = function() return tostring(math.floor(row().pid or 0)) end,
      },
    },
  }
  return node, function() end
end

local function fact(id, label, value, w)
  return ui.Item {
    width = w, height = L.lh(P.SUB),
    kit.text { width = function() return get(w) * 0.42 end, elide = "right", font_size = P.SUB, color = kit.ink("lo"), text = label },
    kit.text {
      id = id, anchors = { right = true }, width = function() return get(w) * 0.58 end, elide = "left",
      horizontal_alignment = "right", font_size = P.SUB, font_weight = 500, color = kit.ink("hi"), text = value,
    },
  }
end

local function detail_words(field, format, missing)
  return function()
    local value = model.detail:get()[field]
    if value == nil then return missing or "Not available" end
    return format(value)
  end
end

local function connection_line(index, w)
  local function item()
    local list = model.detail:get().connections or {}
    return list[index]
  end
  return ui.Item {
    width = w, height = function() return item() and L.lh(P.SUB) or 0 end, visible = function() return item() ~= nil end,
    kit.text {
      id = "monitor-connection-" .. index, width = w, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
      text = function()
        local entry = item()
        if not entry then return "" end
        local there = entry.state == "Listening" and "" or (" to " .. entry.there)
        return ("%s %s%s, %s"):format(unicase.upper(entry.protocol), entry.here, there, entry.state)
      end,
    },
  }
end

-- The chosen process in full: its command line, its readings, its signals.
local function detail_card(w, h)
  local function chosen() return model.row_of(model.selected:get()) or {} end
  local function inner() return get(w) - 2 * P.PAD end
  local connections = { width = inner, gap = S.xxs }
  for index = 1, 6 do connections[index] = connection_line(index, inner) end
  return kit.card {
    id = "monitor-detail", width = w, height = h, radius = kit.round(P.RADIUS), clip = true,
    ui.Item {
      x = P.PAD, y = P.PAD, width = inner, height = S.TARGET,
      kit.text {
        id = "monitor-detail-name", width = function() return inner() - S.TARGET - S.s end, elide = "right",
        anchors = { vertical_center = true }, font_size = L.SIZE.title, color = kit.ink("hi"),
        text = function() return chosen().name or "" end,
      },
      ui.Item {
        anchors = { right = true }, width = S.TARGET, height = S.TARGET,
        L.icon_button {
          id = "monitor-detail-close", icon = "close", name = "Close details", width = S.TARGET, height = S.TARGET,
          on_clicked = function() model.select(0) end,
        },
      },
    },
    (kit.scroll {
      id = "monitor-detail-scroll", x = P.PAD, y = P.PAD + S.TARGET + S.s, width = inner, clip = true,
      height = function() return math.max(1, get(h) - 2 * P.PAD - S.TARGET - S.s - P.BUTTON_H - S.m) end,
      ui.Column {
        width = inner, gap = S.s,
        kit.text {
          id = "monitor-detail-command", width = inner, wrap = true, font_size = P.SUB, color = kit.ink("hi"),
          text = function() return chosen().command or "" end,
        },
        L.rule { width = inner, strength = "faint" },
        fact("monitor-detail-user", "User", function() return chosen().user or "" end, inner),
        fact("monitor-detail-pid", "Process", function()
          local state = chosen().state or ""
          return ("%d, %s"):format(math.floor(chosen().pid or 0), STATES[state] or state)
        end, inner),
        fact("monitor-detail-threads", "Threads", detail_words("threads", function(v) return tostring(math.floor(v)) end), inner),
        fact("monitor-detail-cpu", "CPU", function() return percent(chosen().cpu) end, inner),
        fact("monitor-detail-memory", "Memory", function() return size(chosen().memory) end, inner),
        fact("monitor-detail-swap", "Swap", detail_words("swap", size), inner),
        fact("monitor-detail-read", "Disk read", detail_words("read_rate", rate, "Not readable"), inner),
        fact("monitor-detail-write", "Disk write", detail_words("write_rate", rate, "Not readable"), inner),
        fact("monitor-detail-total", "Disk total", function()
          local detail = model.detail:get()
          if not detail.read_total then return "Not readable" end
          return ("%s read, %s written"):format(size(detail.read_total), size(detail.write_total))
        end, inner),
        fact("monitor-detail-gpu", "GPU", function()
          local gpu = model.detail:get().gpu
          if not gpu then return "No GPU client" end
          local memory = gpu.memory > 0 and (", " .. size(gpu.memory)) or ""
          return (gpu.busy and percent(gpu.busy) or gpu.driver) .. memory
        end, inner),
        fact("monitor-detail-connections", "Connections", function()
          local detail = model.detail:get()
          if not detail.sockets then return "Not readable" end
          return ("%d open, %d sockets"):format(#(detail.connections or {}), math.floor(detail.sockets))
        end, inner),
        ui.Column(connections),
      },
    }),
    ui.Item {
      x = P.PAD, y = function() return get(h) - P.PAD - P.BUTTON_H end, width = inner, height = P.BUTTON_H,
      P.buttons {
        width = inner,
        { id = "monitor-term", label = "End", icon = "cancel", tone = "primary",
          on_clicked = function() model.term(model.selected:get()) end },
        { id = "monitor-kill", label = "Force kill", icon = "dangerous", visible = model.may_force,
          color = function() return kit.signal("alert")() end, ink = function() return C.surface end,
          on_clicked = function() model.force(model.selected:get()) end },
      },
    },
  }
end

local function header_label(id, text, width)
  return kit.text { id = id, width = width, horizontal_alignment = "right", font_size = P.SUB, color = kit.ink("lo"), text = text }
end

local function processes_page(w, h)
  local list_node
  local function open() return model.selected:get() ~= 0 end
  local function roomy() return get(w) >= MEDIUM end
  local top = function() return (roomy() and S.TARGET or S.TARGET * 2 + S.s) + L.lh(theme.size.small) + S.s end
  local function body_h() return math.max(1, get(h) - top()) end
  local list_w = fit.beside(w, open)
  local function list_h() return math.max(1, body_h() - L.lh(P.SUB) - S.xs) end
  local function close()
    if not open() then return false end
    model.select(0)
    return true
  end
  list_node = kit.widgets.virtual_list {
    id = "monitor-list", width = list_w, height = list_h, rows = model.rows, row_height = ROW_H,
    delegate = process_row, current = model.selected_index,
    on_current_changed = function(index) model.select_row(index) end,
    on_key_pressed = function(_, _, _, _, key) return key == "Escape" and close() end,
  }
  local sorts = { "CPU", "Memory", "Name", "PID" }
  local entry = kit.text_field("entry", {
    id = "monitor-search", height = S.TARGET, placeholder = "Search name, command, user or PID", focus = true,
    width = function() return roomy() and math.max(1, get(w) * 0.5 - S.s) or get(w) end,
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"),
    text = function() return model.query:get() end,
    on_text_changed = function(value) model.query:set(value) end,
    on_key_pressed = function(_, _, _, _, key)
      if key == "Escape" then return close() end
      if key ~= "Down" then return false end
      morf.focus.set(list_node, true)
      return true
    end,
  })
  local segments = controls.segments {
    id = "monitor-sort", items = sorts, width = function() return roomy() and get(w) * 0.5 or get(w) end,
    current = function()
      for index, key in ipairs(model.SORTS) do if key == model.sort:get() then return index end end
      return 1
    end,
    on_changed = function(index) model.select_sort(model.SORTS[index]) end,
  }
  local segments_box = ui.Item {
    x = function() return roomy() and get(w) * 0.5 or 0 end, y = function() return roomy() and 0 or S.TARGET + S.s end,
    width = function() return roomy() and get(w) * 0.5 or get(w) end, height = S.TARGET, segments,
  }
  local list_top = function() return top() + L.lh(P.SUB) + S.xs end
  return ui.Item {
    id = "monitor-processes", width = w, height = h,
    ui.Item { width = w, height = S.TARGET, entry },
    segments_box,
    ui.Item {
      y = function() return top() - L.lh(theme.size.small) - S.xs end, width = w, height = L.lh(theme.size.small),
      controls.note {
        id = "monitor-note", width = w,
        text = function()
          if model.message:get() ~= "" then return model.message:get() end
          local shown, count = model.shown:get(), model.count:get()
          if model.paused:get() then return ("Paused, %d processes"):format(count) end
          if shown ~= count then return ("%d of %d processes"):format(shown, count) end
          return ("%d processes"):format(count)
        end,
      },
    },
    ui.Item {
      y = top, width = list_w, height = L.lh(P.SUB),
      kit.text { x = S.s, font_size = P.SUB, color = kit.ink("lo"), text = "Process" },
      ui.Row {
        anchors = { right = true, right_margin = S.s },
        header_label("monitor-head-cpu", "CPU", CPU_W),
        header_label("monitor-head-memory", "Memory", MEMORY_W),
        header_label("monitor-head-pid", "PID", function() return list_w() >= MEDIUM and PID_W or 1 end),
      },
    },
    ui.Item {
      y = list_top, width = list_w, height = list_h,
      shortcuts = { Delete = function() model.term(model.selected:get()) return true end },
      list_node,
      P.empty {
        id = "monitor-empty", icon = "search", title = "Nothing matches", width = list_w,
        text = "No process has those words in its name, command, user or number.",
        visible = function() return model.shown:get() == 0 and model.count:get() > 0 end,
      },
    },
    ui.Item {
      y = top, width = w, height = body_h,
      fit.sheet { id = "monitor-sheet", width = w, height = body_h, open = open, build = detail_card },
    },
  }
end

-- -------------------------------------------------------------- resources --

local function tile(id, label, value, width, level, color)
  return kit.stat { id = id, label = label, value = value, width = width, height = TILE_H, level = level, color = color }
end

local function tiles(width)
  local perf = model.perf
  local across = width >= WIDE and 6 or width >= MEDIUM and 3 or 2
  local each = math.floor((width - S.s * (across - 1)) / across)
  local function totals() return model.totals() end
  local grid = { columns = across, gap = S.s, width = width }
  grid[#grid + 1] = tile("monitor-tile-cpu", "CPU", function() return percent(perf.cpu().usage) end, each,
    function() return (perf.cpu().usage or 0) / 100 end, kit.level(function() return perf.cpu().usage or 0 end))
  grid[#grid + 1] = tile("monitor-tile-memory", "Memory", function() return percent(perf.memory().percent) end, each,
    function() return (perf.memory().percent or 0) / 100 end, kit.level(function() return perf.memory().percent or 0 end))
  grid[#grid + 1] = tile("monitor-tile-swap", "Swap", function()
    local swap = perf.memory().swap
    return swap.total > 0 and size(swap.used) or "None"
  end, each, function() local swap = perf.memory().swap return swap.total > 0 and swap.used / swap.total or 0 end)
  grid[#grid + 1] = tile("monitor-tile-gpu", "GPU", function()
    local all = totals()
    if all.cards == 0 then return "None" end
    return all.busy and percent(all.busy) or (all.cards .. " idle")
  end, each, function() return (totals().busy or 0) / 100 end)
  grid[#grid + 1] = tile("monitor-tile-disk", "Disk", function()
    local all = totals()
    return rate(all.read + all.write)
  end, each)
  grid[#grid + 1] = tile("monitor-tile-network", "Network", function()
    local all = totals()
    return rate(all.rx + all.tx)
  end, each)
  return ui.Grid(grid), math.ceil(6 / across) * (TILE_H + S.s) - S.s
end

local function cores(width)
  local perf = model.perf
  local count = math.max(1, perf.info.logical or 1)
  local per_row = math.max(1, math.min(count, math.floor((width + S.xs) / (S.s + S.xs))))
  local lines = math.ceil(count / per_row)
  local slot = math.floor((width + S.xs) / per_row)
  local bar = math.min(CORE_MAX, math.max(S.xs, slot - S.xs))
  local nodes = { width = width, height = lines * (CORE_H + S.xs) }
  for index = 1, count do
    local function usage()
      local core = perf.cpu().cores[index]
      return core and core.usage or 0
    end
    nodes[#nodes + 1] = kit.vmeter {
      id = "monitor-core-" .. index, x = ((index - 1) % per_row) * slot, y = ((index - 1) // per_row) * (CORE_H + S.xs),
      width = bar, height = CORE_H, value = function() return usage() / 100 end, color = kit.level(usage),
    }
  end
  return ui.Item(nodes)
end

local function meter_line(id, label, value, level, width)
  return ui.Column {
    width = width, gap = S.xs,
    ui.Item {
      width = width, height = L.lh(P.SUB),
      kit.text { font_size = P.SUB, color = kit.ink("lo"), text = label },
      kit.text {
        id = id, anchors = { right = true }, font_size = P.SUB, font_weight = 500, color = kit.ink("hi"), text = value,
      },
    },
    kit.meter { width = width, height = S.s, value = level, color = kit.level(function() return level() * 100 end) },
  }
end

local function device_row(row, width)
  local perf = model.perf
  local function series(which)
    local first, second = perf.row_series(row)
    return which == 1 and first or second
  end
  local function usable(value) return type(value) == "table" and value or {} end
  local spark = math.min(160, math.floor(width * 0.34))
  local text_w = width - spark - S.m
  return ui.Item {
    id = "monitor-device-" .. row.key, width = width, height = DEVICE_H,
    ui.Column {
      width = text_w, gap = S.xxs, anchors = { vertical_center = true },
      kit.text {
        width = text_w, elide = "right", font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi"),
        text = function() return perf.row_title(row) .. "  " .. perf.row_value(row) end,
      },
      kit.text {
        width = text_w, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
        text = function() return perf.row_sub(row) end,
      },
    },
    ui.Item {
      anchors = { right = true, vertical_center = true }, width = spark, height = 44,
      (kit.chart {
        width = spark, height = 44, samples = perf.samples, first = function() return usable(series(1)()) end,
        second = row.kind == "net" and function() return usable(series(2)()) end or nil,
        top = row.kind ~= "net" and 100 or nil, floor = 1024,
      }),
    },
  }
end

local function resources_body(whole, h)
  local perf = model.perf
  local width = whole - GUTTER
  local inner = width - 2 * P.PAD
  local summary, summary_h = tiles(width)
  local half = width >= WIDE
  local pair = half and math.floor((width - P.GAP) / 2) or width
  local pair_inner = pair - 2 * P.PAD
  local speeds = controls.segments {
    id = "monitor-speed", items = { "1 s", "2 s", "5 s" }, width = math.min(inner, 300),
    current = function()
      for index, ms in ipairs(model.SPEEDS) do if ms == model.speed:get() then return index end end
      return 2
    end,
    on_changed = function(index) model.set_speed(model.SPEEDS[index]) end,
  }
  local cpu = P.section {
    id = "monitor-cpu", title = "CPU", note = function() return perf.ghz(perf.cpu().frequency) end, width = pair,
    kit.text {
      id = "monitor-cpu-name", width = pair_inner, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
      text = function() return perf.cpu_name(perf.info.model) end,
    },
    L.chart {
      width = pair_inner, height = CHART_H, samples = perf.samples, top = 100, caption = "Use",
      first = function() return perf.history("cpu") end, scale = function() return "100%" end,
    },
    cores(pair_inner),
    kit.text {
      id = "monitor-cpu-load", width = pair_inner, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
      text = function()
        local load = perf.cpu().load or { 0, 0, 0 }
        return ("Load %.2f %.2f %.2f, up %s"):format(load[1], load[2], load[3], perf.duration(perf.system().uptime))
      end,
    },
  }
  local memory = P.section {
    id = "monitor-memory", title = "Memory and swap", width = pair,
    note = function() return size(perf.memory().total) end,
    L.chart {
      width = pair_inner, height = CHART_H, samples = perf.samples, top = 100, caption = "Use",
      first = function() return perf.history("memory") end, scale = function() return "100%" end,
    },
    meter_line("monitor-memory-used", "Memory", function()
      local m = perf.memory()
      return ("%s of %s, %s cached"):format(size(m.used), size(m.total), size(m.cached))
    end, function() return (perf.memory().percent or 0) / 100 end, pair_inner),
    meter_line("monitor-swap-used", "Swap", function()
      local swap = perf.memory().swap
      if swap.total <= 0 then return "None" end
      return ("%s of %s"):format(size(swap.used), size(swap.total))
    end, function()
      local swap = perf.memory().swap
      return swap.total > 0 and swap.used / swap.total or 0
    end, pair_inner),
  }
  local devices = P.section {
    id = "monitor-devices", title = "Devices", width = width,
    kit.text {
      id = "monitor-totals", width = inner, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
      text = function()
        local all = model.totals()
        return ("Since boot: %s read, %s written, %s down, %s up"):format(size(all.read_total), size(all.write_total),
          size(all.rx_total), size(all.tx_total))
      end,
    },
    ui.Item {
      width = inner, height = function() return math.max(1, model.devices:len() * (DEVICE_H + S.xs)) end,
      ui.Repeater {
        model = model.devices, as = "column", gap = S.xs,
        delegate = function(row) return device_row(row, inner) end,
      },
    },
  }
  local top = half and ui.Row { width = width, gap = P.GAP, cpu, memory } or ui.Column { width = width, gap = P.GAP, cpu, memory }
  return (kit.scroll {
    id = "monitor-resources-scroll", width = whole, height = h, clip = true,
    ui.Column {
      width = width, gap = P.GAP,
      ui.Item { width = width, height = summary_h, summary },
      top,
      devices,
      ui.Row {
        width = width, gap = S.m, align = "center",
        kit.text { font_size = P.SUB, color = kit.ink("lo"), text = "Update every" },
        speeds,
      },
    },
  })
end

local function resources_page(w, h)
  return fit.width { id = "monitor-resources", width = w, height = h, build = function(width) return resources_body(width, h) end }
end

-- ---------------------------------------------------------------- sensors --

local function sensor_row(row, width)
  local temperature = row.kind == "temperature"
  local function now() return model.sensor(row.key) or {} end
  local function level()
    local sensor = now()
    if temperature then return math.min(1, (sensor.celsius or 0) / (sensor.critical or 100)) end
    return math.min(1, (sensor.rpm or 0) / ((sensor.max and sensor.max > 0) and sensor.max or 8000))
  end
  local bar = math.max(64, math.floor(width * 0.28))
  local value_w = 92
  local text_w = width - bar - value_w - S.m * 2
  return ui.Item {
    id = "monitor-sensor-" .. row.key, width = width, height = SENSOR_H,
    ui.Column {
      width = text_w, gap = S.xxs, anchors = { vertical_center = true },
      kit.text {
        width = text_w, elide = "right", font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi"),
        text = row.label,
      },
      kit.text { width = text_w, elide = "right", font_size = P.SUB, color = kit.ink("lo"), text = row.chip },
    },
    kit.meter {
      x = text_w + S.m, anchors = { vertical_center = true }, width = bar, height = S.s, value = level,
      color = kit.level(function() return level() * 100 end),
    },
    kit.text {
      id = "monitor-sensor-value-" .. row.key, anchors = { right = true, vertical_center = true }, width = value_w,
      horizontal_alignment = "right", font_size = theme.size.normal, color = kit.ink("hi"),
      text = function()
        local sensor = now()
        if temperature then return ("%.1f °C"):format(sensor.celsius or 0) end
        return ("%d RPM"):format(math.floor(sensor.rpm or 0))
      end,
    },
  }
end

local function sensors_body(whole, h)
  local width = whole - GUTTER
  local inner = width - 2 * P.PAD
  local sysinfo = require("lib.services.sysinfo")
  return ui.Item {
    width = whole, height = h,
    P.empty {
      id = "monitor-sensors-empty", icon = "thermostat", title = "No sensors", width = whole,
      text = "This machine reports no temperatures and no fans.",
      visible = function() return model.sensors:len() == 0 end,
    },
    (kit.scroll {
      id = "monitor-sensors-scroll", width = whole, height = h, clip = true,
      visible = function() return model.sensors:len() > 0 end,
      ui.Column {
        width = width, gap = P.GAP,
        P.section {
          id = "monitor-temperature", title = "CPU temperature", width = width,
          note = function()
            local t = model.perf.temps().cpu
            return t and ("%.1f °C"):format(t) or ""
          end,
          visible = function() return model.perf.temps().cpu ~= nil end,
          (L.chart {
            width = inner, height = CHART_H, samples = model.perf.samples, floor = 40,
            first = function()
              if not model.showing("sensors") then return {} end
              return sysinfo.history("temperature")
            end,
          }),
        },
        P.section {
          id = "monitor-sensors", title = "Sensors", width = width,
          note = function() return tostring(model.sensors:len()) end,
          ui.Item {
            width = inner, height = function() return math.max(1, model.sensors:len() * (SENSOR_H + S.xs)) end,
            ui.Repeater {
              model = model.sensors, as = "column", gap = S.xs,
              delegate = function(row) return sensor_row(row, inner) end,
            },
          },
        },
      },
    }),
  }
end

local function sensors_page(w, h)
  return fit.width { id = "monitor-sensors-page", width = w, height = h, build = function(width) return sensors_body(width, h) end }
end

--- The header's pause.
function M.actions()
  return L.icon_button {
    id = "monitor-pause", name = "Pause", width = S.TARGET, height = S.TARGET,
    icon = function() return model.paused:get() and "play_arrow" or "pause" end,
    on = function() return model.paused:get() end,
    on_clicked = function() model.paused:set(not model.paused:get()) end,
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return (controls.pages {
    id = "monitor", width = w, height = h, tab = model.tab,
    tabs = {
      { key = "processes", name = "Processes", icon = "list_alt", build = processes_page },
      { key = "resources", name = "Resources", icon = "monitoring", build = resources_page },
      { key = "sensors", name = "Sensors", icon = "thermostat", build = sensors_page },
    },
  })
end

return M
