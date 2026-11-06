# tinkerloop — the invention loop

This system runs **exploratory R&D**, not cataloging. The web is an *adversary* that tries to prove
an idea is already done or infeasible — never the source of the answer. A session that just
retrieves the field's recipe has failed. The deliverable is an *original, feasibility-proven angle*.

## The shape of the system (read this before doing anything)
Work is split into **projects** — one topic each, fully decoupled, living in `projects/<slug>/`.
The interactive main thread (you, talking to the user) does **only two things**:
1. **Project birth.** `tinker start <new-slug>` opens you with a birth brief. The user talks through
   a topic with you until you're aligned; then you **copy `templates/project/` into
   `projects/<slug>/` and fill it out** for that topic (SEED, README, STATE, angles header) and add
   the `PROJECTS.md` row. That is the whole point of the conversation. Then you stop.
2. **Gates and verdicts** the user brings to you: help them read a dossier or a result and write
   their answer into `projects/<slug>/gates/<id>.answer.md`.
   (*Cross-project linking* — surfacing an idea that links two projects — is not active. Don't.)

Everything *between* birth and a finished topic is autonomous: `tinker start <slug>` launches
`bin/tinker-loop`, which chains headless `claude -p` sessions, each doing exactly ONE move per
`loop/PROTOCOL.md`, until the project hits a stopping point (a user gate, or IDLE = no eligible
move). The user can run `tinker start` as often as they like; all state is in files and every move
is resumable. **Idea generation is topic-specific and lives inside each project's folder** — never
globally.

**Catch-up rule (how the main thread holds the big picture cheaply):** read `PROJECTS.md` — the
registry — then the relevant project's `README.md`. Those two give you the whole landscape without
re-reading detail files. Don't open a project's angles/dossiers unless the current task touches it.

## Inverted hybrid (the cost model)
Reading is offloaded; thinking is not. Bulk reading — web triage, source-code spelunking, doc/log
digestion — goes to cheap readers: the user's **local models** via `fleet/gather.sh` (the `reader`
role: extract cited facts) and `fleet/draft.sh` (the `drafter` role: cited first drafts), or to
Explore-style **subagents**. The main thread and each loop session hold **judgment only**: idea
generation, feasibility verdicts, the gate. Spend tokens on reasoning, not on reading. A local
model NEVER judges idea-worth — it gathers cited evidence; Claude decides.

**Local models are optional.** `config.json` may configure none, one, or both roles. When a fleet
script exits **4** ("no local model configured"), that is not an error: do the reading yourself
with subagents / your own tools, under the same citation rules. Exit **3** means a configured model
failed — the question is unanswered (see PROTOCOL); you may retry, or fall back to subagents.

A third bucket is neither reading nor judgment: **devops** (making an experiment's environment
run). It is stateful, cumulative trial-and-error — wrong to debug cold, one error per session, on
the judgment tier. It runs as its own move on the cheaper tier (`NEXT-TIER: devops`, see PROTOCOL).

## Citation firewall = novelty firewall
Every gathered fact cites `file:line` / URL; uncited claims are discarded, not argued with. The same
lens scores ingenuity, applied to the angle's **load-bearing move**, not clause-by-clause: an angle
whose surfaces are all cited but whose *combination / sufficiency / replacement* claim is
uncited-and-justified is an idea, not a summary. Reasoning must show up as that
**uncited-but-justified leap**. Never fabricate a citation or a piece of evidence; "not yet
gathered" is always an acceptable state.

## Nouns (the file schema)
- **Project** — one topic, `projects/<slug>/`, fully self-contained; the unit the loop drives.
  Domain-agnostic schema. Many can run in parallel, decoupled.
- **Angle** — one assumption-attack (the unit of ingenuity), in the project's `angles.md`.
- **Probe** — the feasibility deep-dive on an angle → go / needs-test / no-go.
- **Dossier** — the write-up a probe survivor earns; the thing the gate shows the user.
- **Gate** — a decision only the user makes: `gates/<id>.html` to read, `gates/<id>.answer.md`
  to answer, `gates/INDEX.md` to see what's pending.
- **Experiment** — a falsifiable test run via `bin/tinker-run` (runner from `config.json`).

## Determinism & where the user differs
The control flow is **deterministic**: STATE points at the next move; PROTOCOL fixes what each move
does. The user is pulled in **only at stopping points that need human judgment** — the gate
(go/no-go on a survived angle), any experimental/visual verdict an angle requires, and any spend.
Everywhere else the loop decides for itself and writes back.

## Session rules (cost discipline — follow exactly)
1. **Interactive session?** You're here for project birth or a gate/verdict the user raised. Align,
   write/fill the project files, stop. Do NOT run the loop yourself — that's `tinker start`'s job.
2. **Loop session?** You're given an active project `P`; follow `loop/PROTOCOL.md` for exactly ONE
   move on `projects/P/`, write back, exit. Never touch another project.
3. **Delegate reading** to local models / subagents; keep distilled, cited conclusions only.
4. **Genealogy is load-bearing:** every angle records `parent` / `mutation` / `kill-lesson`.
5. **Gate is deep-dive-only:** only a survived probe writes a dossier + runs `bin/gate.sh P <id>`.
6. **Loop sessions never edit the system itself** (`CLAUDE.md`, `loop/`, `bin/`, `fleet/`,
   `runners/`, `templates/`). If the system needs a change, say so in the project's STATE / a gate.
7. **No autonomous spending.** Paid APIs, paid cloud compute, purchases, sign-ups: never on your
   own. If a move genuinely needs one, stop and raise a gate whose write-up states what, why, the
   estimated cost and why no free/local substitute works; proceed only on the user's explicit "in".

8. **Safe by default.** Unless the loop says FULL AUTONOMY, loop sessions read, search and write
   inside this folder but run no code: experiments go through run-gates the user approves with
   `run`, and the loop driver (not Claude) executes them (PROTOCOL → Permission modes).
9. **A denied tool call is final.** Never retry it or reach the same effect another way (other
   command, tool, script, file trick). Raise a gate naming the exact command and why it's needed,
   mark the move blocked, exit.

Full per-move protocol: `loop/PROTOCOL.md`.
