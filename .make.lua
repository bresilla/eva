-- eva's tasks, as recipes.
--
--   make          the recipes, with what each of them says it does
--   make test     every spec, against morf on PATH (MORF names another)
--   make check    the shell, lock screen and greeter load under `morf check`
--   make build    the Nix package, into ./result
--
-- At an oslo prompt in this directory `make` is enough; everywhere else it is `oslo make`.
-- CI has no oslo, so it calls tools/test.sh, tools/check.sh and nix itself.

local make = oslo.make

make.recipe{ name = "test", desc = "every spec, in parallel shards",
             run = function() sh.sh("tools/test.sh") end }
make.alias("t", "test")

make.recipe{ name = "check", desc = "the shell, lock screen and greeter load under morf check",
             run = function() sh.sh("tools/check.sh") end }

make.recipe{ name = "build", desc = "the Nix package, into ./result",
             run = function() sh.nix("build", ".#eva") end }
