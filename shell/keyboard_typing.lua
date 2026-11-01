-- What a struck key becomes before it reaches the field: a full stop from two
-- spaces, punctuation pulled over an automatic space, a word deleted whole, a
-- correction, a shortcut, the emoji search. `new { deliver, delete, keys }`
-- takes what sends an event, what deletes bytes before the cursor, and the
-- board's `keys`.
local config = require("config")
local model = require("keyboard_model")
local predict = require("keyboard_predict")
local learn = require("keyboard_learn")

local M = {}

-- Repeats of a held backspace before it deletes by the word, and how many
-- repeats each word then takes.
M.WORD_AFTER, M.WORD_EVERY = 12, 6

function M.new(ctx)
  local T = {}
  local spaced, auto_spaced = false, false
  local held, ticks = 0, 0
  local undo

  local function on(name) return config.get("keyboard." .. name) == true end
  local function aids() return model.aids(ctx.keys.mode:get()) end
  local function chars(text) return utf8.len(text) or #text end

  -- Takes `cut` bytes before the cursor away and types `text` there.
  local function replace(cut, text, mods)
    if cut > 0 then
      if model.field:get().active then ctx.delete(cut)
      else
        local gone = model.before():sub(-cut)
        for _ = 1, chars(gone) do ctx.deliver { key = "backspace" } end
      end
    end
    if text ~= "" then ctx.deliver { text = text, mods = mods } end
    model.echo(cut, text)
  end

  -- What space does to the word it ends: a shortcut expands, a slip is fixed.
  local function finish_word(word)
    if word == "" then return end
    local out = predict.shortcut(word)
    if not out and on("autocorrect") then out = predict.correction(word) end
    if out and out ~= word then
      replace(#word, out)
      undo = { from = out, to = word }
    else
      undo = nil
    end
    learn.note(out or word)
  end

  local function type_text(text, mods)
    local smart = aids()
    if text == " " then
      local before = model.before()
      if smart and spaced and on("double_space") and before:match("[%w\128-\255%)%]\"']%s$") then
        spaced = false
        replace(1, ". ", mods)
        return
      end
      if smart then finish_word(model.word()) end
      ctx.deliver { text = text, mods = mods }
      model.echo(0, text)
      spaced, auto_spaced = true, false
      return
    end
    if smart and auto_spaced and text:match("^[%.,!%?;:]$") then
      replace(1, text .. " ", mods)
      spaced, auto_spaced = false, false
      return
    end
    undo = nil
    spaced, auto_spaced = false, false
    ctx.deliver { text = text, mods = mods }
    model.echo(0, text)
  end

  local function delete_word()
    local before = model.before()
    local trail = before:match("%s*$")
    local word = model.tail(before:sub(1, #before - #trail))
    local cut = #word + #trail
    if cut == 0 then cut = model.last_char() end
    if model.known() or model.memo:get() ~= "" then
      replace(math.min(cut, #before), "")
    else
      ctx.deliver { key = "backspace", mods = { ctrl = true } }
    end
  end

  local function backspace(mods)
    spaced, auto_spaced = false, false
    held = held + 1
    if undo and held == 1 then
      local back = undo
      undo = nil
      if model.word() == "" and model.before():sub(-(#back.from + 1)) == back.from .. " " then
        replace(#back.from + 1, back.to .. " ")
        return
      end
    end
    if held > M.WORD_AFTER then
      if ticks == 0 then require("haptics").fire("long") end
      ticks = ticks + 1
      if ticks % M.WORD_EVERY == 1 then delete_word() end
      return
    end
    ctx.deliver { key = "backspace", mods = mods }
    if model.before() ~= "" then model.echo(model.last_char(), "") end
  end

  local function search(event)
    if event.text then
      model.query:set(model.query:get() .. event.text)
    elseif event.key == "backspace" then
      local query = model.query:get()
      local stop = utf8.offset(query, -1)
      model.query:set(stop and query:sub(1, stop - 1) or "")
    elseif event.key == "enter" or event.key == "escape" then
      model.searching:set(false)
      model.show_pane("emoji")
    end
  end

  --- A key was struck, after the language has had it.
  function T.strike(event)
    local mods = event.mods or {}
    local modded = mods.ctrl or mods.alt or mods.super
    if model.searching:get() and not modded then return search(event) end
    if event.text and not modded then return type_text(event.text, event.mods) end
    if event.key == "backspace" and not modded then return backspace(event.mods) end
    ctx.deliver(event)
    spaced, auto_spaced = false, false
    undo = nil
    if event.key and not model.known() then model.forget() end
  end

  --- A finger came down on the key `name`.
  function T.pressed(name)
    if name == "backspace" then held, ticks = 0, 0 end
  end

  --- Puts an offer in place of the word being typed.
  function T.pick(offer)
    local word = model.word()
    local out = offer.text
    if offer.kind ~= "emoji" and on("auto_space") then out = out .. " " end
    replace(#word, out)
    auto_spaced = offer.kind ~= "emoji" and on("auto_space")
    spaced, undo = false, nil
    learn.note(offer.text)
  end

  --- Types an emoji at the cursor.
  function T.emoji(char)
    spaced, auto_spaced, undo = false, false, nil
    ctx.deliver { text = char }
    model.echo(0, char)
  end

  --- Pastes `text`, through the input method where a field is asking.
  function T.paste(text)
    spaced, auto_spaced, undo = false, false, nil
    if model.field:get().active and #text <= 4000 then
      ctx.deliver { text = text }
      model.echo(0, text)
      return
    end
    ctx.set_clipboard(text)
    ctx.deliver { text = "v", mods = { ctrl = true } }
    if not model.known() then model.forget() end
  end

  return T
end

return M
