#!/usr/bin/env bash
# runners/direct.sh — the default runner: run the command right here, detached in the background.
# Called via bin/tinker-run (same interface). Job files live in
#   projects/<P>/jobs/<JOB_ID>/   (with --project)   or   state/jobs/<JOB_ID>/   (without)
# containing: cmd.sh (the command) · run.sh (wrapper) · pid · log · exit (exit code, when finished).
# --vram / --class are recorded but ignored: a direct job just runs (one machine, no scheduling).
#
# status exit codes: 0 done · 1 failed · 2 running · 3 pending · 4 missing · 64 usage
set -euo pipefail
_s=${BASH_SOURCE[0]}
while [ -L "$_s" ]; do _t=$(readlink "$_s"); case "$_t" in /*) _s=$_t ;; *) _s=$(dirname "$_s")/$_t ;; esac; done
TL_SELF=$_s
# shellcheck source=bin/_common.sh
. "$(cd "$(dirname "$_s")" && pwd -P)/../bin/_common.sh"

usage() { echo "usage: tinker-run submit [--project P] [--name tag] [--vram GB] [--class tag] [--cwd dir] --cmd '<command>' | status <JOB_ID> | log <JOB_ID>" >&2; exit 64; }

find_job() {  # find_job <id> → prints job dir
  local id=$1 d
  case "$id" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  for d in "$TINKER_HOME/state/jobs/$id" "$PROJECTS_DIR"/*/jobs/"$id"; do
    [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

submit() {
  local project="" name="job" vram="0" class="default" cwd=$PWD cmd=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project=${2:?}; shift 2 ;;
      --name) name=${2:?}; shift 2 ;;
      --vram) vram=${2:?}; shift 2 ;;
      --class) class=${2:?}; shift 2 ;;
      --cwd) cwd=${2:?}; shift 2 ;;
      --cmd) cmd=${2:?}; shift 2 ;;
      --exclusive) shift ;;                    # queue-only flags: accepted, ignored here
      --priority|--est) shift 2 ;;
      *) echo "direct: unknown arg: $1" >&2; usage ;;
    esac
  done
  [ -n "$cmd" ] || { echo "direct: --cmd is required" >&2; usage; }
  name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-')
  local base
  if [ -n "$project" ]; then
    tl_valid_slug "$project" || { echo "direct: invalid project name: $project" >&2; exit 64; }
    [ -d "$PROJECTS_DIR/$project" ] || { echo "direct: no such project: $project" >&2; exit 64; }
    base=$PROJECTS_DIR/$project/jobs
  else
    base=$TINKER_HOME/state/jobs
  fi
  [ -d "$cwd" ] || { echo "direct: --cwd '$cwd' is not a directory" >&2; exit 64; }
  cwd=$(cd "$cwd" && pwd)
  local id dir
  id="${name}_$(date '+%Y%m%d%H%M%S')_$$"
  dir=$base/$id
  mkdir -p "$dir"
  printf '%s\n' "$cmd" > "$dir/cmd.sh"
  {
    echo "name=$name"; echo "vram=$vram"; echo "class=$class"; echo "cwd=$cwd"
    echo "submitted=$(date '+%F %T')"
  } > "$dir/meta"
  cat > "$dir/run.sh" <<EOF
#!/usr/bin/env bash
# wrapper written by runners/direct.sh — records pid, runs cmd.sh, records the exit code atomically
echo \$\$ > "$dir/pid"
cd "$cwd" || { echo 127 > "$dir/exit.tmp"; mv "$dir/exit.tmp" "$dir/exit"; exit 127; }
rc=0
bash "$dir/cmd.sh" >> "$dir/log" 2>&1 || rc=\$?
echo "\$rc" > "$dir/exit.tmp" && mv "$dir/exit.tmp" "$dir/exit"
exit "\$rc"
EOF
  chmod +x "$dir/run.sh"
  tl_detach "$dir/run.sh" >/dev/null 2>&1 </dev/null
  printf '%s\n' "$id"
}

status() {
  local id=${1:-} dir pid rc
  [ -n "$id" ] || usage
  dir=$(find_job "$id") || { echo missing; exit 4; }
  if [ -f "$dir/exit" ]; then
    rc=$(cat "$dir/exit")
    if [ "$rc" = 0 ]; then echo 'done'; exit 0; fi
    echo "failed"; exit 1
  fi
  if [ -f "$dir/pid" ]; then
    pid=$(cat "$dir/pid")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo running; exit 2; fi
    # re-check: the job may have finished between the two reads
    [ -f "$dir/exit" ] && { status "$id"; return; }
    echo "failed"; exit 1     # process gone without recording an exit code (killed, reboot…)
  fi
  echo pending; exit 3
}

joblog() {
  local dir
  dir=$(find_job "${1:-}") || { echo "direct: no such job: ${1:-}" >&2; exit 4; }
  cat "$dir/log" 2>/dev/null || true
}

case "${1:-}" in
  submit) shift; submit "$@" ;;
  status) shift; status "$@" ;;
  log) shift; joblog "$@" ;;
  *) usage ;;
esac
