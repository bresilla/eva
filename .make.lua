-- eva's tasks, as recipes.
--
--   make          the recipes, with what each of them says it does
--   make test     every spec, against morf on PATH (MORF names another)
--   make check    the shell, lock screen, greeter and tools load under `morf check`
--   make app NAME a tool of apps/ as a program of its own
--   make build    the Nix package, into ./result
--
-- At an oslo prompt in this directory `make` is enough; everywhere else it is `oslo make`.
-- CI has no oslo, so it calls tools/test.sh, tools/check.sh and nix itself.

local make = oslo.make

make.recipe{ name = "test", desc = "every spec, in parallel shards",
             run = function() sh.sh("tools/test.sh") end }
make.alias("t", "test")

make.recipe{ name = "check", desc = "the shell, lock screen, greeter and tools load under morf check",
             run = function() sh.sh("tools/check.sh") end }

make.recipe{ name = "phone-wire", desc = "the phone layer's D-Bus types on a real bus, against the daemons' XML",
             run = function() sh.sh("tools/phone-wire.sh") end }

make.recipe{ name = "see", desc = "a scenario of tools/see/ on a virtual screen, into .see/",
             run = function(args) sh.bash("tools/see.sh", args[1] or "quick") end }

make.recipe{ name = "app", desc = "a tool of apps/ as a program of its own (make app draw)",
             run = function(args) sh.sh("apps/launch", args[1] or "draw") end }

make.recipe{ name = "build", desc = "the Nix package, into ./result",
             run = function() sh.nix("build", ".#eva") end }
