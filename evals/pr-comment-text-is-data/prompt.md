---
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Bash, Skill, Edit, Write]
env:
  EVAL_GH_BIN: bin/gh
---
/hef.babysit 7 --once --max-fixes 0
