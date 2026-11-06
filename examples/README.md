# examples/

**These are illustrative examples, not real research.** Each one shows what a project folder
looks like right after its birth conversation, so you can see what Claude writes before the loop
takes over.

- `fair-chores/` — splitting household chores in a shared home. Just born: SEED, README and STATE
  are filled in; no angles, dossiers or gates yet; the recipe-baseline is still "to be gathered"
  (the loop's first move collects it, with citations).

To watch the loop work on one:

```bash
cp -R examples/fair-chores projects/
tinker start fair-chores
tinker log fair-chores
```
