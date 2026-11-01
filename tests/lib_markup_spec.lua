-- Markdown into blocks and runs.
--     morf test --no-dbus tests/lib_markup_spec.lua
local test = morf.test
local HOST = [[
  local markup = require("lib.shell.markup")
  morf.ipc.blocks = function(text) return markup.blocks(text) end
  morf.ipc.inline = function(text) return markup.inline(text) end
]]
local function kinds(blocks)
  local out = {}
  for i, block in ipairs(blocks) do out[i] = block.kind end
  return out
end

test.describe("markup", function()
  test.before_each(function() test.load { source = HOST } end)

  test.it("splits a reply into its blocks", function()
    local blocks = test.ipc("blocks", "# Title\n\nSome text\nrunning on.\n\n- one\n- two\n\n1. first\n\n> said\n\n---\n\n```lua\nlocal a = 1\n```\n\nEnd.")
    test.eq(kinds(blocks), { "heading", "paragraph", "item", "item", "item", "quote", "rule", "code", "paragraph" })
    test.eq(blocks[1].level, 1)
    test.eq(blocks[2].text, "Some text running on.")
    test.eq(blocks[3].mark, "•")
    test.eq(blocks[5].mark, "1.")
    test.eq(blocks[8].language, "lua")
    test.eq(blocks[8].text, "local a = 1")
    test.eq(blocks[8].open, false)
  end)

  test.it("reads a fence still arriving as code", function()
    local blocks = test.ipc("blocks", "Look:\n\n```py\nprint(1)\nprint(2")
    test.eq(kinds(blocks), { "paragraph", "code" })
    test.eq(blocks[2].open, true)
    test.eq(blocks[2].text, "print(1)\nprint(2")
  end)

  test.it("keeps markup inside a fence as it is", function()
    local blocks = test.ipc("blocks", "```\n# not a heading\n- not an item\n```")
    test.eq(kinds(blocks), { "code" })
    test.eq(blocks[1].text, "# not a heading\n- not an item")
  end)

  test.it("marks runs of text", function()
    local spans = test.ipc("inline", "a **b** c *d* `e` ~~f~~ [g](https://h.test)")
    test.eq(spans[1], "a ")
    test.eq(spans[2].text, "b") test.eq(spans[2].bold, true)
    test.eq(spans[4].text, "d") test.eq(spans[4].italic, true)
    test.eq(spans[6].text, "e") test.eq(spans[6].code, true)
    test.eq(spans[8].text, "f") test.eq(spans[8].strike, true)
    test.eq(spans[10].text, "g") test.eq(spans[10].link, "https://h.test")
  end)

  test.it("finds a bare address and leaves its full stop", function()
    local spans = test.ipc("inline", "See https://a.test/b?c=1.")
    test.eq(spans[2].link, "https://a.test/b?c=1")
    test.eq(spans[3], ".")
  end)

  test.it("leaves an unclosed mark as typed, and code unmarked inside", function()
    test.eq(test.ipc("inline", "2 * 3 **open"), { "2 * 3 **open" })
    local spans = test.ipc("inline", "`**x**`")
    test.eq(spans[1].text, "**x**")
    test.eq(spans[1].bold, nil)
  end)
end)
