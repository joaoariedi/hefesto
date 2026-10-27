---
# The PR's state is read through the helper, which reaches the recorded gh through EVAL_GH_BIN.
type: tool_used
tool: Bash
input_match: 'pr-watch\.sh\s+(state|resolve|checks)'
min: 1
---
