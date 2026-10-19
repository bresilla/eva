-- eva's directory environment. Loaded when you `cd` here, unloaded when you leave.

-- The flake's dev shell: morf, at the release eva is written against.
oslo.direnv.nix_develop()

-- A token in the environment is a token in every child process, and nothing in here needs it.
oslo.env.unset("GITHUB_TOKEN")
