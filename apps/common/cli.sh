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

# The Settings window of the running shell, on page $1.
eva_settings() {
  if ! eva_shell_up; then
    eva_say "the shell is not running, and Settings is a part of it"
    return 1
  fi
  eva_ipc settings "$1" > /dev/null
}

# The answer of a verb alone, unwrapped from morf's JSON reply.
eva_answer() {
  sed -e 's/.*"result":\[*//' -e 's/\]*}[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
}

# Runs a job, which answers in the file EVA_JOB_OUT names (lib/util/job.lua):
# prints its answer to the byte and returns its status.
eva_relay() {
  out=$(eva_private_file job)
  EVA_JOB_OUT=$out "$@" > /dev/null 2>&1 || true
  code=$(head -n 1 "$out" 2>/dev/null || true)
  if [ "${code:-1}" = 0 ]; then
    tail -n +2 "$out"
    rm -f "$out"
    return 0
  fi
  words=$(tail -n +2 "$out" 2>/dev/null || true)
  rm -f "$out"
  eva_say "${words:-the job did not finish}"
  return 1
}

# A command of the shell's own code with no shell running (apps/common/job).
eva_job() {
  eva_relay "${MORF:-morf}" app "$apps/common/job/app.lua" -- "$@"
}

# A tool's own job with no window, `eva_tool_job TOOL ARGS`.
eva_tool_job() {
  tool=$1
  shift
  eva_relay sh "$apps/launch" "$tool" "$@"
}

# The same, with this command's stdin handed over in a private file.
eva_tool_job_stdin() {
  EVA_JOB_IN=$(eva_private_file in)
  export EVA_JOB_IN
  cat > "$EVA_JOB_IN"
  status=0
  eva_tool_job "$@" || status=$?
  rm -f "$EVA_JOB_IN"
  return "$status"
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

# The capture tool's socket, beside the shell's.
eva_capture_socket() {
  display=${WAYLAND_DISPLAY:-wayland-0}
  printf '%s-screenshot' "${display##*/}"
}

eva_capture_up() {
  eva_morf -i "$(eva_capture_socket)" ipc verbs > /dev/null 2>&1
}

eva_capture_call() {
  eva_morf -i "$(eva_capture_socket)" ipc call "$@"
}

# The first frame of recording $1 in a private file, when ffmpeg can take one.
eva_poster() {
  eva_has ffmpeg || return 1
  frame=$(eva_private_file png)
  if ffmpeg -y -loglevel quiet -i "$1" -frames:v 1 "$frame"; then
    printf '%s' "$frame"
    return 0
  fi
  rm -f "$frame"
  return 1
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
