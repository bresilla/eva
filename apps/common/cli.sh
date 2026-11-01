# Sourced by the command-line tools of apps/. POSIX sh; nothing here needs a
# running shell. `apps` is the folder of the tree, set by whoever sources this.

# morf as a client: a child of a tool inherits MORF_APP, which aims `morf ipc`
# at a socket of its own.
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
    notify-send -a eva "$1" "${2:-}" || true
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

# The folder captures go to, with ~ expanded.
eva_captures() {
  folder=$(eva_setting capture.folder "$HOME/Pictures/Captures")
  case "$folder" in "~/"*) folder=$HOME/${folder#"~/"} ;; esac
  printf '%s' "$folder"
}
