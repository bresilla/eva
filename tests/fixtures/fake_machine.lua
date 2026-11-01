-- A machine in a folder for the specs: the /proc, /sys and /etc that
-- lib.services.sysinfo and the system tools read, at `root`.
--
--     local machine = load(morf.fs.read("tests/fixtures/fake_machine.lua"))()
--     local root = machine.build(folder, { processes = 30 })
--     machine.tick(root, 2)
local morf = morf

local M = {}

local function put(root, path, text)
  morf.fs.write(root .. path, text, { parents = true })
end

local function stat_line(pid, name, state, ticks, pages)
  return ("%d (%s) %s 1 1 1 0 -1 0 0 0 0 0 %d 0 0 0 20 0 1 0 100 1000 %d\n"):format(pid, name, state, ticks, pages)
end

-- One process: `spec` is `{ pid, name, command, ticks, pages, uid, state }`.
function M.process(root, spec)
  local base = "/proc/" .. spec.pid
  put(root, base .. "/stat", stat_line(spec.pid, spec.name, spec.state or "S", spec.ticks or 0, spec.pages or 256))
  put(root, base .. "/cmdline", spec.command and (spec.command:gsub(" ", "\0") .. "\0") or "")
  put(root, base .. "/status", ("Name:\t%s\nUid:\t%d\t%d\t%d\t%d\nPPid:\t1\nThreads:\t%d\nVmSwap:\t%d kB\n"):format(
    spec.name, spec.uid or 1000, spec.uid or 1000, spec.uid or 1000, spec.uid or 1000, spec.threads or 3, spec.swap or 0))
end

--- Disk counters for a process.
function M.io(root, pid, read, written)
  put(root, "/proc/" .. pid .. "/io", ("rchar: 1\nwchar: 1\nsyscr: 1\nsyscw: 1\nread_bytes: %d\nwrite_bytes: %d\ncancelled_write_bytes: 0\n")
    :format(read, written))
end

--- Links fd `fd` of a process to `target`.
function M.fd(root, pid, fd, target)
  morf.fs.mkdir(root .. "/proc/" .. pid .. "/fd")
  morf.fs.symlink(target, root .. "/proc/" .. pid .. "/fd/" .. fd)
end

--- The kernel's table of sockets for a process.
function M.sockets(root, pid, protocol, text)
  put(root, "/proc/" .. pid .. "/net/" .. protocol, "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n" .. text)
end

--- The fdinfo of fd `fd` of a process.
function M.fdinfo(root, pid, fd, text)
  put(root, "/proc/" .. pid .. "/fdinfo/" .. fd, text)
end

-- CPU counters of two cores: `busy` jiffies each.
local function cpu_stat(root, busy, idle)
  put(root, "/proc/stat", ("cpu  %d 0 0 %d 0 0 0 0 0 0\ncpu0 %d 0 0 %d 0 0 0 0 0 0\ncpu1 %d 0 0 %d 0 0 0 0 0 0\n")
    :format(busy * 2, idle * 2, busy, idle, busy, idle))
end

--- Moves the machine on by `step` samples.
function M.tick(root, step)
  cpu_stat(root, 100 + step * 40, 100 + step * 60)
  put(root, "/proc/net/dev", ("Inter-|   Receive\n face |bytes\n    lo: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n  eth0: %d 10 0 0 0 0 0 0 %d 10 0 0 0 0 0 0\n")
    :format(step * 2048000, step * 1024000))
  put(root, "/proc/diskstats", ("259 0 nvme0n1 10 0 %d 0 10 0 %d 0 0 %d 0\n259 1 nvme0n1p1 10 0 %d 0 10 0 %d 0 0 0 0\n")
    :format(step * 2000, step * 4000, step * 100, step * 2000, step * 4000))
end

