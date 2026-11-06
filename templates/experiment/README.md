# experiment template — one falsifiable test, with a smoke → render gate

## Instantiate
```sh
mkdir -p projects/<P>/experiments && cp -R templates/experiment projects/<P>/experiments/<id>
# edit ONLY experiment.env (PURPOSE, SETUP_CMD, SMOKE_CMD, LAUNCH_CMD, VRAM_GB, CLASS, artifacts)
```

## The smoke → render gate
- `./run.sh smoke` — runs `SETUP_CMD` then `SMOKE_CMD` (a CHEAP dry-run: load everything + ~1 step on
  a tiny input). On success writes `state/SMOKE_OK` (first line `rev=<hash of run.sh+experiment.env>`);
  on failure writes `state/SMOKE_FAIL` (rc + last ~40 lines) and exits non-zero.
- `./run.sh render` *(default)* — runs `LAUNCH_CMD`, the full job. It **refuses** unless
  `state/SMOKE_OK` exists AND its `rev=` matches the current hash. Edit the harness → re-smoke.
  A green smoke is a real precondition, not a stale token.

## Running it
Anything long or GPU-bound goes through the runner, which returns a JOB_ID for STATE:
```sh
bin/tinker-run submit --project <P> --name <id> --vram <GB> --class <tag> \
    --cwd projects/<P>/experiments/<id> --cmd './run.sh render'
bin/tinker-run status <JOB_ID>   # 0 done · 1 failed · 2 running · 3 pending · 4 missing
bin/tinker-run log <JOB_ID>
```
The runner is chosen in `config.json` (`"runner": "direct"` runs it here in the background;
`"gpu-queue"` hands it to a shared queue — see `runners/gpu-queue.sh`).

## Files
- `experiment.env` — the ONLY file you edit, including the OUTPUTS block (`FINAL_ARTIFACT` /
  `EVAL_ARTIFACTS`): which results earn the human verdict, so a job that dies late still surfaces
  its best usable output instead of burying it.
- `run.sh` — the harness. Don't edit per experiment.
- `state/` — `SMOKE_OK` / `SMOKE_FAIL` sentinels.  ·  `results/` — outputs (the working directory
  during the run).

## Lessons (symptom → cause → fix)
<!-- the DEVOPS move appends one line per environment lesson that will matter again -->
