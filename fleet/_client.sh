# fleet/_client.sh — shared by gather.sh and draft.sh. Sourced, not executed.
# Sends a task + numbered file contents to an OpenAI-compatible /chat/completions endpoint from
# config.json, with the citation-mandatory system prompt, and enforces the ATOMIC contract:
#   exit 0  complete answer on stdout (+ a citation-validator footer)
#   exit 1  local problem (missing jq/curl, unreadable file, bad config) — reason on stderr
#   exit 2  usage
#   exit 3  endpoint failed after retries (down, non-200, unfinished/empty answer) — retry later
#   exit 4  NO LOCAL MODEL configured for this role — do the reading yourself (Claude / subagents)
# On any non-zero exit NOTHING is written to stdout. A failed call is never evidence.

FLEET_NO_MODEL=4

# fleet_endpoint <role> [fallback-role] → sets EP_ROLE EP_URL EP_MODEL EP_KEY, or exits 4/1.
fleet_endpoint() {
  local role
  if [ ! -e "$TINKER_CONFIG" ]; then
    echo "$TOOL: no config.json — no local model configured. Do this reading yourself (exit $FLEET_NO_MODEL)." >&2
    exit "$FLEET_NO_MODEL"
  fi
  jq -e . "$TINKER_CONFIG" >/dev/null 2>&1 || { echo "$TOOL: $TINKER_CONFIG is not valid JSON — run 'tinker doctor'" >&2; exit 1; }
  for role in "$@"; do
    EP_URL=$(jq -r --arg r "$role" '.[$r].url // empty' "$TINKER_CONFIG")
    [ -n "$EP_URL" ] || continue
    EP_ROLE=$role
    EP_MODEL=$(jq -r --arg r "$role" '.[$r].model // empty' "$TINKER_CONFIG")
    [ -n "$EP_MODEL" ] || { echo "$TOOL: config role '$role' has a url but no model" >&2; exit 1; }
    local keyvar
    keyvar=$(jq -r --arg r "$role" '.[$r].api_key_env // empty' "$TINKER_CONFIG")
    EP_KEY=""
    if [ -n "$keyvar" ]; then
      case "$keyvar" in *[!A-Za-z0-9_]*) echo "$TOOL: api_key_env '$keyvar' is not a valid variable name" >&2; exit 1 ;; esac
      EP_KEY=${!keyvar:-}
      [ -n "$EP_KEY" ] || { echo "$TOOL: config says the API key is in \$$keyvar, but it is empty" >&2; exit 1; }
    fi
    EP_URL=${EP_URL%/}
    return 0
  done
  echo "$TOOL: no local model configured for role(s): $* — do this reading yourself (exit $FLEET_NO_MODEL)." >&2
  exit "$FLEET_NO_MODEL"
}

