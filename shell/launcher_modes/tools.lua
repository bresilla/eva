-- Small tools with their answer in the list: passwords, UUIDs, digests,
-- encodings, naming styles, placeholder text, dice and QR codes.
local morf = require("morf")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")
local codec = require("lib.shell.launcher.codec")
local password = require("lib.shell.launcher.password")
local qr = require("lib.util.qr")

local row, copied = rows.row, rows.copy

-- ------------------------------------------------------------- passwords --

-- A password is drawn as dots: its text goes to the clipboard and nowhere else.
local function secret_row(id, shown, description, make)
  local value = make()
  local function regenerate() value = make() return "keep" end
  return row {
    id = id, name = shown, description = description, material = "password", private = true,
    run = function() return run.copy_secret(value) end,
    actions = {
      { name = "Copy it", material = "content_copy", run = function() return run.copy_secret(value) end },
      { name = "Make another", material = "refresh", run = regenerate },
    },
  }
end

local function dots(length) return string.rep("•", math.min(length, 32)) end

local generated = {}

--- One password per question: typing does not draw a new one under the keys.
local function held(key, make)
  if not generated[key] then generated = { [key] = secret_row(key, make()) } end
  return generated[key]
end

registry.mode { id = "password", name = "Password", material = "password", shape = "pill",
  words = { "password", "pass", "pw" }, hint = "pw 24  ·  pw 16 nosym  ·  pw words 6",
  search = function(term)
    local words = {}
    for word in term:lower():gmatch("%S+") do words[word] = true end
    local length = tonumber(term:match("(%d+)")) or 24
    if words.words or words.phrase then
      local count = tonumber(term:match("(%d+)")) or 6
      local bits = password.passphrase_bits(count)
      return { held("pass:phrase:" .. count, function()
        return "•••• •••• •••• ••••", ("%d words, %d bits, %s"):format(count, bits, password.strength(bits):lower()),
          function() return password.passphrase(count) end
      end) }
    end
    local options = { symbols = not (words.nosym or words.plain), digits = not (words.nonum or words.alpha),
      upper = not words.lower }
    local size = #password.alphabet(options)
    local bits = password.bits(length, size)
    local key = "pass:" .. length .. ":" .. tostring(options.symbols) .. tostring(options.digits) .. tostring(options.upper)
    return { held(key, function()
      return dots(length), ("%d characters, %d bits, %s"):format(length, bits, password.strength(bits):lower()),
        function() return password.generate(length, options) end
    end) }
  end }

-- ------------------------------------------------------------------- uuid --

local function uuid_v7()
  local ms = morf.time.now_ms()
  local hex = morf.encoding.uuid():gsub("-", "")
  local stamp = ("%012x"):format(ms)
  return ("%s-%s-7%s-%s-%s"):format(stamp:sub(1, 8), stamp:sub(9, 12), hex:sub(1, 3), hex:sub(17, 20), hex:sub(21, 32))
end

local uuids = {}
registry.mode { id = "uuid", name = "UUID", material = "fingerprint", shape = "pill", words = { "uuid", "guid" },
  hint = "a fresh identifier, v4 or v7", search = function(term)
    if not uuids[1] or term == "new" then uuids = { morf.encoding.uuid(), uuid_v7() } end
    return {
      copied("uuid:4", uuids[1], "UUID v4  ·  random  ·  Return copies", "fingerprint"),
      copied("uuid:7", uuids[2], "UUID v7  ·  ordered by time  ·  Return copies", "schedule"),
      copied("uuid:4u", uuids[1]:upper(), "UUID v4 in capitals", "fingerprint"),
      copied("uuid:compact", (uuids[1]:gsub("-", "")), "UUID v4 without hyphens", "fingerprint"),
    }
  end }

-- ----------------------------------------------------------------- hashes --

local function digest_rows(text)
  return {
    copied("hash:md5", codec.md5(text), "MD5", "tag"),
    copied("hash:sha1", morf.encoding.sha1(text), "SHA-1", "tag"),
    copied("hash:sha256", morf.encoding.sha256(text), "SHA-256", "tag"),
  }
end

