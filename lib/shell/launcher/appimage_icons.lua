-- The icon an AppImage carries (its .DirIcon), read once without running it and
-- kept in the cache. The packed filesystem starts where the ELF runtime's section
-- headers end; `unsquashfs` takes the icon from there. Without `unsquashfs` an
-- AppImage keeps the plain glyph.
--
--   local icons = require("lib.shell.launcher.appimage_icons")
--   icons.cached(path)        -- the kept icon's path, false when it has none, nil unknown
--   icons.fetch(path, done)   -- reads it in the background; done(icon_path or nil)
local morf = require("morf")
local M = {}

M.SCRIPT = [[
file=$1 out=$2
command -v unsquashfs >/dev/null 2>&1 || exit 3
[ "$(od -An -c -N 4 -- "$file" | tr -d ' ')" = 177ELF ] || exit 1
class=$(od -An -t u1 -j 4 -N 1 -- "$file" | tr -d ' ')
if [ "$class" = 2 ]; then
  shoff=$(od -An -t u8 -j 40 -N 8 -- "$file" | tr -d ' ')
  set -- $(od -An -t u2 -j 58 -N 4 -- "$file")
else
  shoff=$(od -An -t u4 -j 32 -N 4 -- "$file" | tr -d ' ')
  set -- $(od -An -t u2 -j 46 -N 4 -- "$file")
fi
offset=$((shoff + $1 * $2))
root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
name=.DirIcon
for _ in 1 2 3 4; do
  unsquashfs -q -n -f -o "$offset" -d "$root/fs" "$file" "$name" >/dev/null 2>&1 || exit 1
  [ -L "$root/fs/$name" ] || break
  link=$(readlink "$root/fs/$name")
  case $link in
    /*) name=${link#/} ;;
    *) name=$(dirname "$name")/$link ;;
  esac
  name=${name#./}
done
[ -f "$root/fs/$name" ] && [ ! -L "$root/fs/$name" ] || exit 1
head=$(od -An -c -N 5 -- "$root/fs/$name" | tr -d ' ')
case $head in
  211PNG*) ext=png ;;
  \<*) ext=svg ;;
  *) exit 1 ;;
esac
mkdir -p "$(dirname "$out")"
cp -- "$root/fs/$name" "$out.$ext.part" && mv -- "$out.$ext.part" "$out.$ext"
echo "$out.$ext"
]]

local queue, busy, missing = {}, false, false

local function folder() return morf.paths.cache("appimage-icons") end

-- One name per file and version of it: its path, size and time.
local function key(path)
  local ok, stat = pcall(morf.fs.stat, path)
  stat = ok and type(stat) == "table" and stat or {}
  return morf.encoding.sha256(path .. ":" .. tostring(stat.size or "") .. ":"
    .. tostring(stat.mtime or stat.modified or ""))
end

function M.cached(path)
  local base = folder() .. "/" .. key(path)
  for _, ext in ipairs { ".png", ".svg" } do
    if morf.fs.exists(base .. ext) then return base .. ext end
  end
  if morf.fs.exists(base .. ".none") then return false end
  return nil
end

local function next_job()
  if busy or #queue == 0 then return end
  local job = table.remove(queue, 1)
  busy = true
  local base = folder() .. "/" .. key(job.path)
  morf.process.run({ "sh", "-c", M.SCRIPT, "appimage-icon", job.path, base },
    { timeout_ms = 20000, max_output = 4096 }, function(result)
      busy = false
      local found = result and result.ok and tostring(result.stdout or ""):match("^%s*(.-)%s*$") or ""
      if found ~= "" and morf.fs.exists(found) then
        job.done(found)
      else
        if result and result.code == 3 then
          missing = true
        else
          pcall(morf.fs.write, base .. ".none", "")
        end
        job.done(nil)
      end
      next_job()
    end)
end

function M.fetch(path, done)
  if missing then return done(nil) end
  for _, job in ipairs(queue) do
    if job.path == path then return end
  end
  queue[#queue + 1] = { path = path, done = done }
  next_job()
end

return M
