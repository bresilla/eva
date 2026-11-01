#!/bin/sh
# Every typed call of the phone layer on a real bus. The shipped specs stop at
# a table of Lua; this goes through the engine's encoder and a dbus-daemon, and
# checks the wire types against what the daemons' XML declares. It says nothing
# of what a modem does with them.
#
#   tools/phone-wire.sh [OUT]       OUT keeps the monitor's log
#
# MORF is the binary (default: morf on PATH).
set -eu
cd "$(dirname "$0")/.."
export PHONE_WIRE_OUT="${1:-$(mktemp "${TMPDIR:-/tmp}/phone-wire.XXXXXX")}"
exec dbus-run-session -- sh tools/phone-wire-inner.sh
