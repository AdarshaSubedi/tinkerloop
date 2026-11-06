# PROTOCOL — one session = one move in ONE project

You are launched by `bin/tinker-loop <P>` with an **active project `P`** named in your prompt (also
in `$TINKER_PROJECT`; the repo root is `$TINKER_HOME` and your working directory). Everything below
is scoped to `projects/P/`. You never touch another project.

**Hydrate:** `projects/P/STATE.md` → that project's `SEED.md` + `angles.md` (only those). Pick the
move STATE points to. Do exactly one, write back, update `projects/P/STATE.md`, refresh
`projects/P/README.md` if the project's status changed, exit. Reading → local models / subagents.

**First, reconcile experiments:** for every job in STATE's `## Experiments` block whose recorded
`status=` isn't terminal, read its true state with `bin/tinker-run status <JOB_ID>` and rewrite the
line (the runner wins over prose — never narrate running/done/failed unchecked). **Adopt approved
runs:** every `gates/<id>.job` (a JOB_ID the loop driver submitted after you approved a run-gate)
whose JOB_ID isn't yet in the Experiments block gets a line there (`status=running`, then reconcile
it like the rest); a `gates/<id>.declined` means that run did NOT happen — read its reason and the
answer file, record it, and decide the next move (re-gate with a fix, or treat as the user's steer).

**Then, reconcile gates:** for every `gates/<id>.answer.md` that now holds an answer (anything
besides the `<!-- -->` placeholder) whose `gates/INDEX.md` line still says `pending`, apply the
answer (see DOSSIER: "in" / "out" / feedback) as this session's move, and change that INDEX line's
`pending` to `answered: <one-line gist>`.

**IDLE:** if NO move is eligible (every angle at gate or killed, no ideation owed, every tracked
experiment still pending/running): write `projects/P/state/IDLE` (one line: why) and exit — never
invent work. The loop re-arms you when the user answers a gate OR a tracked experiment finishes (it
polls `bin/tinker-run status`, so a long experiment costs sleeps, not sessions).

## Permission modes (your prompt says which one you are in)
- **SAFE (default).** You can read, search the web, use the reading tools, and write files inside
  this folder. You **cannot run code** — not `run.sh`, not `bin/tinker-run submit`, not scripts you
  wrote. To run an experiment (smoke OR full), raise a **run-gate**:
  `bin/gate.sh P <exp-id>-run "<plain title>" --run '<exact command>' --cwd projects/P/experiments/<exp-id> --vram <GB> --class <tag>`
  (write `dossiers/<exp-id>-run.md` first: what it runs, why, what it touches, expected time). The
  user approves by answering `run`; the **loop driver** — not you — then submits it and writes
  `gates/<id>.job`. Use a NEW gate id for every run request (e.g. `<exp-id>-smoke-2`). After raising
  it, mark the move waiting on the gate in STATE and exit. Don't edit an experiment's folder after
  gating it: the driver fingerprints the command + folder and refuses a changed run.
- **FULL AUTONOMY** (`TINKER_SKIP_PERMISSIONS=1`). You may run smokes and submit runs yourself via
  `bin/tinker-run submit`, as described in PROBE / DEVOPS / Experiments. Everything else is the same.
- **A denied tool call is a stop sign, not a puzzle.** If permissions deny a call, do NOT retry it
  and do NOT work around it (no alternate command, tool, script or file trick that achieves the same
  effect). Write `dossiers/<id>.md` naming the exact command, why the move needs it, and what the
  user could allow (in `.claude/settings.local.json`) or approve instead; raise
  `bin/gate.sh P <id> "needs permission: <short>"`; mark the move blocked in STATE; exit.

This loop is **domain-agnostic**: the schema below is generic; each project's SEED defines its own
domain (the assumption, the evidence-surfaces, what a "feasibility question" means there).

## Reading tools (and their exit codes — read this once)
- `fleet/gather.sh "<question>" <file...>` — the `reader` model extracts cited facts.
- `fleet/draft.sh "<task>" <file...>` — the `drafter` model (falls back to `reader`) writes a cited draft.
- Web pages: read them with WebFetch / WebSearch, or save the page text into
  `projects/P/sources/<name>.md` (first line: the URL) and hand that file to the reading tools;
  cite the URL for anything taken from them.
- Both are **atomic**: either a complete answer on stdout with exit 0, or NOTHING on stdout with a
  non-zero exit and the reason on stderr.
  - **exit 4 = no local model configured.** Not an error. Do that reading yourself — Explore /
    general subagents or your own tools — under the same citation rules. Don't retry the script.
  - **exit 3 = the model failed** (down, timed out, unfinished answer) after its own retries. The
    question is UNANSWERED.
  - **exit 1 / 2 = local problem / usage** — fix the call.
- **A failed call is NOT evidence.** On any non-zero exit, never infer from partial/empty output and
  never advance a verdict or a move on it. Re-issue, fall back to subagents, or leave the probe
  incomplete and exit — the move is resumable; a later session retries. Treating a failed call as a
  finished answer silently corrupts the genealogy.
- Every answer ends with a validator line; claims whose pointers it lists as DISCARD are dropped.
  Spot-check the pointers you rely on.

## Move: GATHER  (recipe-baseline — what the field ALREADY does)
If SEED's `recipe-baseline` is still the "to be gathered" placeholder, this comes first. Collect the
known recipe(s) — the strongest existing approaches, products, papers, repos, practices — through
the reading tools, and write each as one cited line in SEED's `recipe-baseline`. This is the
adversary baseline that angles must beat, not our answer. Then STATE → IDEATE.

## Move: IDEATE  (generate angles — Claude, assumption-first, COLD)
1. Read the project's `the-assumption-to-attack` and `recipe-baseline` (must already be gathered;
   if missing, do GATHER instead).
