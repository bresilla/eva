-- How current the system is: a NixOS generation and how old its nixpkgs is, read
-- from a fake root laid out as a real system is.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=100,height=100}
  morf.ipc.run=function(code) return load(code)() end
]]
test.before_each(function() test.load("../shell/init.lua",{source=HOST,size={200,200}}) end)
local function run(code) return test.ipc("run",code) end
local NOW=morf.time.time {year=2026,month=11,day=1,hour=12}

test.it("reads a generation from its link",function()
  test.eq(run("return require('updates_model').generation('system-41-link')"),41)
  test.eq(run("return require('updates_model').generation('nothing')"),nil)
end)
test.it("reads the date in a NixOS version",function()
  local at=run("return require('updates_model').version_date('26.05.20261031.fa13731')")
  test.eq(morf.time.format("%Y-%m-%d",at),"2026-10-31")
end)
test.it("reads when a flake.lock locked nixpkgs",function()
  local text=[[{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs_2"}},"nixpkgs_2":{"locked":{"lastModified":1790000000}}},"root":"root","version":7}]]
  test.eq(run(("return require('updates_model').flake_date(%q)"):format(text)),1790000000)
  test.eq(run("return require('updates_model').flake_date('nonsense')"),nil)
end)
test.it("reads a whole system from a root",function()
  local root=morf.env("XDG_CACHE_HOME").."/nix-root"
  morf.fs.mkdir(root.."/nix/var/nix/profiles",{parents=true})
  morf.fs.mkdir(root.."/run",{parents=true})
  morf.fs.mkdir(root.."/etc/nixos",{parents=true})
  morf.fs.symlink("system-41-link",root.."/nix/var/nix/profiles/system")
  morf.fs.symlink("/nix/store/abc-nixos-system-tron-26.05.20261031.fa13731",root.."/run/current-system")
  morf.fs.write(root.."/etc/nixos/flake.lock",[[{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"lastModified":]]
    ..tostring(NOW-20*86400)..[[}}},"root":"root"}]])
  local nix=run(("return require('updates_model').nix(%q,'',%d)"):format(root,NOW))
  test.eq(nix.generation,41) test.eq(nix.version,"26.05.20261031.fa13731") test.eq(nix.age,1) test.eq(nix.flake_age,20)
  local text=run(("local u=require('updates_model') return u.describe(u.nix(%q,'',%d))"):format(root,NOW))
  test.eq(text.text,"#41 20d") test.eq(text.tone,"warn") test.truthy(text.present)
  test.truthy(text.tooltip:find("generation 41",1,true)~=nil)
end)
test.it("says nothing on a machine without Nix",function()
  test.eq(run("return require('updates_model').nix('/nonexistent','',0)"),nil)
end)
test.it("reads this machine's real system when it has one",function()
  if not morf.fs.exists("/run/current-system") then test.note("no NixOS here") return end
  local nix=run("return require('updates_model').nix('','')")
  test.truthy(nix.nix) test.truthy(nix.generation==nil or nix.generation>0)
end)
test.it("counts packages elsewhere",function()
  local out=run("return require('updates_model').describe(nil,{total=3,managers={'pacman'}})")
  test.eq(out.text,"3") test.truthy(out.present)
  test.falsy(run("return require('updates_model').describe(nil,{total=0,managers={}})").present)
end)
