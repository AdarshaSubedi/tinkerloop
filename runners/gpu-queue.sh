#!/usr/bin/env bash
# runners/gpu-queue.sh — optional adapter for a shared GPU job queue that has a "submit" command and
# a per-job "status" command. Select it with  "runner": "gpu-queue"  in config.json.
# Nothing is baked in; point it at your queue with environment variables:
#
#   TINKER_QUEUE_SUBMIT  (required) submit command. Called as:
#                          $TINKER_QUEUE_SUBMIT --cmd '<command>' --vram <GB> --class <tag> --name <tag>
#   TINKER_QUEUE_STAT    (required) status command. Called as:  $TINKER_QUEUE_STAT <JOB_ID>
#                        and MUST use the same exit codes as tinker-run status:
#                          0 done · 1 failed · 2 running · 3 pending · 4 missing
#   TINKER_QUEUE_LOGDIR  (optional) directory holding <JOB_ID>.log, for `tinker-run log`
#
# Job id extraction from the submit command's output, first match wins:
#   a line "JOB_ID=<id>" or "job_id: <id>"  →  a line "submitted: [anything__]<id>[.job]"  →
#   the last word of the last non-empty line.
# --project and --cwd are accepted for interface compatibility; the command runs in --cwd via `cd`.
set -euo pipefail

usage() { echo "usage: tinker-run submit [--project P] [--name tag] [--vram GB] [--class tag] [--cwd dir] [--exclusive] [--priority N] [--est min] --cmd '<command>' | status <JOB_ID> | log <JOB_ID>" >&2; exit 64; }
need() { [ -n "${!1:-}" ] || { echo "gpu-queue runner: $1 is not set. Export it (see runners/gpu-queue.sh)." >&2; exit 64; }; }

submit() {
  need TINKER_QUEUE_SUBMIT
  local name="job" vram="0" class="default" cwd=$PWD cmd="" extra=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) shift 2 ;;
      --name) name=${2:?}; shift 2 ;;
      --vram) vram=${2:?}; shift 2 ;;
      --class) class=${2:?}; shift 2 ;;
      --cwd) cwd=${2:?}; shift 2 ;;
      --cmd) cmd=${2:?}; shift 2 ;;
      --exclusive) extra="$extra --exclusive"; shift ;;
      --priority) extra="$extra --priority ${2:?}"; shift 2 ;;
      --est) extra="$extra --est ${2:?}"; shift 2 ;;
      *) echo "gpu-queue: unknown arg: $1" >&2; usage ;;
    esac
  done
  [ -n "$cmd" ] || { echo "gpu-queue: --cmd is required" >&2; usage; }
  cwd=$(cd "$cwd" && pwd)
  local full out id
  full="cd $(printf '%q' "$cwd") && $cmd"
  # shellcheck disable=SC2086  # $extra is a deliberately word-split list of flags
  out=$($TINKER_QUEUE_SUBMIT --cmd "$full" --vram "$vram" --class "$class" --name "$name" $extra) || {
    echo "gpu-queue: submit failed" >&2; printf '%s\n' "$out" >&2; exit 1; }
  id=$(printf '%s\n' "$out" | sed -n 's/^.*JOB_ID[=:] *\([A-Za-z0-9._-]*\).*$/\1/p; s/^.*job_id[=:] *\([A-Za-z0-9._-]*\).*$/\1/p' | head -1)
  if [ -z "$id" ]; then
    id=$(printf '%s\n' "$out" | sed -n 's/^submitted: *//p' | head -1 | sed 's/.*__//; s/\.job$//')
  fi
  if [ -z "$id" ]; then
    id=$(printf '%s\n' "$out" | awk 'NF{last=$NF} END{print last}')
  fi
  [ -n "$id" ] || { echo "gpu-queue: could not find a job id in the submit output:" >&2; printf '%s\n' "$out" >&2; exit 1; }
  printf '%s\n' "$id"
}

status() {
  need TINKER_QUEUE_STAT
  [ -n "${1:-}" ] || usage
  local rc=0
  $TINKER_QUEUE_STAT "$1" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) echo 'done' ;; 1) echo failed ;; 2) echo running ;; 3) echo pending ;; 4) echo missing ;;
    *) echo "unknown(rc=$rc)" ;;
  esac
  exit "$rc"
}

joblog() {
  [ -n "${1:-}" ] || usage
  if [ -n "${TINKER_QUEUE_LOGDIR:-}" ] && [ -f "$TINKER_QUEUE_LOGDIR/$1.log" ]; then
    cat "$TINKER_QUEUE_LOGDIR/$1.log"
  else
    echo "gpu-queue: no log found (set TINKER_QUEUE_LOGDIR to the queue's log directory)" >&2; exit 4
  fi
}

case "${1:-}" in
  submit) shift; submit "$@" ;;
  status) shift; status "$@" ;;
  log) shift; joblog "$@" ;;
  *) usage ;;
esac
