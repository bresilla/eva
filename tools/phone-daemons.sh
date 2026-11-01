#!/bin/sh
# The phone layer against the real daemons that run without hardware, on a
# private session bus that can start them.
#
#   FEEDBACKD=/path/to/feedbackd tools/phone-daemons.sh
#
# FEEDBACKD is the package, its folder holding share/dbus-1/services. MORF is
# the binary (default: morf on PATH).
set -eu
cd "$(dirname "$0")/.."
: "${FEEDBACKD:?name the feedbackd package}"
XDG_DATA_DIRS="$FEEDBACKD/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export XDG_DATA_DIRS
exec dbus-run-session -- "${MORF:-morf}" test tools/phone_daemon_spec.lua
