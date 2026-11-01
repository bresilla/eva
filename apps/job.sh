# Sourced by a tool's cli, after apps/common/cli.sh. POSIX sh.

# The tool's own windowless job, `eva_tool_job TOOL ARGS`, beside its window:
# prints its words and returns its status (lib/util/job.lua).
eva_tool_job() {
  tool=$1
  shift
  out=$(eva_private_file job)
  EVA_JOB_OUT=$out sh "$apps/launch" "$tool" "$@" > /dev/null 2>&1 || true
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
