-- The Assistant's settings page: which provider, where it is, which model, its
-- key and the system prompt. A key typed here stays in a local of the page and
-- goes once to the keyring; no signal ever holds it.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local R = require("themes.layouts.rows")
local widgets = require("planner_widgets")
local C = theme.color
local S = theme.space
local V = {}

local SYSTEM_H = 112

--- The page; `model` is shell/assistant_model.lua.
function V.page(model, w, h)
  local inner = P.inner(w)
  local stamp = tostring({})
  local said = morf.signal("eva.assistant.settings.said." .. stamp, "")
  local typed = morf.signal("eva.assistant.settings.typed." .. stamp, false)
  local models = morf.signal("eva.assistant.settings.models." .. stamp, {})
  local key = ""
  local function chosen() return model.kind() end
  local function kind() return model.KINDS[chosen()] end

  local kinds = {}
  kinds[1] = { id = "assistant-kind-off", label = "Off", group = "assistant-kind",
    selected = function() return chosen() == "" end, on_clicked = function() model.choose("") end }
  for _, id in ipairs(model.ORDER) do
    kinds[#kinds + 1] = { id = "assistant-kind-" .. id, label = model.KINDS[id].name, group = "assistant-kind",
      selected = function() return chosen() == id end, on_clicked = function() model.choose(id) end }
  end

  local base_node, base = widgets.field("assistant-base", "Address", "https://…", inner,
    function(value) if chosen() ~= "" then model.set_field(chosen(), "base", value) end end)
  local model_node, model_input = widgets.field("assistant-model", "Model", "Which model answers", inner,
    function(value) if chosen() ~= "" then model.set_field(chosen(), "model", value) end end)
  -- The fields follow the provider chosen.
  morf.effect("assistant.settings.fields", function()
    local provider = model.provider()
    if provider then
      if base.text ~= provider.base then base.text = provider.base end
      if model_input.text ~= provider.model then model_input.text = provider.model end
    end
  end, { owner = base_node })

  local presets = { width = inner, id = "assistant-presets" }
  for i, preset in ipairs(model.PRESETS) do
    presets[#presets + 1] = { id = "assistant-preset-" .. i, label = preset.name,
      on_clicked = function() model.set_field("openai", "base", preset.base) end }
  end
  local preset_row = P.buttons(presets)


  local list = P.button { id = "assistant-list-models", label = "List models", icon = "list", on_clicked = function()
    said:set("Asking…")
    model.models(function(found, why)
      if not found then said:set(why) return end
      models:set(found)
      said:set(#found == 0 and "No models there" or (#found .. " models. Press one to use it."))
    end)
  end }
  local offered = ui.Repeater { as = "column", gap = S.xs, width = inner,
    model = (function()
      local rows = morf.list_model({})
      morf.effect("assistant.settings.offered", function()
        local out = {}
        for i, id in ipairs(models:get()) do if i <= 12 then out[i] = { id = id } end end
        rows:replace(out, "id")
      end, { owner = base_node })
      return rows
    end)(),
    delegate = function(row)
      return P.button { id = "assistant-pick-" .. row.id:gsub("[^%w]", "-"), label = row.id, width = inner,
        selected = function() return model.provider() ~= nil and model.provider().model == row.id end,
        on_clicked = function() model.set_field(chosen(), "model", row.id) end }
    end }

  local key_node, key_input = kit.text_field("password", {
    id = "assistant-key", x = S.m, width = inner - 2 * S.m, height = 40, reveal = false,
    font_family = theme.font, font_size = theme.size.normal, color = function() return C.onSurface end,
    placeholder = "Paste a key", placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.3) end,
    on_text_changed = function(value) key = value typed:set(value ~= "") end,
  })
  local function save_key()
    local given = key
    key = ""
    key_input.text = ""
    typed:set(false)
    model.save_key(given, function(ok, why)
      said:set(ok and "Saved in the keyring" or tostring(why))
    end)
  end
  key_input.on_accepted = save_key

  local function key_words()
    local state = model.key_state:get()
    if state == "saved" then return "A key is saved in the keyring" end
    if state == "no-tool" then return "secret-tool is not installed" end
    if state == "failed" then return "The keyring did not answer" end
    if state == "none" then return "No key saved" end
    return "Checking the keyring"
  end
  local key_section = P.section { id = "assistant-key-section", width = w, title = "API key",
    visible = function() return chosen() ~= "" and kind().needs_key end,
    P.row { id = "assistant-key-state", width = inner, icon = "key", title = key_words,
      on = function() return model.key_state:get() == "saved" end,
      subtitle = "Held by the Secret Service, not in eva's settings" },
    ui.Column { width = inner, gap = S.xs, widgets.label("Key"), R.well { width = inner, height = 40, key_node } },
    P.buttons { width = inner,
      { id = "assistant-key-save", label = "Save key", icon = "save", tone = "primary",
        enabled = function() return typed:get() end, on_clicked = save_key },
      { id = "assistant-key-forget", label = "Forget key", icon = "delete",
        enabled = function() return model.key_state:get() == "saved" end,
        on_clicked = function()
          model.forget_key(function(ok, why) said:set(ok and "Forgotten" or tostring(why)) end)
        end },
    },
  }

  local system_node, system_input = kit.text_field("text_area", {
    id = "assistant-system", width = inner, height = SYSTEM_H, well = true, inset = { S.m, S.s, S.m, S.s },
    font_family = theme.font, font_size = theme.size.normal, color = function() return C.onSurface end,
    placeholder = "How the assistant should answer", placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.3) end,
    on_text_changed = function(value) require("config").set("assistant.system", value) end,
  })
  system_input.text = require("config").get("assistant.system") or ""

  local history = function() return require("config").get("assistant.history") ~= false end
  local folder_box, folder_input = P.field { id = "assistant-folder", width = inner, placeholder = "The state folder",
    name = "Conversations folder", on_changed = function(value) require("config").set("assistant.folder", value) end }
  local folder_node = ui.Column { width = inner, gap = S.xs,
    require("themes.layouts.form").note(inner, "Conversations folder"), folder_box }
  folder_input.text = require("config").get("assistant.folder") or ""
  local page = P.page { id = "settings-assistant-scroll", width = w, height = h,
    P.section { id = "assistant-provider", width = w, title = "Provider",
      P.buttons { width = inner, kinds[1], kinds[2] },
      P.buttons { width = inner, table.unpack(kinds, 3) },
      P.row { id = "assistant-provider-state", width = inner, icon = "forum", title = model.summary,
        on = function() return model.state() == "ready" end,
        subtitle = function()
          if model.state() == "ready" then return "Ready" end
          if chosen() == "" then return "Pick a provider above" end
          return (select(2, model.explain()))
        end },
    },
    P.section { id = "assistant-endpoint", width = w, title = "Endpoint",
      visible = function() return chosen() ~= "" end,
      P.fold { width = inner, shown = function() return chosen() == "openai" end, gap = P.ROW_GAP,
        head = base_node, preset_row },
      model_node, list, offered,
    },
    key_section,
    kit.subtitle { id = "assistant-settings-said", width = w, wrap = true, font_size = P.SUB,
      color = kit.ink("lo"), text = function() return said:get() end, visible = function() return said:get() ~= "" end },
    P.section { id = "assistant-behaviour", width = w, title = "Behaviour",
      ui.Column { width = inner, gap = S.xs, widgets.label("System prompt"),
        system_node },
      P.row { id = "assistant-history", width = inner, icon = "history", title = "Keep conversations", on = history,
        subtitle = function() return history() and "On this machine, in plain JSON" or "Nothing is written to disk" end,
        trailing = P.switch { id = "assistant-history-switch", name = "Keep conversations", on = history,
          on_toggled = function(on) require("config").set("assistant.history", on) end } },
      folder_node,
    },
  }
  return page
end

return V
