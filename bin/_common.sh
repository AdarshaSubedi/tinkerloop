# _common.sh — sourced by every tinkerloop script. Not executable on its own.
# Resolves TINKER_HOME (the repo root) and provides small portable helpers.
# Callers must set TL_SELF to "${BASH_SOURCE[0]}" before sourcing (so symlinks resolve).

# Resolve a path through any chain of symlinks (portable: no `readlink -f`, which old macOS lacks).
tl_resolve() {
  local src=$1 dir
  while [ -L "$src" ]; do
    dir=$(cd -P "$(dirname "$src")" && pwd)
    src=$(readlink "$src")
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  dir=$(cd -P "$(dirname "$src")" && pwd)
  printf '%s/%s\n' "$dir" "$(basename "$src")"
}

if [ -z "${TINKER_HOME:-}" ]; then
  _tl_me=$(tl_resolve "${TL_SELF:?TL_SELF must be set before sourcing _common.sh}")
  # scripts live one level down from the repo root (bin/, fleet/, runners/)
  TINKER_HOME=$(cd "$(dirname "$_tl_me")/.." && pwd)
  unset _tl_me
fi
export TINKER_HOME
TINKER_CONFIG=${TINKER_CONFIG:-$TINKER_HOME/config.json}
export TINKER_CONFIG
# shellcheck disable=SC2034  # used by the scripts that source this file
PROJECTS_DIR=$TINKER_HOME/projects

tl_die() { echo "tinker: $*" >&2; exit 1; }

# Slugs are kebab-case: lowercase letters, digits, dashes. Keeps paths and process matching safe.
tl_valid_slug() {
  case "$1" in
    ''|-*|*-) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# Read a value from config.json with jq. Prints nothing if the file or key is absent.
# Usage: tl_config '.runner'
tl_config() {
  [ -e "$TINKER_CONFIG" ] || return 0
  jq -r "$1 // empty" "$TINKER_CONFIG" 2>/dev/null || true
}

# Run a command fully detached from the terminal. setsid is missing on macOS → plain nohup.
tl_detach() {
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup "$@" &
  else
    nohup "$@" &
  fi
}

# Is the pid in a pidfile alive? Prints the pid on success.
tl_pid_alive() {
  local f=$1 pid
  [ -f "$f" ] || return 1
  pid=$(cat "$f" 2>/dev/null) || return 1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && { printf '%s\n' "$pid"; return 0; }
  return 1
}

# A gate answer counts once it has something besides HTML comments and blank lines.
tl_gate_answered() {
  [ -f "$1" ] || return 1
  sed -e 's/<!--.*-->//g' "$1" | grep -q '[^[:space:]]'
}

# Count pending gates in a project (gate page exists, answer still empty).
tl_pending_gates() {
  local g=$1/gates n=0 page id
  for page in "$g"/*.html; do
    [ -f "$page" ] || continue
    id=$(basename "$page" .html)
    tl_gate_answered "$g/$id.answer.md" || n=$((n+1))
  done
  echo "$n"
}

# --- run-approval gates -----------------------------------------------------------------------
tl_hash() {  # stdin → hex digest (sha1sum / shasum / cksum, whichever exists)
  if command -v sha1sum >/dev/null 2>&1; then sha1sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum | cut -d' ' -f1
  else cksum | cut -d' ' -f1; fi
}

# Fingerprint of a run spec + every file in its working dir (except results/ and state/), so an
# approved command can't be swapped, or its scripts edited, between your "run" and the execution.
tl_run_fingerprint() {  # tl_run_fingerprint <spec.run>
  local spec=$1 cwd f
  cwd=$(jq -r '.cwd' "$spec")
  {
    cat "$spec"
    find "$cwd" -type f ! -path "$cwd/results/*" ! -path "$cwd/state/*" 2>/dev/null | LC_ALL=C sort |
      while IFS= read -r f; do printf '\n== %s\n' "${f#"$cwd"/}"; cat "$f"; done
  } | tl_hash
}

# Where the driver keeps run-gate fingerprints: OUTSIDE the repo, so a loop session (which may
# only edit files inside the repo) cannot rewrite what you approved.
tl_run_record() {  # tl_run_record <project> <id> → path of the fingerprint record
  local base key
  base=${TINKER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tinkerloop}
  key=$(printf '%s' "$TINKER_HOME" | tl_hash | cut -c1-12)
  printf '%s/%s/%s/%s.fp\n' "$base" "$key" "$1" "$2"
}
