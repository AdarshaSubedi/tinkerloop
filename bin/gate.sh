#!/usr/bin/env bash
# bin/gate.sh <project> <id> [title] [artifact-path] [--run '<cmd>' --cwd <dir> [--vram N] [--class tag]]
# Raise a gate: a decision only the user makes. Called by a loop session (not by you) when a probe
# survivor earns a dossier, when a result needs a human verdict, or — with --run — when experiment
# code needs your OK before it runs. It writes, in projects/<project>/gates/:
#   <id>.html       the write-up (from dossiers/<id>.md) for the user to read in a browser
#   <id>.answer.md  where the user writes the decision (created empty-ish; never overwritten)
#   <id>.run        (--run only) the exact command spec; the LOOP DRIVER (bash) submits it via
#                   bin/tinker-run once the answer's first word is run / yes / approve
#   INDEX.md        one line per gate, marked "pending" until a session records the answer
# Optional artifact (image / video / any file) is shown alongside, for a verdict gate.
# Set TINKER_GATE_OPEN=1 to also open the page in the default browser.
set -euo pipefail
_s=${BASH_SOURCE[0]}
while [ -L "$_s" ]; do _t=$(readlink "$_s"); case "$_t" in /*) _s=$_t ;; *) _s=$(dirname "$_s")/$_t ;; esac; done
TL_SELF=$_s
# shellcheck source=bin/_common.sh
. "$(cd "$(dirname "$_s")" && pwd -P)/../bin/_common.sh"

USAGE="usage: gate.sh <project> <id> [title] [artifact-path] [--run '<cmd>' --cwd <dir> [--vram N] [--class tag]]"
P=${1:?$USAGE}
ID=${2:?$USAGE}
shift 2
TITLE=""; ARTIFACT=""; RUN_CMD=""; RUN_CWD=""; RUN_VRAM=0; RUN_CLASS=default
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN_CMD=${2:?--run needs a command}; shift 2 ;;
    --cwd) RUN_CWD=${2:?--cwd needs a directory}; shift 2 ;;
    --vram) RUN_VRAM=${2:?}; shift 2 ;;
    --class) RUN_CLASS=${2:?}; shift 2 ;;
    --*) echo "gate.sh: unknown option $1" >&2; echo "$USAGE" >&2; exit 2 ;;
    *) if [ -z "$TITLE" ]; then TITLE=$1; elif [ -z "$ARTIFACT" ]; then ARTIFACT=$1
       else echo "$USAGE" >&2; exit 2; fi; shift ;;
  esac
done
TITLE=${TITLE:-$ID}
tl_valid_slug "$P" || { echo "gate.sh: invalid project name: $P" >&2; exit 2; }
case "$ID" in ''|*[!A-Za-z0-9._-]*) echo "gate.sh: id must be letters, digits, . _ - only" >&2; exit 2 ;; esac
[ -d "$PROJECTS_DIR/$P" ] || { echo "gate.sh: no such project: $P" >&2; exit 2; }
case "$RUN_VRAM" in *[!0-9]*) echo "gate.sh: --vram must be a whole number of GB" >&2; exit 2 ;; esac
case "$RUN_CLASS" in *[!A-Za-z0-9._-]*) echo "gate.sh: --class must be letters, digits, . _ -" >&2; exit 2 ;; esac

G=$PROJECTS_DIR/$P/gates; BODY_FILE=$PROJECTS_DIR/$P/dossiers/$ID.md
mkdir -p "$G"
ANSWER=$G/$ID.answer.md
PAGE=$G/$ID.html
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
RUN_HTML=""
if [ -n "$RUN_CMD" ]; then
  # A run gate must be fresh: never let an earlier answer approve a new command.
  if [ -e "$G/$ID.run" ] || tl_gate_answered "$ANSWER"; then
    echo "gate.sh: gate '$ID' already exists or was answered — use a new id for a new run request" >&2; exit 2
  fi
  [ -n "$RUN_CWD" ] || { echo "gate.sh: --run needs --cwd <dir> (inside projects/$P/)" >&2; exit 2; }
  [ -d "$RUN_CWD" ] || { echo "gate.sh: --cwd '$RUN_CWD' is not a directory" >&2; exit 2; }
  RUN_CWD=$(cd "$RUN_CWD" && pwd -P)
  PROOT=$(cd "$PROJECTS_DIR/$P" && pwd -P)
  case "$RUN_CWD/" in "$PROOT"/*) ;; *) echo "gate.sh: --cwd must be inside projects/$P/" >&2; exit 2 ;; esac
  command -v jq >/dev/null || { echo "gate.sh: jq required for --run" >&2; exit 1; }
  jq -n --arg project "$P" --arg id "$ID" --arg cmd "$RUN_CMD" --arg cwd "$RUN_CWD" \
        --argjson vram "$RUN_VRAM" --arg class "$RUN_CLASS" --arg at "$(date '+%F %T')" \
        '{project:$project, id:$id, cmd:$cmd, cwd:$cwd, vram:$vram, class:$class, requested:$at}' > "$G/$ID.run"
  FP=$(tl_run_fingerprint "$G/$ID.run")
  REC=$(tl_run_record "$P" "$ID")
  mkdir -p "$(dirname "$REC")"
  printf '%s\n' "$FP" > "$REC"
  CMD_HTML=$(printf '%s' "$RUN_CMD" | esc); CWD_HTML=$(printf '%s' "$RUN_CWD" | esc)
  RUN_HTML="<div class=\"box run\"><b>Permission to run code</b> — nothing runs unless you approve.<br>
Command: <pre>$CMD_HTML</pre>Folder: <code>$CWD_HTML</code><br>Resources: GPU memory ${RUN_VRAM} GB (0 = CPU only) · class <code>$RUN_CLASS</code><br>
Fingerprint of the command + the folder's files: <code>${FP}</code> — if anything in that folder changes before it runs, the run is refused.<br>
Read the scripts in that folder before approving. To approve, make the first word of your answer <b>run</b>.</div>"
  if [ ! -s "$ANSWER" ]; then
    printf '<!-- Approve by writing "run" as the first word below. Anything else declines (add why). -->\n' > "$ANSWER"
  fi
fi
if [ ! -s "$ANSWER" ]; then
  printf '<!-- Write your decision below: in / out (+ why), or any feedback. The loop reads this. -->\n' > "$ANSWER"
fi

if [ -r "$BODY_FILE" ]; then BODY_HTML=$(esc < "$BODY_FILE"); else BODY_HTML="(write-up not found: $BODY_FILE)"; fi
TITLE_HTML=$(printf '%s' "$TITLE" | esc)

ART_HTML=""
if [ -n "$ARTIFACT" ]; then
  abs=$ARTIFACT; case "$abs" in /*) ;; *) abs="$PWD/$abs" ;; esac
  url="file://$(printf '%s' "$abs" | sed 's/ /%20/g; s/"/%22/g')"
  shown=$(printf '%s' "$abs" | esc)
  case "$abs" in
    *.mp4|*.webm|*.mov) ART_HTML="<div class=\"box\"><b>Result to judge</b> (look before answering):<br><video src=\"$url\" controls></video><br><a href=\"$url\">$shown</a></div>" ;;
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg) ART_HTML="<div class=\"box\"><b>Result to judge</b> (look before answering):<br><img src=\"$url\" alt=\"result\"><br><a href=\"$url\">$shown</a></div>" ;;
    *) ART_HTML="<div class=\"box\"><b>Result to judge:</b> <a href=\"$url\">$shown</a></div>" ;;
  esac
fi
ANSWER_HTML=$(printf '%s' "$ANSWER" | esc)

cat > "$PAGE" <<EOF
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>[$P/$ID] $TITLE_HTML</title>
<style>
:root{--bg:#fafafa;--fg:#222;--box:#ddd;--code:#eee;--accent:#0b62a4}
@media (prefers-color-scheme: dark){:root{--bg:#111;--fg:#ddd;--box:#444;--code:#222;--accent:#7ec8ff}}
body{font-family:system-ui,sans-serif;max-width:820px;margin:2em auto;padding:0 16px;background:var(--bg);color:var(--fg);line-height:1.5}
h1{color:var(--accent);font-size:1.4em}code,pre{background:var(--code);border-radius:4px}code{padding:2px 6px}
pre{padding:1em;white-space:pre-wrap;word-wrap:break-word}.box{border:1px solid var(--box);border-radius:8px;padding:1em;margin:1em 0}
a{color:var(--accent)}.run{border-color:var(--accent)}video,img{max-width:100%;margin-top:.5em;border-radius:6px}
</style></head><body>
<h1>[$P/$ID] $TITLE_HTML</h1>$RUN_HTML$ART_HTML<pre>$BODY_HTML</pre>
<div class="box">Write your decision (<b>in</b> / <b>out</b> + why, or any feedback) in:<br><code>$ANSWER_HTML</code><br>
On <b>in</b> the loop carries the idea forward; on <b>out</b> your reason becomes the lesson it learns.</div>
</body></html>
EOF
KIND=""; [ -n "$RUN_CMD" ] && KIND=" (run approval: answer 'run' to approve)"
echo "- [$ID] pending — $TITLE$KIND — answer: gates/$ID.answer.md ($(date '+%F %T'))" >> "$G/INDEX.md"
if [ "${TINKER_GATE_OPEN:-0}" = 1 ]; then
  if command -v open >/dev/null 2>&1 && [ "$(uname)" = Darwin ]; then open "$PAGE" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$PAGE" >/dev/null 2>&1 || true; fi
fi
echo "$ID"