registry.mode { id = "hash", name = "Hash", material = "tag", shape = "pill", words = { "hash", "sha", "md5", "checksum" },
  hint = "hash some text  ·  hash ~/a/file", search = function(term)
    if term == "" then return { rows.note("hash", "Type text, or a file's path", "MD5, SHA-1, SHA-256, SHA-512", "tag") } end
    local path = rows.untilde(term)
    if morf.fs.is_file(path) then
      local sums = rows.ask("hashfile", path, function(done)
        return morf.process.run({ "sh", "-c", 'md5sum -- "$1"; sha1sum -- "$1"; sha256sum -- "$1"; sha512sum -- "$1"', "sh", path },
          { timeout_ms = 60000 }, function(result)
            local out = {}
            for digest in tostring(result and result.stdout or ""):gmatch("(%x+)%s[^\n]*\n") do out[#out + 1] = digest end
            done(out)
          end)
      end, { debounce_ms = 50 })
      if not sums then return { rows.note("hash", "Reading " .. rows.tilde(path) .. "…", "", "hourglass_top") } end
      local names = { "MD5", "SHA-1", "SHA-256", "SHA-512" }
      local out = {}
      for i, digest in ipairs(sums) do
        out[i] = copied("hash:" .. i, digest, names[i] .. " of " .. rows.tilde(path), "tag")
      end
      return out
    end
    local out = digest_rows(term)
    local sha512 = rows.ask("sha512", term, function(done)
      return morf.process.run({ "sha512sum" }, { stdin = term, timeout_ms = 2000 }, function(result)
        done(tostring(result and result.stdout or ""):match("^(%x+)"))
      end)
    end, { debounce_ms = 80 })
    if sha512 then out[#out + 1] = copied("hash:sha512", sha512, "SHA-512", "tag") end
    return out
  end }

-- -------------------------------------------------------------- encodings --

local function encoding_rows(text)
  local out = {
    copied("enc:b64", morf.encoding.base64_encode(text), "Base64 encoded", "code"),
    copied("enc:url", morf.encoding.url_encode(text), "URL encoded", "link"),
    copied("enc:hex", codec.hex_encode(text), "Hexadecimal", "tag"),
    copied("enc:html", codec.html_encode(text), "HTML entities", "code"),
    copied("enc:rot13", codec.rot13(text), "ROT13", "rotate_right"),
  }
  local ok, plain = pcall(morf.encoding.base64_decode, text)
  if ok and type(plain) == "string" and plain ~= "" and utf8.len(plain) then
    table.insert(out, 1, copied("dec:b64", plain, "Base64 decoded", "code_off"))
  end
  local fine, unescaped = pcall(morf.encoding.url_decode, text)
  if fine and unescaped ~= text then table.insert(out, 1, copied("dec:url", unescaped, "URL decoded", "link_off")) end
  local bytes = codec.hex_decode(text)
  if bytes and bytes ~= "" and utf8.len(bytes) then out[#out + 1] = copied("dec:hex", bytes, "Hexadecimal decoded", "tag") end
  local html = codec.html_decode(text)
  if html ~= text then out[#out + 1] = copied("dec:html", html, "HTML decoded", "code_off") end
  return out
end

registry.mode { id = "encode", name = "Encode", material = "code", shape = "pill",
  words = { "encode", "decode", "b64", "base64", "url", "hex" }, hint = "b64 hello  ·  url a b  ·  decode aGk=",
  search = function(term)
    if term == "" then return { rows.note("encode", "Type text to encode or decode", "Base64, URL, hex, HTML, ROT13", "code") } end
    return encoding_rows(term)
  end }

registry.mode { id = "case", name = "Case", material = "match_case", shape = "pill", words = { "case" },
  hint = "case some words  ·  every naming style", search = function(term)
    if term == "" then return { rows.note("case", "Type text to restyle", "camelCase, snake_case, Title Case…", "match_case") } end
    local out = {}
    for i, c in ipairs(codec.cases(term)) do out[i] = copied("case:" .. i, c[2], c[1], "match_case") end
    return out
  end }

registry.mode { id = "json", name = "JSON", material = "data_object", shape = "pill", words = { "json", "jwt" },
  hint = "json {…}  ·  jwt a.b.c  ·  nothing: reads the clipboard", search = function(term)
    if term == "" then return { rows.note("json", "Paste JSON or a token", "Indented, on one line, or a JWT read", "data_object") } end
    local header, payload = codec.jwt(term)
    if header then
      local h, p = codec.json(header), codec.json(payload)
      return {
        row { id = "jwt:payload", name = (payload:gsub("%s+", " ")), description = "Payload  ·  the signature is not checked",
          material = "data_object", copy = p, preview = { text = p, title = "Payload" },
          run = function() return run.copy(p) end },
        row { id = "jwt:header", name = (header:gsub("%s+", " ")), description = "Header", material = "data_object", copy = h,
          preview = { text = h, title = "Header" }, run = function() return run.copy(h) end },
      }
    end
    local pretty, line = codec.json(term)
    if not pretty then return { rows.note("json", "Not JSON", term, "data_object") } end
    return {
      row { id = "json:pretty", name = "Indented", description = #pretty .. " bytes  ·  Return copies", material = "format_align_left",
        copy = pretty, preview = { text = pretty, title = "JSON" }, run = function() return run.copy(pretty) end },
      copied("json:line", line, "On one line", "remove"),
    }
  end }

registry.mode { id = "lorem", name = "Placeholder text", material = "notes", shape = "pill", words = { "lorem" },
  hint = "lorem 3  ·  paragraphs of placeholder text", search = function(term)
    local n = tonumber(term) or 1
    local text = codec.lorem(n)
    return { row { id = "lorem", name = text:sub(1, 80) .. "…", description = n .. " paragraph" .. (n == 1 and "" or "s") .. "  ·  Return copies",
      material = "notes", copy = text, preview = { text = text, title = "Lorem ipsum" }, run = function() return run.copy(text) end } }
  end }

registry.mode { id = "dice", name = "Dice", material = "casino", shape = "pill", words = { "dice", "roll", "rand", "random" },
  hint = "roll 2d6  ·  rand 1 100  ·  rand a b c", search = function(term)
    local count, sides = term:lower():match("^(%d*)d(%d+)$")
    local out = {}
    if sides then
      count, sides = tonumber(count) or 1, tonumber(sides)
      local total, each = 0, {}
      for i = 1, math.min(count, 100) do
        each[i] = password.pick(math.min(sides, 256))
        total = total + each[i]
      end
      out[1] = copied("dice", tostring(total), table.concat(each, " + ") .. "  ·  " .. term, "casino", tostring(total))
      return out
    end
    local low, high = term:match("^(%-?%d+)%s+(%-?%d+)$")
    if low then
      low, high = tonumber(low), tonumber(high)
      if high >= low then
        local span = high - low + 1
        local value = low + (span <= 256 and password.pick(span) - 1 or math.random(0, span - 1))
        return { copied("dice", tostring(value), ("A number from %d to %d"):format(low, high), "casino") }
      end
    end
    local choices = {}
    for word in term:gmatch("%S+") do choices[#choices + 1] = word end
    if #choices > 1 then
      return { copied("dice", choices[password.pick(#choices)], "One of " .. #choices, "casino") }
    end
    return { copied("dice", tostring(password.pick(6)), "One die  ·  roll 2d6, rand 1 100, rand a b c", "casino") }
  end }

registry.mode { id = "unicode", name = "Characters", material = "translate", shape = "pill", words = { "unicode", "char" },
  hint = "char é  ·  U+00E9  ·  a code point and back", search = function(term)
    local hex = term:match("^[Uu]%+(%x+)$") or term:match("^0[xX](%x+)$")
    if hex then
      local code = tonumber(hex, 16)
      if code and code <= 0x10FFFF then
        local char = utf8.char(code)
        return { copied("char", char, ("U+%04X  ·  Return copies"):format(code), "translate") }
      end
    end
    local out = {}
    for i, point in ipairs(codec.code_points(term)) do
      if i > 24 then break end
      out[#out + 1] = copied("char:" .. i, point[2], point[1], "translate")
    end
    if #out == 0 then out[1] = rows.note("char", "Type a character or U+1F600", "Its code point, or the other way", "translate") end
    return out
  end }

-- --------------------------------------------------------------------- qr --

-- The most a code in the preview pane can hold and still be read by a camera.
local QR_BYTES = 400

--- The code for `text`, built off the search, so typing never waits for it.
local function code_for(text)
  return rows.ask("qr", text, function(done)
    if #text > QR_BYTES then
      done({ error = "too long for a QR code" })
      return true
    end
    local job = qr.encode(text, "M", function(code, why)
      done(code and { svg = qr.svg(code), size = code.size } or { error = why })
    end)
    return { kill = job.cancel }
  end, { debounce_ms = 60 })
end

registry.mode { id = "qr", name = "QR code", material = "qr_code_2", shape = "pill", words = { "qr", "qrcode" },
  hint = "qr any text or address", search = function(term)
    if term == "" then return { rows.note("qr", "Type what the code should hold", "Up to " .. QR_BYTES .. " bytes", "qr_code_2") } end
    local made = code_for(term)
    if not made then return { rows.note("qr", "Drawing…", term, "qr_code_2") } end
    if made.error then return { rows.note("qr", "That will not fit", made.error, "qr_code_2") } end
    local svg = made.svg
    return { row {
      id = "qr", name = term, description = "A QR code  ·  Return copies the text", material = "qr_code_2", copy = term,
      preview = { svg = svg, title = "QR code", size = made.size }, auto_preview = true,
      run = function() return run.copy(term) end,
      actions = {
        { name = "Save as SVG", material = "save", run = function()
          local folder = rows.untilde(require("config").get("capture.folder"))
          local path = folder .. "/qr-" .. morf.time.format("%Y%m%d_%H-%M-%S") .. ".svg"
          morf.fs.write(path, svg, { parents = true })
          return run.copy(path)
        end },
        { name = "Copy the SVG", material = "content_copy", run = function() return run.copy(svg) end },
      },
    } }
  end }
