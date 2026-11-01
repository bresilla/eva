-- Lining up the frames of a scrolling window, on rows made up here.
--
--     morf test --no-dbus tests/lib_stitch_spec.lua
local test = morf.test

local function check(name, body)
  test.it(name, function()
    test.load { source = [[
      local S = require("lib.shell.capture.stitch")
      -- A page of `length` rows of its own, each row its number.
      local function page(length, blank)
        local rows = {}
        for y = 1, length do rows[y] = (blank and y % 7 == 0) and "blank" or "row" .. y end
        return rows
      end
      -- The frame of `height` rows at `at` down the page, a header and a footer on it.
      local function frame(rows, at, height, header, footer)
        local out = {}
        for y = 1, header or 0 do out[#out + 1] = "header" .. y end
        for y = 1, height - (header or 0) - (footer or 0) do out[#out + 1] = rows[at + y] end
        for y = 1, footer or 0 do out[#out + 1] = "footer" .. y end
        return out
      end
    ]] .. body .. "\nmorf.ipc.ok = function() return true end" }
    test.truthy(test.ipc("ok"))
    test.eq(#test.logs("error"), 0)
  end)
end

check("finds how far a frame moved, past blank lines", [[
  local rows = page(2000, true)
  local found = S.align(frame(rows, 0, 400), frame(rows, 120, 400))
  assert(found.kind == "moved" and found.shift == 120, found.kind)
]])

check("keeps a header and a footer out of it", [[
  local rows = page(2000)
  local found = S.align(frame(rows, 0, 400, 30, 20), frame(rows, 90, 400, 30, 20))
  assert(found.kind == "moved" and found.shift == 90 and found.top == 30 and found.bottom == 20)
]])

check("says nothing moved when nothing did", [[
  local rows = page(500)
  assert(S.align(frame(rows, 10, 300), frame(rows, 10, 300)).kind == "same")
]])

check("says nothing moved when only a clock in the header changed", [[
  local rows = page(500)
  local a, b = frame(rows, 10, 300, 20), frame(rows, 10, 300, 20)
  b[5] = "header-changed"
  assert(S.align(a, b).kind == "same")
]])

check("says nothing moved when a pill came up over the frame", [[
  local rows = page(500)
  local a, b = frame(rows, 10, 300), frame(rows, 10, 300)
  for y = 1, 40 do b[y] = "pill" .. y end
  assert(S.align(a, b).kind == "same")
]])

check("follows a page under a pill that came up after the first frame", [[
  local rows = page(1000)
  local a, b = frame(rows, 0, 300), frame(rows, 120, 300)
  for y = 1, 40 do b[y] = "pill" .. y end
  local found = S.align(a, b)
  assert(found.kind == "moved" and found.shift == 120, found.kind)
]])

check("finds a small overlap under a guarded pill, however many rows it covers", [[
  local rows = page(2000)
  local a, b = frame(rows, 0, 400, 30), frame(rows, 340, 400, 30)
  for y = 1, 44 do b[y] = "pill" .. y end
  assert(S.align(a, b).kind == "lost", "unguarded, the pill outvotes a small overlap")
  local found = S.align(a, b, 44)
  assert(found.kind == "moved" and found.shift == 340, found.kind)
]])

check("knows a frame that went back up", [[
  local rows = page(1000)
  local found = S.align(frame(rows, 200, 300), frame(rows, 150, 300))
  assert(found.kind == "back" and found.shift == 50)
]])

check("refuses a frame with no overlap", [[
  local rows = page(3000)
  assert(S.align(frame(rows, 0, 300), frame(rows, 900, 300)).kind == "lost")
]])

check("refuses a page of nothing but repeats", [[
  local rows = {}
  for y = 1, 2000 do rows[y] = "row" .. (y % 40) end
  assert(S.align(frame(rows, 0, 300), frame(rows, 100, 300)).kind == "lost")
]])

check("refuses frames of different heights", [[
  local rows = page(500)
  assert(S.align(frame(rows, 0, 300), frame(rows, 0, 280)).kind == "lost")
]])

check("refuses when most rows disagree with the best guess", [[
  local rows = page(2000)
  local a, b = frame(rows, 0, 400), frame(rows, 50, 400)
  for y = 1, 400 do if y % 10 > 1 then b[y] = "noise" .. y end end
  assert(S.align(a, b).kind == "lost")
]])

check("a run pastes every row of the page once, header and footer once", [[
  local rows = page(1400, true)
  local run = S.new(40)
  local canvas = {}
  local function paste(source, strip)
    for y = 1, strip.height do
      local at = strip.y + y
      assert(canvas[at] == nil, "row " .. at .. " pasted twice")
      canvas[at] = source[strip.from + y]
    end
  end
  local first = frame(rows, 0, 400, 30, 20)
  assert(run.add(first).kind == "first")
  local last = first
  for at = 200, 1000, 200 do
    local shot = frame(rows, at, 400, 30, 20)
    local found = run.add(shot)
    assert(found.kind == "moved", found.kind)
    if found.first then
      assert(found.first == 380)
      for y = 1, found.first do canvas[y] = first[y] end
    end
    paste(shot, found.strip)
    last = shot
  end
  local tail, total = run.finish()
  paste(last, tail)
  assert(total == 1400, "total " .. tostring(total))
  for y = 1, 30 do assert(canvas[y] == "header" .. y) end
  for y = 31, 1380 do assert(canvas[y] == rows[y - 30], "row " .. y) end
  for y = 1, 20 do assert(canvas[1380 + y] == "footer" .. y) end
]])

check("a short move waits, and is compared again from the same frame", [[
  local rows = page(1000)
  local run = S.new(100)
  run.add(frame(rows, 0, 300))
  assert(run.add(frame(rows, 40, 300)).kind == "small")
  assert(run.add(frame(rows, 80, 300)).kind == "small")
  local found = run.add(frame(rows, 150, 300))
  assert(found.kind == "moved" and found.shift == 150)
]])

check("a short last move can still be taken at the end", [[
  local rows = page(1000)
  local run = S.new(100)
  run.add(frame(rows, 0, 300))
  run.add(frame(rows, 150, 300))
  local small = run.add(frame(rows, 190, 300))
  assert(small.kind == "small")
  local kept = run.accept(small.rows, small.found)
  assert(kept.strip.height == 40 and kept.strip.y == 300 + 150)
  local _, total = run.finish()
  assert(total == 190 + 300, tostring(total))
]])

check("nothing moved means nothing to finish", [[
  local rows = page(500)
  local run = S.new(10)
  run.add(frame(rows, 0, 300))
  run.add(frame(rows, 0, 300))
  assert(run.finish() == nil)
]])
