-- Markdown, as far as a chat reply or a note uses it: a list of blocks, each
-- with runs of inline text, kept as plain data for a list model. A fence left
-- open reads as code to the end, so a reply still arriving reads well.
--
--   markup.blocks("# Hi\n\nSome **bold** text.")
--     --> { { key = "1:heading", kind = "heading", level = 1, spans = { "Hi" }, text = "Hi" }, ... }
--
-- A block is `heading` (`level`), `paragraph`, `item` (`mark`, `depth`),
-- `quote`, `code` (`language`, `open`), `table` or `rule`. A span is a string,
-- or `{ text, bold, italic, code, strike, link }`.
local M = {}

local PATTERNS = {
  { "`([^`\n]+)`", "code" }, { "%*%*(.-)%*%*", "bold" }, { "__(.-)__", "bold" }, { "~~(.-)~~", "strike" },
  { "%*([^%s*][^*\n]-)%*", "italic" }, { "%f[%w_]_([^%s_][^_\n]-)_%f[^%w_]", "italic" },
}

-- The earliest inline mark in `text` from `from`: where, where it ends, what.
local function next_mark(text, from)
  local best_s, best_e, best_kind, best_value, best_link
  local function consider(s, e, kind, value, link)
    if s and (not best_s or s < best_s) then
      best_s, best_e, best_kind, best_value, best_link = s, e, kind, value, link
    end
  end
  for _, pattern in ipairs(PATTERNS) do
    local s, e, value = text:find(pattern[1], from)
    consider(s, e, pattern[2], value)
  end
  local s, e, label, target = text:find("%[([^%]\n]+)%]%(([^%s%)]+)%)", from)
  consider(s, e, "link", label, target)
  s, e = text:find("https?://[%w%-%._~:/%?#%[%]@!%$&'%*%+,;=%%]+", from)
  if s then
    local url = text:sub(s, e):gsub("[%.,;:!%?%)]+$", "")
    consider(s, s + #url - 1, "link", url, url)
  end
  return best_s, best_e, best_kind, best_value, best_link
end

--- The runs of one line of text.
function M.inline(text)
  local spans, from = {}, 1
  while from <= #text do
    local s, e, kind, value, link = next_mark(text, from)
    if not s then
      spans[#spans + 1] = text:sub(from)
      break
    end
    if s > from then spans[#spans + 1] = text:sub(from, s - 1) end
    if kind == "link" then
      spans[#spans + 1] = { text = value, link = link }
    elseif kind == "code" then
      spans[#spans + 1] = { text = value, code = true }
    else
      for _, inner in ipairs(M.inline(value)) do
        local run = type(inner) == "table" and inner or { text = inner }
        run[kind] = true
        spans[#spans + 1] = run
      end
    end
    from = e + 1
  end
  return spans
end

local function plain(spans)
  local out = {}
  for i, span in ipairs(spans) do out[i] = type(span) == "table" and span.text or span end
  return table.concat(out)
end
M.plain = plain

--- The blocks of `text`.
function M.blocks(text)
  local blocks, paragraph = {}, {}
  local code, table_rows
  local function add(block)
    block.key = (#blocks + 1) .. ":" .. block.kind
    blocks[#blocks + 1] = block
  end
  local function flush()
    if #paragraph > 0 then
      local spans = M.inline(table.concat(paragraph, " "))
      add { kind = "paragraph", spans = spans, text = plain(spans) }
      paragraph = {}
    end
    if table_rows then
      add { kind = "table", text = table.concat(table_rows, "\n") }
      table_rows = nil
    end
  end
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    if code then
      if line:match("^%s*```%s*$") or line:match("^%s*~~~%s*$") then
        add { kind = "code", language = code.language, text = table.concat(code.lines, "\n"), open = false }
        code = nil
      else
        code.lines[#code.lines + 1] = line
      end
    else
      local fence = line:match("^%s*```%s*([%w_+#.%-]*)") or line:match("^%s*~~~%s*([%w_+#.%-]*)")
      local level, heading = line:match("^(#+)%s+(.+)$")
      local indent, bullet = line:match("^(%s*)[%-%*%+]%s+(.+)$")
      local number_indent, number, numbered = line:match("^(%s*)(%d+)[%.%)]%s+(.+)$")
      local quote = line:match("^>%s?(.*)$")
      if fence then
        flush()
        code = { language = fence, lines = {} }
      elseif line:match("^%s*$") then
        flush()
      elseif level and #level <= 6 then
        flush()
        local spans = M.inline((heading:gsub("%s+#+%s*$", "")))
        add { kind = "heading", level = #level, spans = spans, text = plain(spans) }
      elseif line:match("^%s*[%-%*_]%s*[%-%*_]%s*[%-%*_][%-%*_%s]*$") then
        flush()
        add { kind = "rule", text = "" }
      elseif bullet then
        flush()
        local spans = M.inline(bullet)
        add { kind = "item", mark = "•", depth = #indent // 2, spans = spans, text = plain(spans) }
      elseif numbered then
        flush()
        local spans = M.inline(numbered)
        add { kind = "item", mark = number .. ".", depth = #number_indent // 2, spans = spans, text = plain(spans) }
      elseif quote then
        flush()
        local spans = M.inline(quote)
        add { kind = "quote", spans = spans, text = plain(spans) }
      elseif line:match("^%s*|.*|%s*$") then
        if #paragraph > 0 then flush() end
        table_rows = table_rows or {}
        table_rows[#table_rows + 1] = line
      else
        if table_rows then flush() end
        paragraph[#paragraph + 1] = (line:gsub("^%s+", ""))
      end
    end
  end
  flush()
  if code then add { kind = "code", language = code.language, text = table.concat(code.lines, "\n"), open = true } end
  return blocks
end

return M
