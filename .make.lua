-- eva's tasks, as recipes.
--
--   make          the recipes, with what each of them says it does
--   make test     every spec, against morf on PATH (MORF names another)
--   make check    the shell, lock screen and greeter load under `morf check`
--   make build    the Nix package, into ./result
--
-- At an oslo prompt in this directory `make` is enough; everywhere else it is `oslo make`.
-- CI has no oslo, so it calls tools/test.sh and nix itself.

local make = oslo.make

make.recipe{ name = "test", desc = "every spec, in parallel shards",
             run = function() sh.sh("tools/test.sh") end }
make.alias("t", "test")

make.recipe{
  name = "check",
  desc = "the shell, lock screen and greeter load under morf check",
  run = function()
    for _, role in ipairs { "shell", "lock", "greet" } do
      local command = { "env", "EVA_DRY_RUN=1", "morf", "check", role .. "/init.lua",
                        "--no-dbus", "--isolate", "--after", "0" }
      if role == "lock" then
        for _, word in ipairs { "--", "window", "preview" } do command[#command + 1] = word end
      end
      assert(oslo.run(command).ok, role .. " did not load cleanly")
    end
  end,
}

make.recipe{ name = "build", desc = "the Nix package, into ./result",
             run = function() sh.nix("build", ".#eva") end }
