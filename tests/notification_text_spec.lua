-- What a card reads out of a notification: markup, links, codes, its face and
-- its buttons. Nothing here draws.
--
--     morf test --no-dbus tests/notification_text_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  local text = require("themes.notification_text")
  ui.Item { width = 100, height = 100 }
  morf.ipc.call = function(name, value)
    local decoded = morf.json.decode(value)
    local answer = text[name](decoded)
    if answer == nil then return "nil" end
    return answer
  end
]]
local function call(name, value)
  local answer = test.ipc("call", name, morf.json.encode(value))
  if answer == "nil" then return nil end
  return answer
end

test.before_each(function() test.load("../shell/init.lua", { source = HOST, size = { 100, 100 } }) end)

test.it("markup keeps the spec's tags and loses its pictures", function()
  test.eq(call("markup", "<b>Ada</b> <i>wrote</i>"), "<b>Ada</b> <i>wrote</i>")
  test.eq(call("markup", 'See <img src="/tmp/a.png" alt="a"/> this'), "See  this")
end)

test.it("only web and mail links may open", function()
  test.truthy(call("safe_link", "https://example.org/a"))
  test.truthy(call("safe_link", "http://example.org"))
  test.truthy(call("safe_link", "mailto:ada@example.org"))
  for _, href in ipairs { "file:///etc/passwd", "javascript:alert(1)", "/etc/passwd", "--help", "ssh://host", "" } do
    test.falsy(call("safe_link", href), href)
  end
end)

test.it("a picture comes from raw pixels, a path, or a local <img>", function()
  test.eq(call("image_of", { image_source = "memory:n-1", image = "/a.png" }), "memory:n-1")
  test.eq(call("image_of", { image = "/a.png" }), "/a.png")
  test.eq(call("image_of", { body = 'Hi <img src="/tmp/b.png" alt="x">' }), "/tmp/b.png")
  test.eq(call("image_of", { body = '<img src="file:///tmp/c.png"/>' }), "file:///tmp/c.png")
  test.eq(call("image_of", { body = '<img src="https://tracker.example/p.gif"/>' }), "", "a remote picture was fetched")
  test.eq(call("image_of", { body = "plain" }), "")
end)

test.it("a one-time code is found where one is meant", function()
  test.eq(call("otp", { summary = "Your code", body = "Use 482913 to sign in" }), "482913")
  test.eq(call("otp", { summary = "Verification", body = "Code: 123-456" }), "123456")
  test.eq(call("otp", { summary = "Login", body = "PIN 7741" }), "7741")
  test.eq(call("otp", { summary = "Bank", body = "Your security code is G-559201" }), "G-559201")
  test.eq(call("otp", { summary = "<b>OTP</b>", body = "&lt;b&gt;884421&lt;/b&gt;" }), "884421")
end)

test.it("numbers are not codes without the words", function()
  test.eq(call("otp", { summary = "Order", body = "Order 482913 has shipped" }), nil)
  test.eq(call("otp", { summary = "Meeting", body = "At 1500 in room 4021" }), nil)
  test.eq(call("otp", { summary = "Code review", body = "Reviewed in 2026" }), nil, "a year passed for a code")
end)

test.it("the first web link is found, without what ends its sentence", function()
  test.eq(call("link", { body = "Read https://example.org/a?b=1." }), "https://example.org/a?b=1")
  test.eq(call("link", { body = '<a href="https://example.org/x">here</a>' }), "https://example.org/x")
  test.eq(call("link", { body = '<a href="file:///etc/passwd">bad</a>' }), nil)
  test.eq(call("link", { body = "none" }), nil)
end)

test.it("a card's face follows what it carries", function()
  test.eq(call("style", { category = "call.incoming" }), "call")
  test.eq(call("style", { actions = { { key = "media-skip-forward", label = "Next" } } }), "media")
  test.eq(call("style", { hints = { value = 40 } }), "progress")
  test.eq(call("style", { category = "im.received" }), "message")
  test.eq(call("style", { image = "/a.png" }), "image")
  test.eq(call("style", { summary = "Plain" }), "plain")
end)

test.it("media controls come from the sender's own actions", function()
  local list = call("transport", { actions = { { key = "media-skip-backward", label = "Previous" },
    { key = "media-playback-pause", label = "Pause" }, { key = "media-skip-forward", label = "" },
    { key = "other", label = "Other" } } })
  test.eq(#list, 3)
  test.eq(list[1].icon, "skip_previous")
  test.eq(list[2].icon, "pause")
  test.eq(list[3].icon, "skip_next")
  test.eq(list[3].name, "next")
end)

test.it("a card's buttons leave out the body's click and the media controls", function()
  local list = call("buttons", { actions = { { key = "default", label = "Open" }, { key = "inline-reply", label = "" },
    { key = "media-playback-pause", label = "Pause" }, { key = "archive", label = "Archive" } } })
  test.eq(#list, 2)
  test.eq(list[1].label, "Reply")
  test.truthy(list[1].reply)
  test.eq(list[2].key, "archive")
end)

test.it("a reply field asks in the sender's words", function()
  test.eq(call("reply_prompt", { hints = { ["x-kde-reply-placeholder-text"] = "Message Ada" } }), "Message Ada")
  test.eq(call("reply_prompt", {}), "Reply")
end)

test.it("a job's line says how long is left once that is known", function()
  test.eq(call("progress_line", { hints = { value = 25 } }), "25% done · 75% left")
  test.eq(call("progress_line", { hints = { value = 25 }, eta = 90 }), "25% done · 1 min left")
end)