--- A machine at `root`: `options.processes` beyond the named few, `sensors`
--- false for none. Returns `root`.
function M.build(root, options)
  options = options or {}
  morf.fs.mkdir(root .. "/proc")
  put(root, "/proc/cpuinfo", "processor\t: 0\nmodel name\t: Intel(R) Core(TM) i7-11800H CPU @ 2.30GHz\ncpu MHz\t\t: 2300.0\nflags\t\t: vmx\n\nprocessor\t: 1\nmodel name\t: Intel(R) Core(TM) i7-11800H CPU @ 2.30GHz\ncpu MHz\t\t: 2400.0\nflags\t\t: vmx\n")
  put(root, "/proc/meminfo", "MemTotal:       16000000 kB\nMemFree:         4000000 kB\nMemAvailable:    8000000 kB\nBuffers:          100000 kB\nCached:          2000000 kB\nSwapTotal:       4000000 kB\nSwapFree:        3000000 kB\nShmem:            100000 kB\nDirty:              1000 kB\nCommitted_AS:    9000000 kB\nCommitLimit:    12000000 kB\n")
  put(root, "/proc/loadavg", "0.52 0.41 0.30 2/318 4242\n")
  put(root, "/proc/uptime", "93784.12 100.00\n")
  put(root, "/proc/mounts", "/dev/nvme0n1p1 / ext4 rw 0 0\nproc /proc proc rw 0 0\n")
  put(root, "/proc/swaps", "Filename Type Size Used Priority\n")
  put(root, "/proc/net/route", "Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\neth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n")
  put(root, "/proc/sys/kernel/osrelease", "6.18.57\n")
  put(root, "/proc/sys/kernel/hostname", "fakebox\n")
  put(root, "/etc/passwd", "root:x:0:0:root:/root:/bin/sh\nada:x:1000:100:Ada:/home/ada:/bin/sh\n")
  put(root, "/etc/os-release", 'NAME="FakeOS"\nID=fakeos\nPRETTY_NAME="FakeOS 26.05"\nVERSION_ID="26.05"\n')
  put(root, "/sys/block/nvme0n1/size", "2000000\n")
  put(root, "/sys/block/nvme0n1/removable", "0\n")
  put(root, "/sys/block/nvme0n1/queue/rotational", "0\n")
  put(root, "/sys/block/nvme0n1/device/model", "Fake NVMe 1TB\n")
  put(root, "/sys/block/nvme0n1/nvme0n1p1/size", "1000000\n")
  put(root, "/sys/class/net/eth0/address", "aa:bb:cc:dd:ee:ff\n")
  put(root, "/sys/class/net/eth0/operstate", "up\n")
  put(root, "/sys/class/net/eth0/speed", "1000\n")
  put(root, "/sys/class/net/eth0/device/uevent", "\n")
  put(root, "/sys/class/drm/card0/device/vendor", "0x1002\n")
  put(root, "/sys/class/drm/card0/device/device", "0x73ff\n")
  put(root, "/sys/class/drm/card0/device/uevent", "DRIVER=amdgpu\nPCI_SLOT_NAME=0000:03:00.0\n")
  put(root, "/sys/class/drm/card0/device/gpu_busy_percent", "42\n")
  put(root, "/sys/class/drm/card0/device/mem_info_vram_used", "1073741824\n")
  put(root, "/sys/class/drm/card0/device/mem_info_vram_total", "8589934592\n")
  if options.sensors ~= false then
    put(root, "/sys/class/hwmon/hwmon0/name", "coretemp\n")
    put(root, "/sys/class/hwmon/hwmon0/temp1_input", "61000\n")
    put(root, "/sys/class/hwmon/hwmon0/temp1_label", "Package id 0\n")
    put(root, "/sys/class/hwmon/hwmon0/temp1_crit", "100000\n")
    put(root, "/sys/class/hwmon/hwmon1/name", "dell_smm\n")
    put(root, "/sys/class/hwmon/hwmon1/fan1_input", "3200\n")
    put(root, "/sys/class/hwmon/hwmon1/fan1_label", "Processor Fan\n")
    put(root, "/sys/class/hwmon/hwmon1/fan1_max", "6400\n")
  end
  M.process(root, { pid = 1, name = "systemd", command = "/sbin/init splash", uid = 0, ticks = 50, pages = 2048 })
  M.process(root, { pid = 2, name = "kthreadd", ticks = 1, pages = 0, uid = 0 })
  M.process(root, { pid = 700, name = "firefox", command = "/usr/bin/firefox --new-window https://example.test", ticks = 400, pages = 90000 })
  M.process(root, { pid = 701, name = "Zed", command = "/usr/bin/zed /home/ada/notes", ticks = 100, pages = 40000 })
  M.process(root, { pid = 702, name = "alacritty", command = "alacritty -e btop", ticks = 20, pages = 8000 })
  for index = 1, options.processes or 0 do
    M.process(root, { pid = 1000 + index, name = "worker" .. index, command = "/opt/worker --id " .. index, ticks = index, pages = 100 + index })
  end
  M.tick(root, 1)
  return root
end

return M