# fleet_run <label> <system-prompt> <task-text> <file...>   (call fleet_endpoint first)
fleet_run() {
  local label=$1 system=$2 task=$3; shift 3
  command -v jq >/dev/null || { echo "$TOOL: jq required" >&2; exit 1; }
  command -v curl >/dev/null || { echo "$TOOL: curl required" >&2; exit 1; }
  local BODY LINEMAP REQ RESP
  BODY=$(mktemp); LINEMAP=$(mktemp); REQ=$(mktemp); RESP=$(mktemp)
  # shellcheck disable=SC2064  # expand now: the temp names are local
  trap "rm -f '$BODY' '$LINEMAP' '$REQ' '$RESP'" EXIT
  {
    printf '%s: %s\n' "$label" "$task"
    local f
    for f in "$@"; do
      [ -r "$f" ] && [ -f "$f" ] || { echo "$TOOL: cannot read $f" >&2; exit 1; }
      printf '\n=== SOURCE: %s ===\n' "$f"
      grep -n '' -- "$f" || true   # prefix every line with N: so citations are checkable
      printf '%s\t%s\n' "$f" "$(grep -c '' -- "$f" || true)" >> "$LINEMAP"
    done
  } > "$BODY"

  local chars; chars=$(wc -c < "$BODY" | tr -d ' ')
  if [ "$chars" -gt "${TINKER_FLEET_MAX_CHARS:-200000}" ]; then
    echo "$TOOL: input is ~$((chars / 3500))k tokens — may exceed the model's context window; consider splitting the call" >&2
  fi

  jq -n --arg model "$EP_MODEL" --arg sys "$system" --rawfile user "$BODY" \
    --argjson maxtok "${TINKER_FLEET_MAX_TOKENS:-16384}" \
    '{model:$model, temperature:0.6, top_p:0.95, max_tokens:$maxtok,
      messages:[{role:"system",content:$sys},{role:"user",content:$user}]}' > "$REQ"

  # Bounded retry, then the ATOMIC gate: buffer the whole response and prove it finished cleanly
  # before emitting anything. Transport drop / non-200 / unfinished / empty → retry; give up as 3.
  local tries=$(( ${TINKER_FLEET_RETRIES:-2} + 1 )) n=0 code finish content reason=""
  while [ "$n" -lt "$tries" ]; do
    n=$((n+1))
    [ "$n" -gt 1 ] && { echo "$TOOL: retry $((n-1)) after: $reason" >&2; sleep "${TINKER_FLEET_RETRY_WAIT:-10}"; }
    if [ -n "$EP_KEY" ]; then
      code=$(curl -sS -m "$TIMEOUT" -o "$RESP" -w '%{http_code}' "$EP_URL/chat/completions" \
               -H 'Content-Type: application/json' -H "Authorization: Bearer $EP_KEY" \
               --data-binary @"$REQ" 2>/dev/null) || { reason="request to $EP_URL failed (unreachable or timed out)"; continue; }
    else
      code=$(curl -sS -m "$TIMEOUT" -o "$RESP" -w '%{http_code}' "$EP_URL/chat/completions" \
               -H 'Content-Type: application/json' --data-binary @"$REQ" 2>/dev/null) || {
        reason="request to $EP_URL failed (unreachable or timed out)"; continue; }
    fi
    [ "$code" = 200 ] || { reason="HTTP $code from $EP_URL: $(head -c 300 "$RESP" | tr '\n' ' ')"; continue; }
    finish=$(jq -r '.choices[0].finish_reason // empty' "$RESP" 2>/dev/null) || finish=""
    content=$(jq -r '.choices[0].message.content // empty' "$RESP" 2>/dev/null) || content=""
    case "$finish" in
      stop) ;;
      length) echo "$TOOL: warning — answer hit max_tokens (complete but cut at the token budget)" >&2 ;;
      *) reason="generation did not finish (finish_reason='${finish:-none}')"; continue ;;
    esac
    [ -n "$content" ] || { reason="empty answer"; continue; }
    reason=""; break
  done
  if [ -n "$reason" ]; then
    echo "$TOOL: $reason — NOT complete after $tries attempt(s); retry later (exit 3)" >&2
    exit 3
  fi
  [ "$EP_ROLE" != "$WANT_ROLE" ] && echo "$TOOL: note — no '$WANT_ROLE' configured, used '$EP_ROLE' ($EP_MODEL)" >&2

  # some models cite with fullwidth brackets 【…】 — normalise to [ ] so the validator sees them
  printf '%s\n' "$content" | LC_ALL=C sed 's/【/[/g; s/】/]/g' | fleet_validate "$LINEMAP" "$#" "$VALIDATOR_TAG"
}

# Citation firewall: verify every [path:N], [path:N-M] — and, with a single source, bare [N]/[N-M] —
# against the real line counts. Out-of-range or unknown-path pointers are listed for discard.
fleet_validate() {
  awk -v linemap="$1" -v nsrc="$2" -v tag="$3" '
  BEGIN {
    while ((getline l < linemap) > 0) { split(l, kv, "\t"); max[kv[1]] = kv[2]; only = kv[1] }
    if (nsrc != 1) only = ""
  }
  {
    print
    line = $0
    while (match(line, /\[[^][]+\]/)) {
      inner = substr(line, RSTART + 1, RLENGTH - 2)
      line = substr(line, RSTART + RLENGTH)
      ncs = split(inner, cs, /[,;] */)
      path = ""
      for (i = 1; i <= ncs; i++) {
        c = cs[i]; gsub(/`| /, "", c); sub(/^(src|source|SOURCE):/, "", c)
        if (match(c, /^.+:[0-9]+(-[0-9]+)?$/)) { path = c; sub(/:[0-9]+(-[0-9]+)?$/, "", path); rng = substr(c, length(path) + 2) }
        else if (match(c, /^[0-9]+(-[0-9]+)?$/) && (path != "" || only != "")) { if (path == "") path = only; rng = c }
        else continue
        total++
        split(rng, ab, "-"); lo = ab[1] + 0; hi = (ab[2] != "" ? ab[2] + 0 : lo)
        if (!(path in max)) { bad[++nbad] = path ":" rng " (unknown source)" }
        else if (hi > max[path] + 0 || lo < 1 || lo > hi) { bad[++nbad] = path ":" rng " (max " max[path] ")" }
      }
    }
  }
  END {
    print ""
    if (nbad) {
      print "[" tag "] DISCARD claims citing " nbad " out-of-range pointer(s) of " total ":"
      for (i = 1; i <= nbad; i++) print "[" tag "]   " bad[i]
    } else if (total) print "[" tag "] all " total " citation pointer(s) within source range"
    else print "[" tag "] WARNING: no file:line citations found — treat every claim as uncited"
  }'
}
