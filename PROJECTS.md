# PROJECTS — the registry (main thread's catch-up index)

Read this first in an interactive session, then the relevant project's `README.md`. That's the
whole big picture; don't re-read detail files unless a move touches them. (`tinker status` shows
the same list with live loop state.)

**The flow:** the user runs `tinker start <slug>` → Claude talks it through until aligned →
copies `templates/project/` into `projects/<slug>/`, fills it for the topic, adds a row here →
the loop runs by itself. Claude is pulled back in only at a gate, a verdict, or a new birth.

## Active projects
| slug | topic | status | README |
|------|-------|--------|--------|

## Conventions
- New project: kebab-case slug, `cp -R templates/project projects/<slug>`, fill SEED + README,
  add the row above. (Cross-project idea-linking is not active — don't wire projects together.)
- Per-project runtime (`state/`, `logs/`, `jobs/`, gate `*.html`) is loop runtime; the rest is
  the project's record. `projects/` is kept out of the tinkerloop git repo — version it
  separately if you like.