2. **Attack the assumption.** Produce 1–3 angles that each either *beat* the baseline on a named
   axis or *sidestep* a named bottleneck. State for each: the assumption it breaks, the move, and
   the `must-beat` axis. **Reject an angle only if its *load-bearing move* (the one claim that would
   survive deleting every other clause) traces to a citation that covers that move.** An angle whose
   individual surfaces are all cited but whose *combination / sufficiency / replacement* claim is
   uncited-and-justified is an idea, not a summary — score the leap, not the clauses (a relabel of a
   cited mechanism → kill; cited surfaces + an uncited sufficiency claim → survive).
3. Every new angle must respect SEED's `constraints-proven` ledger — cite the `[Cn]` it steers around
   rather than re-discovering it.
4. Append to `projects/P/angles.md` per `templates/ANGLE.md` with `parent`/`mutation` set
   (orthogonal → `—`). Set the strongest to `status: probing`; STATE → probe it next.

## Move: PROBE  (feasibility deep-dive on one angle → verdict)
The angle generates **cheaply-answerable feasibility questions** — for software/ML: "does hook X
exist at file:line? memory at target size? does the library expose this?"; for other domains: the
equivalent primary-source lookups, calculations or tiny prototypes that would prove or disprove the
move. For each:
- **Gather, don't read yourself.** Adversarial web triage + source/doc spelunking → `fleet/gather.sh`
  / `fleet/draft.sh` or subagents. They return cited notes; you spot-check the pointers. Follow the
  exit-code rules above.
- Reason over the cited evidence → verdict on the verdict ladder (default DOWN when unsure):
  `pursue` (feasible + original; every load-bearing assumption proven or carrying a cheap test) /
  `needs-test` (one falsifiable experiment named) / `kill` (a concrete blocker).
- **On needs-test, build the experiment.** `mkdir -p projects/P/experiments && cp -R templates/experiment projects/P/experiments/<id>`
  and fill its `experiment.env` (setup, smoke and launch commands, artifacts, resources). An
  experiment is not ready until its **smoke** passes (`run.sh smoke` → `state/SMOKE_OK` for the
  current harness rev). If it isn't smoke-green, don't debug it in this judgment session: set STATE's
  next move to `DEVOPS <exp-id>` with `NEXT-TIER: devops` and exit. Once smoke-green, submit the full
  run through the runner (see Experiments), record its JOB_ID in STATE, and set `NEXT-TIER: wait`.
  **In SAFE mode** you never run or submit anything: both the smoke and the full run are run-gates
  (see Permission modes); the approved job comes back as `gates/<id>.job` for you to adopt.
  Anything that would cost money → a gate first (CLAUDE.md rule 7).
- **On kill:** write the one-line `kill-lesson` (the reusable constraint) into the angle AND into the
  project's `constraints-proven` ledger in SEED.md as `[Cn]`. Later angles must cite it, not
  re-discover it.
- **On pursue:** status → `survived`; next move is DOSSIER.

