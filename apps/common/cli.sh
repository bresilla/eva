# Sourced by the command-line tools of apps/. POSIX sh; nothing here needs a
# running shell. `apps` is the folder of the tree, set by whoever sources this.

# morf as a client, outside any tool.
eva_morf() {
  env -u MORF_APP "${MORF:-morf}" "$@"
}

# Whether the shell answers on this display.
eva_shell_up() {
  eva_morf ipc verbs > /dev/null 2>&1
}

eva_ipc() {
  eva_morf ipc call "$@"
}

# The answer of a verb alone, unwrapped from morf's JSON reply.
eva_answer() {
  sed -e 's/.*"result":\[*//' -e 's/\]*}[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
}

# A command of the shell's own code with no shell running (apps/common/job):
# prints its words and returns its status.
eva_job() {
  out=$(eva_private_file job)
  EVA_JOB_OUT=$out "${MORF:-morf}" app "$apps/common/job/app.lua" -- "$@" > /dev/null 2>&1 || true
  code=$(head -n 1 "$out" 2>/dev/null || true)
  words=$(tail -n +2 "$out" 2>/dev/null || true)
  rm -f "$out"
  if [ "${code:-1}" = 0 ]; then
    if [ -n "$words" ]; then printf '%s\n' "$words"; fi
    return 0
  fi
  eva_say "${words:-the job did not finish}"
  return 1
}

eva_dry() {
  [ -n "${EVA_DRY_RUN:-}" ] && [ "$EVA_DRY_RUN" != 0 ]
}

eva_say() {
  printf 'eva: %s\n' "$*" >&2
}

eva_has() {
  command -v "$1" > /dev/null 2>&1
}

# Which compositor this session has: hyprland, sway or other.
eva_compositor() {
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then echo hyprland
  elif [ -n "${SWAYSOCK:-}" ]; then echo sway
  else echo other
  fi
}

# A notification, through the shell when it answers, else through notify-send.
eva_notify() {
  if eva_shell_up; then
    eva_ipc notify "$1" "${2:-}" low eva > /dev/null 2>&1 || true
  elif eva_has notify-send; then
    notify-send -a eva "$1" "${2:-}" 2>/dev/null || true
  fi
}

# The tree's own state folder, the same for every tool and for the shell.
eva_state() {
  printf '%s/eva' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# One setting of the shell's file, or the default given, for a flat string key.
eva_setting() {
  file=${EVA_SETTINGS:-}
  [ -n "$file" ] || file=$(cat "$(eva_state)/settings-path" 2>/dev/null || true)
  value=""
  if [ -n "$file" ] && [ -r "$file" ] && eva_has jq; then
    value=$(jq -r --arg path "$1" 'getpath($path / ".") // empty' "$file" 2>/dev/null || true)
  fi
  printf '%s' "${value:-$2}"
}

# A new private file for a picture that must not stay, with extension $1.
eva_private_file() {
  folder=${XDG_RUNTIME_DIR:-/tmp}/eva
  mkdir -p "$folder"
  chmod 700 "$folder"
  mktemp "$folder/capture.XXXXXX.$1"
}

# The focused window as grim and slurp spell an area, X,Y WxH.
eva_window_area() {
  case "$(eva_compositor)" in
    hyprland)
      hyprctl -j activewindow | jq -er '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
      ;;
    sway)
      swaymsg -r -t get_tree | jq -er '
        .. | objects | select(.focused? == true and (.pid? != null))
        | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"' | head -n 1 | grep .
      ;;
    *) return 1 ;;
  esac
}

# The focused output's name.
eva_focused_output() {
  case "$(eva_compositor)" in
    hyprland) hyprctl -j monitors | jq -er '.[] | select(.focused) | .name' ;;
    sway) swaymsg -r -t get_outputs | jq -er '.[] | select(.focused) | .name' ;;
    *)
      eva_say "this compositor is not known"
      return 1
      ;;
  esac
}

# A notification titled $3 for file $2 with thumbnail $1, offering Open, and
# Edit through the tool at $4 when one is given. Waits for the answer: run it in
# the background.
eva_thumbnail() {
  if ! eva_has notify-send; then
    eva_notify "$3" "$2"
    return 0
  fi
  if [ -n "${4:-}" ]; then
    answer=$(notify-send --app-name=eva --icon="$1" --action=open=Open --action=edit=Edit \
      --wait "$3" "$2" 2>/dev/null || true)
  else
    answer=$(notify-send --app-name=eva --icon="$1" --action=open=Open \
      --wait "$3" "$2" 2>/dev/null || true)
  fi
  case "$answer" in
    open) if eva_has xdg-open; then xdg-open "$2"; fi ;;
    edit) sh "$4" --edit-file "$2" ;;
  esac
}

# The folder captures go to, with ~ expanded.
eva_captures() {
  folder=$(eva_setting capture.folder "$HOME/Pictures/Captures")
  case "$folder" in "~/"*) folder=$HOME/${folder#"~/"} ;; esac
  printf '%s' "$folder"
}
