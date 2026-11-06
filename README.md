# tinkerloop

**Talk through an idea once. tinkerloop keeps tinkering on it while you're away.**

You describe a topic you're curious about: a problem at work, a hobby project, something you
wish existed. tinkerloop then runs on its own. It looks at what people already do, comes up
with fresh angles, checks whether each one could actually work, and only interrupts you when
an idea is promising enough to need your decision.

> **Status: early.** This works, but it's young. Expect rough edges and please report them.

---

## How it works (the 30-second version)

```
   you ──talk──► Claude ──writes──► a project folder
                                        │
                     ┌──────────────────┘
                     ▼
          ┌───────────────────────────────┐
          │  the loop (runs by itself)     │
          │  1. gather what's known        │  ◄── reading: local models (cheap)
          │  2. invent new angles          │  ◄── thinking: Claude
          │  3. test if each could work    │
          │  4. write up the survivors     │
          └──────────────┬────────────────┘
                         ▼
                 a "gate": you decide yes / no
```

Two simple rules keep it honest:

- **Cheap helpers read, Claude thinks.** Reading lots of pages and code is the expensive part.
  If you have a local model (optional), it does the reading and Claude does the judging.
- **Everything is cited.** Every fact must point to where it came from (a link, a file and line).
  Anything without a source is thrown away.

---

## What you need

| | Needed? | Notes |
|---|---|---|
| A Mac or Linux computer | **Yes** | On Windows, use WSL. |
| [Claude Code](https://claude.com/claude-code) + a Claude plan | **Yes** | Claude is the part that thinks. |
| `git`, `bash`, `jq`, `curl` | **Yes** | Usually already installed. |
| A local model (Ollama, LM Studio, vLLM…) | Optional | Makes long research much cheaper. |
| A GPU | Optional | Only if your topic needs to *run* experiments. |

No special hardware is required. With nothing but Claude Code it still works; it just costs
more Claude usage.

---

## Setup (about 10 minutes)

**1. Get the code**

```bash
git clone https://github.com/AdarshaSubedi/tinkerloop.git
cd tinkerloop
./install.sh            # puts the `tinker` command on your PATH
```

**2. Tell it about your models (optional, so you can skip this)**

```bash
cp config.example.json config.json
```

Open `config.json` and fill in whatever you have. Any server that speaks the OpenAI-style API
works. For example, [Ollama](https://ollama.com) on your own laptop:

```json
{
  "reader":  { "url": "http://localhost:11434/v1", "model": "qwen3:8b" },
  "drafter": { "url": "http://localhost:11434/v1", "model": "qwen3:32b" },
  "runner":  "direct"
}
```

- `reader`: a small, fast model that reads and pulls out facts.
- `drafter`: a bigger model that writes first drafts. It can be the same as `reader`.
- `runner`: how experiments run. `direct` means "just run them here."

Leave a model out and Claude does that job itself.

**3. Check everything is ready**

```bash
tinker doctor
```

It reports what it found (Claude Code, your models, a GPU) and what's missing, in plain words.

---

## Your first project

```bash
tinker start my-first-idea
```

- `my-first-idea` is a short name for the topic, lowercase with dashes.
- Claude opens and **asks you questions** until it understands two things: what the topic is,
  and which common assumption is worth challenging. Answer in normal language; there are no
  wrong answers.
- When it's clear, Claude creates `projects/my-first-idea/` and the loop **starts by itself in
  the background**. You can close the terminal.

---

## Day-to-day

| Command | What it does |
|---|---|
| `tinker status` | Lists all your projects and which ones are running. |
| `tinker status my-first-idea` | Shows one project: running, idle, or waiting for you. |
| `tinker log my-first-idea` | Watch it work live. Ctrl-C stops watching, not the loop. |
| `tinker stop my-first-idea` | Pauses it after the current step. Nothing is lost. |
| `tinker start my-first-idea` | Resumes a paused or finished project. Safe to run any time. |

### When it needs you

The loop only stops for you at a **gate**. There are two kinds:

- **Idea gates:** an idea survived testing and needs a yes or no.
- **Run gates:** the loop wants to run some code (an experiment) and needs your OK first.
  The page shows the exact command, the folder it runs in, and what it needs.

1. Open `projects/my-first-idea/gates/INDEX.md`. Anything marked **pending** is waiting on you.
2. Open the matching `.html` file in your browser to read the write-up.
3. Write your decision in the matching `.answer.md` file. For an idea: `in`, `kill`, or a
   sentence of feedback. For a run gate: `run` to approve it, or anything else (say why) to decline.

That's it. A running loop notices your answer within a few minutes and carries on.

### Safety: what it can do on its own

By default the loop is careful. On its own it can only:

- read files and search the web,
- write files inside the `tinkerloop` folder.

It **runs no code without your OK**. When an experiment needs to run, you get a run gate; answer
`run` and tinkerloop (not Claude) runs exactly the command you saw. If the code or command changes
after you were asked, it refuses to run it and asks again.

**To allow more**, add rules to `.claude/settings.local.json` (your own file, kept out of git).
It uses [Claude Code's permission rules](https://code.claude.com/docs/en/permissions).

**Full autonomy** (`TINKER_SKIP_PERMISSIONS=1 tinker start <name>`) lets Claude run experiments
itself, with no run gates. Be honest with yourself about what that means: **Claude can then run
any command on your computer, unsupervised**, for hours. Only do this on a separate user account
or a virtual machine with nothing you'd hate to lose.

---

## What's in the box

```
tinkerloop/
├── README.md             ← you are here
├── config.example.json   ← copy to config.json (optional)
├── bin/                  ← the `tinker` command
├── loop/                 ← the rules each step follows (PROTOCOL.md)
├── fleet/                ← helpers that send reading to your local models
├── runners/              ← how experiments run: direct (default) or a GPU queue
├── templates/            ← what a new project starts from
├── examples/             ← a small example project to look at
└── projects/             ← your projects live here (kept out of git)
```

Your projects stay on your computer. Nothing is uploaded anywhere except what Claude Code
itself sends to Claude.

---

## Common questions

**Does it cost money?**
It uses your Claude plan. Each step is one Claude session, and you can cap a run with
`MAX_SESSIONS=10 tinker start <name>`. If you hit a usage limit, the loop waits and retries
instead of burning through more. A local model lowers the cost a lot.

**What kinds of topics work?**
Anything where you want *new* ideas, not just a summary: a better way to do something, a tool
that doesn't exist yet, a fix nobody has tried. It is not built for "write me a report on X."

**Can I run several projects at once?**
Yes. Each project is fully separate.

**I don't have a GPU. Is that a problem?**
No. A GPU only matters if a project needs to run heavy experiments (for example, training or
generating video). Most topics never do.

**Something broke.**
Run `tinker doctor` first. Then check `tinker log <name>`. If you're stuck, open an issue on
GitHub with the output.

---

## License

MIT. Use it, change it, share it.
