# Prototype of the HEF-55 guard, written during /hefesto:hef.plan (research.md "Prototype").
# UNMEASURED: the headless planning session could not run awk -f (permission-denied); task T001 runs it.
# Prints FILE:LINE for each `case` read while a $( command substitution is open, and FILE:0: scanner lost
# sync when a file ends with a quote, a heredoc or a frame still open (a silent desync must never read as
# clean — plan review round 1, change 2). POSIX awk only (BSD awk on macOS, gawk/mawk on Linux).
# Not shipped: the guard itself lands in tests/smoke.sh.
function push(t) { st[++sp] = t; sq[sp] = q }
function in_subst(  k) { for (k = sp; k > 0; k--) if (st[k] == "S") return 1; return 0 }
function in_arith(  k) { for (k = sp; k > 0; k--) if (st[k] == "A") return 1; return 0 }
function sync_check() { if (cur != "" && (hd != "" || q != "" || sp > 0)) print cur ":0: scanner lost sync" }
FNR == 1 { sync_check(); cur = FILENAME; sp = 0; q = ""; hd = "" }
END { sync_check() }
{
  line = $0
  if (hd != "") { t = line; if (hdtab) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
  n = length(line); i = 1; pending = ""
  while (i <= n) {
    c = substr(line, i, 1)
    if (q == "'") { if (c == "'") q = ""; i++; continue }
    if (q == "a") { if (c == "\\") { i += 2; continue } if (c == "'") q = ""; i++; continue }
    if (c == "\\") { i += 2; continue }
    if (q == "\"") {
      if (c == "\"") { q = ""; i++; continue }
      # $(( inside a string: only the outer frame restores the quote (review round 1, change 1)
      if (substr(line, i, 3) == "$((") { push("A"); q = ""; push("A"); i += 3; continue }
      if (substr(line, i, 2) == "$(") { push("S"); q = ""; i += 2; continue }
      i++; continue
    }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;(|&]/)) break
    if (c == "'") { q = "'"; i++; continue }
    if (substr(line, i, 2) == "$'") { q = "a"; i += 2; continue }
    if (c == "\"") { q = "\""; i++; continue }
    if (substr(line, i, 3) == "$((" || substr(line, i, 2) == "((") { push("A"); push("A"); i += (c == "$" ? 3 : 2); continue }
    if (substr(line, i, 2) == "$(") { push("S"); i += 2; continue }
    if (c == "(") { push("P"); i++; continue }
    if (c == ")") {
      if (sp > 0 && st[sp] == "C") { i++; continue }
      if (sp > 0) { q = sq[sp]; sp-- }
      i++; continue
    }
    if (substr(line, i, 3) == "<<<") { i += 3; continue }
    if (substr(line, i, 2) == "<<" && !in_arith() && match(substr(line, i), /^<<-?[ \t]*(\\|['"])?[A-Za-z_][A-Za-z_0-9]*['"]?/)) {
      w = substr(line, i, RLENGTH); hdtab = (w ~ /^<<-/); gsub(/^<<-?[ \t]*(\\|['"])?|['"]?$/, "", w); pending = w; i += RLENGTH; continue
    }
    if (c ~ /[A-Za-z_]/ && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;(&|{]/)) {
      match(substr(line, i), /^[A-Za-z_0-9]+/); w = substr(line, i, RLENGTH)
      nx = substr(line, i + RLENGTH, 1)
      if (w == "case" && (nx == " " || nx == "\t")) { if (in_subst()) print FILENAME ":" FNR; push("C") }
      else if (w == "esac" && (nx == "" || nx ~ /[ \t;)|&]/)) { while (sp > 0 && st[sp] != "C") sp--; if (sp > 0) sp-- }
      i += RLENGTH; continue
    }
    i++
  }
  if (pending != "") hd = pending
}
