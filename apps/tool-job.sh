# Sourced by a tool's cli after apps/common/cli.sh: a job of that tool's own
# app.lua, beside any window of it. lib/shell/tool_job.lua is the other end.

# `apps/launch TOOL ARGS`: prints its answer to the byte and returns its status.
eva_tool_job() {
  out=$(eva_private_file job)
  EVA_JOB_OUT=$out sh "$apps/launch" "$@" > /dev/null 2>&1 || true
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
