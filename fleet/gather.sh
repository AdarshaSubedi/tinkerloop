#!/usr/bin/env bash
# fleet/gather.sh "<question>" <file...>
# Reader client: ships a question + numbered file contents to the `reader` model from config.json
# (any OpenAI-compatible server: Ollama, LM Studio, llama.cpp, vLLM…) with a citation-mandatory
# prompt. Uncited claims are discarded downstream, not argued with. The caller spot-checks cites.
#
# Exit codes (ATOMIC — stdout is either a complete answer or empty):
#   0 answer on stdout · 1 local problem · 2 usage · 3 model failed, retry later
#   4 NO LOCAL MODEL configured → do the reading yourself (Claude / subagents)
# Env: TINKER_FLEET_TIMEOUT (s, default 600) · TINKER_FLEET_RETRIES (default 2) ·
#      TINKER_FLEET_MAX_TOKENS (default 16384) · TINKER_CONFIG (default <repo>/config.json)
set -euo pipefail
_s=${BASH_SOURCE[0]}
while [ -L "$_s" ]; do _t=$(readlink "$_s"); case "$_t" in /*) _s=$_t ;; *) _s=$(dirname "$_s")/$_t ;; esac; done
TL_SELF=$_s
# shellcheck source=bin/_common.sh
. "$(cd "$(dirname "$_s")" && pwd -P)/../bin/_common.sh"
# shellcheck source=fleet/_client.sh
. "$TINKER_HOME/fleet/_client.sh"

TOOL=gather.sh
[ $# -ge 2 ] || { echo "usage: fleet/gather.sh \"<question>\" <file...>" >&2; exit 2; }
QUESTION=$1; shift
TIMEOUT=${TINKER_FLEET_TIMEOUT:-600}
WANT_ROLE=reader
VALIDATOR_TAG=gather-validator
command -v jq >/dev/null || { echo "$TOOL: jq required" >&2; exit 1; }
fleet_endpoint reader

SYSTEM='You are a gather worker: you read sources and extract facts for a downstream reviewer.
Rules (non-negotiable):
1. Answer ONLY from the provided sources. No outside knowledge, no guesses.
2. EVERY claim must end with a citation in plain ASCII square brackets [ ]:
   - file content -> [<path>:<line>] or [<path>:<start>-<end>] (line numbers are given)
   - anything else -> the exact URL or command it came from.
3. Uncited claims are automatically discarded downstream, so do not write any.
   Line numbers RESTART AT 1 for each SOURCE — cite the N: prefix shown on the line itself,
   never a running count across sources. Out-of-range citations are auto-discarded.
4. If the sources do not answer the question, reply exactly: NOT FOUND, then list
   (with citations) the closest related facts you did find, if any.
5. Be compressed: terse bullets, no preamble, no restating the question.'

fleet_run QUESTION "$SYSTEM" "$QUESTION" "$@"
