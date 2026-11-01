# Turns the session's choices into a kanata configuration, as root, for a service
# that cannot write it. Only the words below get through: a choices file is the
# person's to write, so nothing in it reaches the configuration as text. Exits
# non-zero with nothing chosen, so no keyboard is taken for nothing.
#
#   remap-render CHOICES OUTPUT [DEVICE...]
choices=$1
output=$2
shift 2
devices=""
for device in "$@"; do devices="$devices \"$device\""; done

field() { jq -r --arg name "$1" '.[$name] // empty | tostring' "$choices" 2>/dev/null || true; }

number() {
  value=$(field "$1")
  case "$value" in
    '' | *[!0-9]*) echo "$2" ;;
    *) if [ "$value" -lt 50 ] || [ "$value" -gt 1000 ]; then echo "$2"; else echo "$value"; fi ;;
  esac
}

tap=$(number tap 200)
hold=$(number hold 200)
source=""
action=""

add() {
  source="$source $1"
  action="$action $2"
}

case "$(field caps)" in
  escape) add caps esc ;;
  control) add caps lctl ;;
  tap_escape_hold_control) add caps '(tap-hold $tap $hold esc lctl)' ;;
  hyper) add caps '@hyper' ;;
  tap_escape_hold_hyper) add caps '(tap-hold $tap $hold esc @hyper)' ;;
esac

case "$(field hyper)" in
  right_alt) add ralt '@hyper' ;;
  right_control) add rctl '@hyper' ;;
  menu) add comp '@hyper' ;;
esac

if [ "$(field swap_alt_super)" = true ]; then
  add lalt lmet
  add lmet lalt
fi

if [ "$(field home_row)" = true ]; then
  add a '(tap-hold $tap $hold a lmet)'
  add s '(tap-hold $tap $hold s lalt)'
  add d '(tap-hold $tap $hold d lsft)'
  add f '(tap-hold $tap $hold f lctl)'
  add j '(tap-hold $tap $hold j rctl)'
  add k '(tap-hold $tap $hold k rsft)'
  add l '(tap-hold $tap $hold l ralt)'
  add ';' '(tap-hold $tap $hold ; rmet)'
fi

mkdir -p "$(dirname "$output")"
chmod 0755 "$(dirname "$output")"
if [ -z "$source" ]; then
  rm -f "$output"
  exit 1
fi

only=""
if [ -n "$devices" ]; then only="linux-dev ($devices)"; fi

cat > "$output.new" <<EOF
(defcfg
  process-unmapped-keys yes
  $only
  linux-continue-if-no-devs-found yes)
(defvar tap $tap hold $hold)
(defalias hyper (multi lctl lalt lsft lmet))
(defsrc$source)
(deflayer base$action)
EOF
chmod 0644 "$output.new"
mv "$output.new" "$output"
