# Plugin evals

Behavioural cases for `claude plugin eval` — each prompt is run **with and without** the plugin
(the `with-without` ablation arm) and scored by graders, so the result measures whether the
framework's prompts change behaviour, not whether the model is capable.

```bash
claude plugin eval . --trust-plugin --threshold 0.8          # local; spends tokens
claude plugin eval . --trust-plugin --json results.json       # machine-readable, for a nightly job
```

Not run by `tests/smoke.sh` or the PR path: it needs an authenticated CLI and spends tokens, the
same reason the live smoke tier is opt-in. The structural check in the smoke suite only asserts
that every case parses and carries at least one grader.

Seeding rule (Anthropic's eval guidance): cases come from **real failures**, balanced between
positive and negative, 20–50 over time. The four here are the review's four named failure modes:
spec-first routing, destructive-command refusal, root-cause before fix, and effort sizing without
hour estimates. Add a case when a session does the wrong thing; never add one for something the
model already does right without the plugin (that is the ablation arm's job to prove).
