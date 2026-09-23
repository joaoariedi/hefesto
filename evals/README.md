# Plugin evals

Behavioural cases for `claude plugin eval` — each prompt is run **with and without** the plugin
(the `with-without` ablation arm) and scored by graders, so the result measures whether the
framework's prompts change behaviour, not whether the model is capable.

```bash
claude plugin eval . --trust-plugin --scaffold --allow-tools Bash --threshold 0.8      # local; spends tokens
claude plugin eval . --trust-plugin --scaffold --allow-tools Bash --json results.json  # machine-readable, for a nightly job
```

`--scaffold` runs each case's `scaffold.sh` first: the eval workspace is **empty** by default, and the
first real run proved that both arms answer "there is no project here" to every prompt. Each case
now ships a small git repo with real code for the prompt to act on. `--allow-tools Bash` lets the
with-arm run the `hef.*` pre-flight helpers, and lets the destructive-command case exercise the
hook that blocks the force push. The CLI **refuses** that grant unless it can confine the shell:
on Linux that means `bubblewrap` and `socat` installed (`pacman -S bubblewrap socat` /
`apt install bubblewrap socat`). Without them, drop the flag — the cases still run and the graders
still score the reply; only the Bash-dependent evidence (helper output, the hook firing) is absent.
`--keep-temp` preserves each run's `out/trace.jsonl`, the only place the transcript survives.

Measured 2026-09-23 with the backend installed: the eval sandbox also **denies the `git` binary**
(`permission denied: git` in both arms), so the destructive-command case never reaches the
`block-destructive-commands.sh` hook — the model reads `.git/refs` by hand and refuses on the
evidence. That case therefore measures the *reply*; the hook itself is proven by the mutation-tested
fixtures in `tests/smoke.sh`. Its `tool_used` grader (`push --force` called 0 times) stays: it is the
guard that would catch a with-arm regression if the sandbox ever let git through.

Layout: one directory per case, `evals/<case>/case.yaml` — the CLI resolves `case.yaml` (or `prompt.md` + `graders/*.md`), not top-level `<name>.yaml`; a flat file is silently ignored and the run reports zero cases. The case format is `schema_version: "1.1"`, `name`, the prompt and run limits under `execution:`, `plugins: ["../.."]` so the plugin under test resolves, and graders typed `regex | tool_used | tool_order | file_exists | llm | baseline` (an `llm` grader's rubric is `criteria`; a judge model votes PASS in two of three). Results land in `evals/results/` (gitignored — they hold full prompts and transcripts). `claude plugin eval init` scaffolds new cases in this format.

Not run by `tests/smoke.sh` or the PR path: it needs an authenticated CLI and spends tokens, the
same reason the live smoke tier is opt-in. The structural check in the smoke suite only asserts
that every case parses and carries at least one grader.

Seeding rule (Anthropic's eval guidance): cases come from **real failures**, balanced between
positive and negative, 20–50 over time. Four are the review's named failure modes — spec-first
routing, destructive-command refusal, root-cause before fix, and effort sizing without hour
estimates — and the fifth, `no-ceremony-for-trivial`, is their mirror: a one-word typo must be
fixed, not routed into the pipeline. It exists because 7.0 made the session-start hook state the
routing rule, and a rule that pushes work *up* needs a guard that it does not push trivial work
up too (the ~10× ceremony cost the SDD critics measured). Add a case when a session does the wrong
thing. A case the model already passes without the plugin is worth keeping only as a **regression
guard** against the plugin making it worse — say so in its description, as the zero-Δ cases here do.
