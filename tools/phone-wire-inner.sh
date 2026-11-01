#!/bin/sh
# Inside tools/phone-wire.sh's private bus: both buses are that one, every
# service is an echo, and dbus-monitor writes what crosses it.
set -eu
morf=${MORF:-morf}
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
out=$PHONE_WIRE_OUT
pids=""
for name in org.freedesktop.ModemManager1 org.mobian_project.CallAudio org.sigxcpu.Feedback; do
  dbus-test-tool echo --session --name="$name" & pids="$pids $!"
done
dbus-monitor --session "type='method_call'" > "$out" & pids="$pids $!"
sleep 1
"$morf" test tools/phone_wire_spec.lua > "$out.tap" 2>&1 || { cat "$out.tap"; exit 1; }
sleep 1
kill $pids 2>/dev/null || true

# The body of the method call to `member`, one line.
body() {
  awk -v want="member=$1\$" '
    /^(method call|signal|method return|error)/ { on = ($0 ~ want) ; next }
    on { gsub(/^ +/, ""); gsub(/ +/, " "); printf "%s ", $0 }
  ' "$out"
}

status=0
want() {
  got=$(body "$1")
  case "$got" in
    *"$2"*) echo "ok   $1: $2" ;;
    *) echo "FAIL $1: wanted [$2], got [$got]"; status=1 ;;
  esac
}

# Each line is what the XML declares for that method.
want CreateCall 'array [ dict entry( string "number" variant string "+3161234" ) ]'
want Deflect 'string "+3199"'
want SendDtmf 'string "5"'
want CallWaitingSetup 'boolean true'
want DeleteCall 'object path "/org/freedesktop/ModemManager1/Call/1"'
want Create 'string "number" variant string "+3161234"'
want Create 'string "delivery-report-request" variant boolean true'
want Create 'string "text" variant string "hello"'
want Delete 'object path "/org/freedesktop/ModemManager1/SMS/1"'
want SetChannels 'array [ struct { uint32 4370 uint32 4383 } ]'
want SendPin 'string "1234"'
want SendPuk 'string "12345678" string "1234"'
want EnablePin 'string "1234" boolean true'
want ChangePin 'string "1234" string "4321"'
want SelectMode 'uint32 1'
want EnableSpeaker 'boolean true'
want MuteMic 'boolean true'
want TriggerFeedback 'string "org.eva.Shell" string "phone-incoming-call" array [ dict entry( string "important" variant boolean true ) ] int32 0'
want EndFeedback 'uint32 7'
for member in Accept Hangup JoinMultiparty LeaveMultiparty HoldAndAccept HangupAndAccept HangupAll Transfer; do
  grep -q "member=$member\$" "$out" && echo "ok   $member: sent, no arguments" \
    || { echo "FAIL $member: never sent"; status=1; }
done
exit "$status"
