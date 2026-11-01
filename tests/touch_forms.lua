-- The forms a finger meets eva on, for the touch specs: a phone, a touchscreen
-- with no keyboard, and a Surface with its Type Cover on. The last two are desks.
local test = morf.test
local M = {}

M.FORMS = {
  { name = "phone", size = { 620, 1380 }, devices = "tests/fixtures/input-devices-touch", sheet = true },
  { name = "touchscreen alone", size = { 1280, 800 }, devices = "tests/fixtures/input-devices-touch" },
  { name = "desk with a touchscreen", size = { 1440, 900 }, devices = "tests/fixtures/input-devices-cover" },
}

--- Loads the shell on `form` in `style` with `source` as its configuration.
function M.load(form, style, source, env)
  test.stub_run("task", { code = 0, stdout = "[]" })
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  local all = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "",
    EVA_INPUT_DEVICES = form.devices, LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do all[key] = value end
  test.load("../shell/init.lua", { source = source, size = form.size, env = all })
  test.settle(2000)
end

--- One finger from (x, y) by (dx, dy) over `steps` frames; `hold` keeps it
--- down at the end, `slow` lets it rest first so it lets go with no speed.
function M.drag(x, y, dx, dy, opts)
  opts = opts or {}
  local steps = opts.steps or 12
  test.touch("down", 0, x, y) test.advance(16)
  for i = 1, steps do
    test.touch("move", 0, x + dx * i / steps, y + dy * i / steps) test.advance(16)
  end
  if opts.hold then return end
  if opts.slow then test.advance(150) end
  test.touch("up", 0, x + dx, y + dy)
  test.advance(opts.after or 900)
end

--- Lets go of the finger `drag` kept down at (x, y).
function M.lift(x, y, after)
  test.touch("up", 0, x, y)
  test.advance(after or 900)
end

return M
