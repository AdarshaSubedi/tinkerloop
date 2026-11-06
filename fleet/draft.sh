#!/usr/bin/env bash
# fleet/draft.sh "<task>" <file...>
# Drafter client: ships a task + numbered file contents to the `drafter` model from config.json
# (falls back to `reader` if no drafter is configured) with a citation-mandatory prompt. The
# output is a DRAFT for Claude to verify — the drafter is trusted with drafts, never verdicts.
#
# Exit codes (ATOMIC — stdout is either a complete draft or empty):
#   0 draft on stdout · 1 local problem · 2 usage · 3 model failed, retry later
#   4 NO LOCAL MODEL configured (neither drafter nor reader) → do it yourself (Claude / subagents)
# Env: TINKER_FLEET_TIMEOUT (s, default 1800) · TINKER_FLEET_RETRIES (default 2) ·
#      TINKER_FLEET_MAX_TOKENS (default 16384) · TINKER_CONFIG (default <repo>/config.json)
set -euo pipefail
_s=${BASH_SOURCE[0]}
while [ -L "$_s" ]; do _t=$(readlink "$_s"); case "$_t" in /*) _s=$_t ;; *) _s=$(dirname "$_s")/$_t ;; esac; done
TL_SELF=$_s
# shellcheck source=bin/_common.sh
. "$(cd "$(dirname "$_s")" && pwd -P)/../bin/_common.sh"
# shellcheck source=fleet/_client.sh
. "$TINKER_HOME/fleet/_client.sh"

TOOL=draft.sh
[ $# -ge 2 ] || { echo "usage: fleet/draft.sh \"<task>\" <file...>" >&2; exit 2; }
TASK=$1; shift
TIMEOUT=${TINKER_FLEET_TIMEOUT:-1800}
WANT_ROLE=drafter
VALIDATOR_TAG=draft-validator
command -v jq >/dev/null || { echo "$TOOL: jq required" >&2; exit 1; }
fleet_endpoint drafter reader

SYSTEM='You are a research drafter: you read sources and produce a structured draft
(findings, comparisons, or report sections) for a downstream reviewer who will verify it.
Rules (non-negotiable):
1. Build the draft ONLY from the provided sources. No outside knowledge, no guesses.
   Mark any inference that goes beyond a source as INFERENCE with the citations it rests on.
2. EVERY factual claim must end with a citation in plain ASCII square brackets [ ]:
   - file content -> [<path>:<line>] or [<path>:<start>-<end>] (line numbers are given)
   - anything else -> the exact URL or command it came from.
3. Uncited claims are automatically discarded downstream, so do not write any.
   Line numbers RESTART AT 1 for each SOURCE — cite the N: prefix shown on the line itself,
   never a running count across sources. Out-of-range citations are auto-discarded.
4. If the sources cannot support the task, say so plainly and draft only what they support.
5. You draft; you do not decide. Surface open questions and conflicts between sources in a
   final OPEN QUESTIONS section instead of resolving them silently.'

fleet_run TASK "$SYSTEM" "$TASK" "$@"
