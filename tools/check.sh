#!/bin/sh
# The shell, lock screen, greeter and every tool of apps/, each loaded headless
# by `morf check`: no errors, and an engine that meets morf.lua.
#
# MORF is the binary (default: morf on PATH).
set -eu
cd "$(dirname "$0")/.."
morf=${MORF:-morf}
for role in shell lock greet; do
  set -- "$role/init.lua" --no-dbus --isolate --after 0
  [ "$role" = lock ] && set -- "$@" -- window preview
  EVA_DRY_RUN=1 "$morf" check "$@"
done
for app in apps/*/app.lua apps/common/job/app.lua; do
  EVA_DRY_RUN=1 "$morf" check "$app" --no-dbus --isolate --after 0
done
# The capture tool past its first order: the panel up, then the selection, and
# at rest on standby.
EVA_DRY_RUN=1 "$morf" check apps/screenshot/app.lua --no-dbus --isolate --after 800 -- capture open
EVA_DRY_RUN=1 "$morf" check apps/screenshot/app.lua --no-dbus --isolate --after 800 -- screenshot screen
EVA_DRY_RUN=1 "$morf" check apps/screenshot/app.lua --no-dbus --isolate --after 800 -- standby
