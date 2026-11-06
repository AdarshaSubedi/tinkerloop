#!/usr/bin/env bash
# run.sh — generic experiment harness with a smoke → render gate. Don't edit per experiment;
# edit experiment.env. Instantiate: mkdir -p projects/<P>/experiments && cp -R templates/experiment projects/<P>/experiments/<id>
#
#   ./run.sh smoke    cheap dry-run ($SMOKE_CMD) → state/SMOKE_OK (with the harness rev) or SMOKE_FAIL
#   ./run.sh render   full run ($LAUNCH_CMD); REFUSES unless SMOKE_OK matches the current rev
#   (no arg)          render
# Submit through the runner rather than calling it bare for anything long or GPU-bound:
#   bin/tinker-run submit --project <P> --name <id> --vram "$VRAM_GB" --class "$CLASS" \
#       --cwd projects/<P>/experiments/<id> --cmd './run.sh render'
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MODE=${1:-render}
cd "$HERE"
# shellcheck source=/dev/null
. "$HERE/experiment.env"
STATE=$HERE/state; RESULTS=$HERE/results
mkdir -p "$STATE" "$RESULTS"

# rev = hash of (run.sh + experiment.env): an edited harness must re-smoke.
current_rev() {
  if command -v sha1sum >/dev/null 2>&1; then cat "$HERE/run.sh" "$HERE/experiment.env" | sha1sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then cat "$HERE/run.sh" "$HERE/experiment.env" | shasum | cut -d' ' -f1
  else cat "$HERE/run.sh" "$HERE/experiment.env" | cksum | cut -d' ' -f1; fi
}

setup() {
  if [ -n "${SETUP_CMD:-}" ]; then echo "[run] SETUP: $SETUP_CMD"; eval "$SETUP_CMD"; fi
}

case "$MODE" in
  smoke)
    [ -n "${SMOKE_CMD:-}" ] || { echo "[run] FATAL: SMOKE_CMD is empty in experiment.env." >&2; exit 1; }
    rev=$(current_rev)
    out=$STATE/.smoke.out.$$
    rc=0
    { setup && cd "$RESULTS" && echo "[run] SMOKE: $SMOKE_CMD" && eval "$SMOKE_CMD"; } > "$out" 2>&1 || rc=$?
    cat "$out"
    if [ "$rc" = 0 ]; then
      rm -f "$STATE/SMOKE_FAIL"
      echo "rev=$rev ts=$(date +%s) msg=smoke OK" > "$STATE/SMOKE_OK"
      rm -f "$out"
      echo "[run] SMOKE_OK written (rev=$rev)"
    else
      { echo "stage=smoke rc=$rc rev=$rev ts=$(date +%s)"; echo "cmd=$SMOKE_CMD"
        echo "--- last ~40 lines ---"; tail -n 40 "$out"; } > "$STATE/SMOKE_FAIL"
      rm -f "$STATE/SMOKE_OK" "$out"
      echo "[run] SMOKE FAILED (rc=$rc) → state/SMOKE_FAIL" >&2
      exit "$rc"
    fi
    ;;
  render)
    [ -f "$STATE/SMOKE_OK" ] || { echo "[run] REFUSING render: no state/SMOKE_OK. Run './run.sh smoke' first." >&2; exit 1; }
    ok_rev=$(head -1 "$STATE/SMOKE_OK" | sed -n 's/^rev=\([^ ]*\).*/\1/p')
    cur_rev=$(current_rev)
    if [ "$ok_rev" != "$cur_rev" ]; then
      echo "[run] REFUSING render: SMOKE_OK rev=$ok_rev != current rev=$cur_rev (harness changed; re-smoke)." >&2
      exit 1
    fi
    [ -n "${LAUNCH_CMD:-}" ] || { echo "[run] FATAL: LAUNCH_CMD is empty in experiment.env." >&2; exit 1; }
    setup
    cd "$RESULTS"
    echo "[run] RENDER (smoke-green, rev=$cur_rev): $LAUNCH_CMD"
    eval "$LAUNCH_CMD"
    echo "[run] done → $RESULTS"
    ;;
  *) echo "[run] usage: $0 {smoke|render}   (no arg = render)" >&2; exit 2 ;;
esac
