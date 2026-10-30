# Unlock pattern

Pattern authentication is off by default. Setting
`programs.eva.pattern.enable = true` installs `morf-pattern` and enables it for
greetd and `morf-lock`. A pattern has far less entropy than a password; enable
it only where that trade-off is acceptable. Enroll locally with `sudo morf-pattern setup USER` (Enter
skips), or use `set` to replace a pattern and `clear` to remove it. An existing
pattern is preserved by `setup`. The OS installer can invoke `setup` immediately
after `passwd`; no secret belongs in a Nix option or installation manifest.

The prompt hides input and asks for confirmation. Dots are numbered `123 / 456 /
789`: connect 4–9 distinct neighbouring dots, including diagonals. `123654` is
valid; `123456` is rejected because 3 and 4 are not neighbours. The lock and login
screens enforce the same rule. Password login remains available.

Only a randomly salted yescrypt hash is stored, under `/var/lib/morf/pattern`
(root-only directory and files). `/etc/morf/pattern/USER` is an empty, public
enrollment marker so both screens know when to offer patterns. The compiled
setuid verifier accepts an unprivileged caller only for their own account;
enrollment/removal require root. Every five failed pattern attempts trigger a
cooldown that grows each time (30 s, 1 min, 5 min, 15 min), shared by login and
lock. After twenty-five failures patterns stay disabled until a password login
through greetd (or `sudo morf-pattern reset USER`); strikes fade after a day
without new ones. The account password remains in
the system password store; it is never copied or recovered from the pattern.

On non-NixOS systems, `sudo helpers/pattern/install.sh USER` builds the helper,
preserves the existing PAM password/account checks, and starts enrollment.
It requires a C compiler, libxcrypt headers and Python 3. NixOS uses the module
instead of this imperative installer. Leaving `programs.eva.pattern.enable`
false keeps the integration off without changing the account password.

`test_pattern.py` exercises the verifier and the CLI inside a private user
namespace, never live PAM: `python3 helpers/pattern/test_pattern.py` (it needs
`/usr/bin/cc` with libxcrypt and PAM headers).