## Move: DEVOPS  (make an experiment run — cheap tier, never a judgment session)
Selected when STATE says `DEVOPS <exp-id>` (the loop runs it on the devops model). Iterate *within
this one session*: `run.sh smoke` → read the failure → patch the experiment dir (its env file,
scripts, dependencies) → re-smoke, until `state/SMOKE_OK` exists for the current rev, or you have
made several honest attempts without progress. Run the smoke through `bin/tinker-run submit` when
it needs a GPU or is long; short CPU smokes may run inline. Record each lesson that will matter
again as one line in the experiment's README ("symptom → cause → fix"). Never change what the
experiment *tests* — only what makes it run. **In SAFE mode** each smoke attempt is a run-gate:
read the previous attempt's job log (`bin/tinker-run log <JOB_ID>`) and `state/SMOKE_FAIL`, patch,
raise a new run-gate for the next smoke, exit — one attempt per session. On success: STATE → back to the PROBE step that
submits the full run, `NEXT-TIER: judgment`. If stuck: write a short dossier
`dossiers/<exp-id>-stuck.md` (what was tried, the blocking error, what would unblock it), raise
`bin/gate.sh P <exp-id>-stuck "experiment won't run"`, mark the angle `blocked(gate)`, exit.

## Experiments (lifecycle — STATE's `## Experiments` block is the machine-read source of truth)
Submit (FULL AUTONOMY mode; in SAFE mode the same command goes into a run-gate's `--run`):
`bin/tinker-run submit --project P --name <exp-id> --vram <GB, 0 = CPU> --class <workload-tag> --cwd projects/P/experiments/<exp-id> --cmd './run.sh render'`
It prints the JOB_ID. Each tracked job is one line in STATE:
`- <label> job=<JOB_ID> status=<pending|running|done|failed> <note>`.
`bin/tinker-run status <JOB_ID>` exits 0 done · 1 failed · 2 running · 3 pending · 4 missing;
`bin/tinker-run log <JOB_ID>` shows its output. Every session reconciles this block before acting.
On a terminal job (done OR failed) the session does BOTH: **(a)** resolves the best EVALUABLE ARTIFACT
on disk — the first existing of `FINAL_ARTIFACT` then `EVAL_ARTIFACTS` (best → worst) declared in the
experiment's `experiment.env` — and if one exists AND no verdict is yet recorded, surfaces it to the
user's verdict gate (`bin/gate.sh P <id> "<title>" <artifact-path>`; say PARTIAL in the title when it
came from a failed job); and **(b)** on failure, ALSO diagnoses from the job log and routes repair to
DEVOPS. The verdict trigger is ARTIFACT EXISTENCE, NOT exit code — a job that died in a late polish
stage but left an evaluable artifact still earns the human verdict; only when NO evaluable artifact
exists is a failure verdict-silent (diagnose/repair only). Then rewrite `status=` so the loop stops
waking on it. A still-running job with no other eligible move → IDLE (the loop polls cheaply and
wakes you when it finishes).

## Move: DOSSIER  (the gate — survivor only)
Write `projects/P/dossiers/<angle-id>.md` per `templates/DOSSIER.md`: the assumption broken, the
move, why it beats the baseline, the feasibility evidence (cited), the cheapest first experiment,
and what resuming this chain means concretely. Write it for a smart non-specialist: plain words
first, detail after. Then `bin/gate.sh P <angle-id> "<short title>"` → the user reads
`gates/<angle-id>.html` and replies in `gates/<angle-id>.answer.md`. Mark the angle `blocked(gate)`;
exit. When the answer arrives (gate reconciliation above): on **"in"** (or "yes", "go"), a later session resumes the
chain (deep-dive → build/test); on **"out"** (or "kill", "no"), kill it with the user's reason as the kill-lesson, and
IDEATE produces the next angle; on **free-form feedback**, treat it as the user's steer — fold it
into the angle (a mutation) or SEED, and re-probe if it changes feasibility.

## Move: HOUSEKEEPING
Keep genealogy tidy; archive settled angles; keep `angles.md` thin; keep the project `README.md`
an accurate ≤1-screen catch-up (status line per angle + pointers). **Keep `STATE.md` ≤ its line
budget (40):** a resolved saga (a closed race, a cleared blocker, a settled deviation) collapses to
a ONE-LINE pointer (the durable lesson + `see logs/…` or `see SEED.md [Cn]`), never the blow-by-blow;
proven constraints move to SEED's `constraints-proven` ledger and STATE cites `[Cn]`. The loop FORCES
this move when STATE is over budget — compact well under it (≈80%) so one pass buys several moves of
headroom. Every session that writes STATE sets `NEXT-TIER:` for the next move (`judgment` default;
`devops` for experiment repair; `wait` for a bare poll-a-job-and-exit).

## Cost & honesty
Devops → its own cheap-tier move, never a cold judgment session. Long reading calls → background
or subagents. No autonomous spending (CLAUDE.md rule 7). Report verdicts faithfully — `needs-test`
is not `pursue`; ambiguity is never confirmation; a missing citation is a missing fact.
