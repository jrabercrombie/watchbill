#!/usr/bin/env bash
# sweep.sh [--kill] [--done <task>,...] [--only <task>,...] [--keep <task|pid>,...]
#
# Finds processes this mailbox left behind and, with --kill, stops them. Dry run by default:
# it lists what it would stop and what it keeps, and why.
#
# Why: on Windows (Git Bash), stopping a shell kills only that shell, so the rest of its
# pipeline and its children keep running. One night 113 orphaned tail/grep/cut processes
# (about 583 MB) from re-armed mailbox watchers piled up, next to duplicate polling loops and
# test shards whose wrapper had been stopped; the process churn put half the CPU in the kernel.
#
# What it looks at: only processes that reference this mailbox or one of its worktrees, by
# command line, working directory, or open files, plus their pipeline partners (joined to them
# by a pipe: one's stdout is the other's stdin) and their children. Nothing else is ever
# listed or stopped.
#
# Leftover (stopped with --kill):
#   watcher  a mailbox watcher pipeline (tail of the inboxes, or watch.sh) whose top shell is
#            gone, or a watch.sh that is not the current one in .watch.pid
#   loop     a polling loop (until/while ... sleep) whose task is finished, or one on the
#            mailbox alone whose shell is gone
#   task     a process started from .worktrees/<task> whose task is finished: the worktree is
#            gone, the task is named in --done, or its inbox's last signal line is DONE ALL
# In use (never stopped):
#   - anything in the tree, process group, or ancestry of a live lock holder (the pid recorded
#     in locks/*/owner by lock_run.sh), of the current watcher (.watch.pid), or of this sweep
#   - processes of a task that is still live, and other processes that use the mailbox
# Agents run inside the controller's session, not as processes of their own, so a task's
# liveness is read from its worktree and inbox; --done names tasks the controller knows are over.
#
# It also tidies mailbox state nothing uses: lock folders whose recorded holder is gone,
# and a .watch.pid or .watch-tick.* left by a watcher that is no longer running.
#
# --only limits the sweep to the named tasks' processes (cleanup.sh uses it). --keep, and the
# lines of <mail>/sweep.keep (a task name or a pid per line), mark processes as in use: use it
# for anything run from a worktree on purpose after its agent finished, such as a build the
# user is trying out.
# Windows: process data from /proc (MSYS) plus PowerShell Get-CimInstance for native
# programs; stops with kill and taskkill /F /T. POSIX: /proc or ps, and kill.
set -u
mail="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=proc_lib.sh
. "$mail/proc_lib.sh" || { echo "sweep: proc_lib.sh missing next to sweep.sh" >&2; exit 1; }
root="$(cd "$mail/.." && pwd -P)"
# Other spellings of the root that command lines may use: the path as given (/tmp/x is a
# mount of C:/Users/.../Temp/x on MSYS), and the Windows forms.
rootw="$(cd "$(dirname "$0")/.." && pwd -L)"
if command -v cygpath >/dev/null 2>&1; then
  rootw="$rootw|$(cygpath -m "$root")|$(cygpath -m "$rootw")|$(cygpath -u "$(cygpath -m "$rootw")")"
fi
KILL=0; DONE_LIST=""; ONLY=""; KEEP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kill) KILL=1; shift ;;
    --done) DONE_LIST="$DONE_LIST,$2"; shift 2 ;;
    --only) ONLY="$ONLY,$2"; shift 2 ;;
    --keep) KEEP="$KEEP,$2"; shift 2 ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "usage: sweep.sh [--kill] [--done t1,t2] [--only t1,t2] [--keep t1,pid2]" >&2; exit 64 ;;
  esac
done

# --- live tasks (builtins and one awk: a project can have a hundred worktrees) -----------
tasks=(); inboxes=()
for d in "$root"/.worktrees/*/; do
  [ -d "$d" ] || continue
  t="${d%/}"; t="${t##*/}"; tasks+=("$t")
  [ -f "$mail/inbox-$t.log" ] && inboxes+=("$mail/inbox-$t.log")
done
finished=","
if [ "${#inboxes[@]}" -gt 0 ]; then
  finished=",$(awk '/STATUS|ISSUE|QUESTION|DONE|TO |CLAIM/ { last[FILENAME] = $0 }
    END { for (f in last) if (last[f] ~ /DONE ALL/) { sub(/.*\/inbox-/, "", f); sub(/\.log$/, "", f); printf "%s,", f } }' "${inboxes[@]}")"
fi
live=""
for t in "${tasks[@]}"; do
  case ",$DONE_LIST,$finished" in *",$t,"*) continue ;; esac
  live="$live,$t"
done

if [ -f "$mail/sweep.keep" ]; then
  while read -r k _; do case "$k" in ''|'#'*) ;; *) KEEP="$KEEP,$k" ;; esac; done < "$mail/sweep.keep"
fi

# --- protected bases: this sweep, the current watcher, live lock holders -----------------
prot=""
watcher=""
if [ -f "$mail/.watch.pid" ]; then
  read -r watcher _ < "$mail/.watch.pid"
  if pl_alive "$watcher"; then prot="$prot $watcher"; else watcher=""; fi
fi
stale_locks=()
for o in "$mail"/locks/*/owner; do
  [ -f "$o" ] || continue
  pl_owner_alive "$o"; s=$?
  if [ "$s" -eq 0 ]; then
    line=""; read -r line < "$o"; p="${line##* pid=}"; prot="$prot ${p%% *}"
  elif [ "$s" -eq 1 ]; then
    stale_locks+=("$(dirname "$o")")
  fi
done

# --- process table: src pid winpid ppid pgid wppid cmd cwd fds --------------------------
tab="$(mktemp)"; trap 'rm -f "$tab" "$tab".*' EXIT
clean() { local s="$1"; s="${s//$'\t'/ }"; s="${s//$'\n'/ }"; s="${s//$'\r'/}"; printf '%s' "$s"; }
if [ -r /proc/self/cmdline ]; then
  # Working directories and open files, two listings for all processes at once.
  ls -l /proc/[0-9]*/cwd 2>/dev/null | sed -n 's#^.* /proc/\([0-9]*\)/cwd -> \(.*\)$#\1\t\2#p' > "$tab.cwd"
  # Open files, and which pipe is each process's stdin and stdout (pipeline partners).
  ls -l /proc/[0-9]*/fd/ 2>/dev/null | awk '
    /^\/proc\/[0-9]+\/fd\/?:$/ { split($0, a, "/"); p = a[3]; seen[p] = 1; next }
    / -> / && p != "" {
      i = index($0, " -> "); t = substr($0, i + 4); n = split(substr($0, 1, i - 1), w, " ")
      if (t ~ /^\//) f[p] = f[p] "|" t
      else if (t ~ /^pipe:/ && w[n] == "0") pin[p] = t
      else if (t ~ /^pipe:/ && w[n] == "1") pout[p] = t
    }
    END { for (p in seen) print p "\t" f[p] "\t" pin[p] "\t" pout[p] }' > "$tab.fd"
  for d in /proc/[0-9]*; do
    p="${d#/proc/}"
    [ -r "$d/cmdline" ] || continue
    pp=""; pg=""; w=""
    if [ -r "$d/ppid" ]; then
      read -r pp < "$d/ppid" 2>/dev/null; read -r pg < "$d/pgid" 2>/dev/null
      read -r w < "$d/winpid" 2>/dev/null
    elif [ -r "$d/stat" ]; then
      st=""; read -r st < "$d/stat" 2>/dev/null; st="${st##*) }"
      set -- $st; pp="${2:-}"; pg="${3:-}"
    fi
    [ -n "$pp" ] || continue
    a=(); mapfile -d '' -t a < "$d/cmdline" 2>/dev/null
    printf 'M\t%s\t%s\t%s\t%s\t\t%s\n' "$p" "${w:-}" "$pp" "${pg:-$p}" "$(clean "${a[*]:-}")"
  done > "$tab.m"
else
  : > "$tab.cwd"; : > "$tab.fd"
  ps -eo pid=,ppid=,pgid=,args= 2>/dev/null | awk '{ p=$1; pp=$2; pg=$3; $1=$2=$3=""; sub(/^ +/, ""); gsub(/\t/, " "); printf "M\t%s\t\t%s\t%s\t\t%s\n", p, pp, pg, $0 }' > "$tab.m"
fi
: > "$tab.w"
if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  wr="$(cygpath -w "$root")"; mr="$(cygpath -m "$root")"
  # Every process's pid and parent; the command line only where it names this repository.
  powershell.exe -NoProfile -NonInteractive -Command "
    \$w = '*$wr\\*'; \$m = '*$mr/*'
    Get-CimInstance Win32_Process | ForEach-Object {
      \$c = ''; if (\$_.CommandLine -and (\$_.CommandLine -like \$w -or \$_.CommandLine -like \$m)) { \$c = (\$_.CommandLine -replace '[\t\r\n]', ' ') }
      'W' + [char]9 + [char]9 + \$_.ProcessId + [char]9 + [char]9 + [char]9 + \$_.ParentProcessId + [char]9 + \$c
    }" 2>/dev/null | tr -d '\r' > "$tab.w"
fi
cat "$tab.m" "$tab.w" > "$tab"

# --- classify ---------------------------------------------------------------------------
plan="$(awk -F '\t' -v mail="$mail" -v root="$root" -v live="$live" -v prot="$prot" -v self="$$" -v rootw="$rootw" \
  -v watcher="$watcher" -v only="$ONLY" -v keep="$KEEP" -v cwdf="$tab.cwd" -v fdf="$tab.fd" '
function norm(s,   i, out) {
  s = tolower(s); gsub(/\\/, "/", s)
  out = ""
  while (match(s, /[a-z]:\//)) { out = out substr(s, 1, RSTART - 1) "/" substr(s, RSTART, 1) "/"; s = substr(s, RSTART + 3) }
  return out s
}
# Other spellings of the root (see rootw) are rewritten to the canonical one.
function alias(s,   i, j, x) {
  for (j = 1; j <= nrw; j++) { x = rws[j]; if (x == "" || x == R) continue; while ((i = index(s, x))) s = substr(s, 1, i - 1) R substr(s, i + length(x)) }
  return s
}
function isshell(t) { return t ~ /^"?[^ ]*(^|\/)(ba|da|z)?sh(\.exe)?"?( |$)/ }
function under(c, base) { return c == base || index(c, base "/") == 1 }
function wtask(s, pre,   i, r) {
  i = index(s, pre); if (!i) return ""
  r = substr(s, i + length(pre)); sub(/[\/ "\047|;&)].*$/, "", r); return r
}
# partners: add the processes joined to k by a pipe (the stdout of k is their stdin, or the reverse).
function partners(u, k,   n, a, j) {
  if (src[k] != "M") return
  n = split((pout[pid[k]] != "" ? inby[pout[pid[k]]] : "") " " (pin[pid[k]] != "" ? outby[pin[pid[k]]] : ""), a, " ")
  for (j = 1; j <= n; j++) if (!(a[j] in unitof) && !(a[j] in S)) { addunit(u, a[j]); partners(u, a[j]) }
}
# isorphan: the process lost the shell that started it (its group leader, or its parent, is gone).
function isorphan(k,   L) {
  if (src[k] != "M") return !(("w" wpar[k]) in wk) && !(("w" wpar[k]) in src)
  L = "m" pgid[k]
  if (!(L in src)) return 1
  return pid[k] != pgid[k] && (ppid[k] == 1 || !(("m" ppid[k]) in src))
}
function addunit(u, k) { if (!(k in unitof) && !(k in S)) { unitof[k] = u; members[u] = members[u] " " k } }
function desc(u, k,   n, a, j) { n = split(kids[k], a, " "); for (j = 1; j <= n; j++) if (!(a[j] in unitof)) { addunit(u, a[j]); desc(u, a[j]) } }
function sdesc(k, X,   n, a, j) { n = split(kids[k], a, " "); for (j = 1; j <= n; j++) if (!(a[j] in X)) { X[a[j]] = 1; sdesc(a[j], X) } }
# closure: each base pid, its ancestors, (with sib) its pipeline siblings (same parent and
# process group), and every descendant of the base and of those siblings.
function closure(list, X, sib,   n, a, i, k, b, j, m, g, Q) {
  n = split(list, a, " ")
  for (i = 1; i <= n; i++) {
    b = "m" a[i]; if (!(b in src)) continue
    Q[b] = 1
    if (sib && src[b] == "M") { m = split(grp[pgid[b]], g, " "); for (j = 1; j <= m; j++) if (parent[g[j]] == parent[b]) Q[g[j]] = 1 }
    k = parent[b]; while (k in src && !(k in X)) { X[k] = 1; k = parent[k] }
  }
  for (k in Q) { X[k] = 1; sdesc(k, X) }
}
BEGIN {
  N = norm(mail); R = norm(root); W = R "/.worktrees/"
  nrw = split(rootw, rws, "|"); for (i = 1; i <= nrw; i++) rws[i] = norm(rws[i])
  n = split(live, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") islive[a[i]] = 1
  n = split(only, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") isonly[a[i]] = 1
  n = split(keep, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") iskeep[a[i]] = 1
  while ((getline l < cwdf) > 0) { i = index(l, "\t"); cwd[substr(l, 1, i - 1)] = substr(l, i + 1) }
  while ((getline l < fdf) > 0) { split(l, x, "\t"); fds[x[1]] = x[2]; pin[x[1]] = x[3]; pout[x[1]] = x[4] }
}
$1 == "M" { k = "m" $2; src[k] = "M"; pid[k] = $2; win[k] = $3; ppid[k] = $4; pgid[k] = $5; cmd[k] = $7
            if ($3 != "") wk["w" $3] = k; order[++cnt] = k; next }
$1 == "W" { k = "w" $3; if (k in wk) { wpar[wk[k]] = $6; next }
            src[k] = "W"; win[k] = $3; wpar[k] = $6; cmd[k] = $7; order[++cnt] = k }
END {
  for (i = 1; i <= cnt; i++) {
    k = order[i]
    if (src[k] == "M") { par = "m" ppid[k]; if (par in src && par != k) parent[k] = par; grp[pgid[k]] = grp[pgid[k]] " " k }
    else { par = "w" wpar[k]; if (par in wk) par = wk[par]; if (par in src && par != k) parent[k] = par }
    if (k in parent) kids[parent[k]] = kids[parent[k]] " " k
  }
  # In use: protected bases with their ancestors, process groups, and descendants.
  closure(prot, P, 1)
  # This sweep itself is left out of the listing altogether.
  closure(self, S, 0)
  # Seeds: processes that reference the mailbox or a worktree.
  for (i = 1; i <= cnt; i++) {
    k = order[i]; if (k in S) continue
    t = alias(norm(cmd[k])); c = (src[k] == "M") ? alias(norm(cwd[pid[k]])) : ""; f = (src[k] == "M") ? alias(norm(fds[pid[k]])) : ""
    rel = under(c, R)
    refm = index(t, N) || under(c, N) || index(f, N "/") || (rel && t ~ /(^|[ "\047])\.agent-mail\//)
    tk = wtask(t, W); if (tk == "") tk = wtask(c "/", W); if (tk == "") tk = wtask(f, W)
    if (tk == "" && rel) tk = wtask(t, ".worktrees/")
    kind = ""
    if (refm && ((t ~ /(^|[ \/"])tail(\.exe)?"? / && (t ~ /inbox-/ || f ~ /inbox-/)) || t ~ /watch\.sh/)) kind = "watcher"
    else if ((refm || tk != "") && t ~ /(until|while)[ (!].*sleep/) kind = "loop"
    # A shell counts as started from a worktree only by its working directory: a live tool
    # shell may merely mention a worktree path in its command text.
    else if (tk != "" && (!isshell(t) || wtask(c "/", W) != "")) kind = "task"
    else if (refm) kind = "other"
    if (kind != "") { seedkind[k] = kind; seedtask[k] = tk }
  }
  rank["watcher"] = 4; rank["loop"] = 3; rank["task"] = 2; rank["other"] = 1
  # Pipe links: a process whose stdout is the stdin of another is its partner.
  for (i = 1; i <= cnt; i++) {
    k = order[i]; if (src[k] != "M") continue
    if (pout[pid[k]] != "") outby[pout[pid[k]]] = outby[pout[pid[k]]] " " k
    if (pin[pid[k]] != "") inby[pin[pid[k]]] = inby[pin[pid[k]]] " " k
  }
  # Units: a seed with its pipeline partners, then (below) their children.
  for (i = 1; i <= cnt; i++) {
    k = order[i]; if (!(k in seedkind) || (k in S)) continue
    if (k in unitof) u = unitof[k]; else { u = k; addunit(u, k); partners(u, k) }
    if (!(u in ukind) || rank[seedkind[k]] > rank[ukind[u]]) ukind[u] = seedkind[k]
    if (seedtask[k] != "" && utask[u] == "") utask[u] = seedtask[k]
    if (!(u in uord)) { uord[u] = ++nu; ulist[nu] = u }
  }
  for (i = 1; i <= nu; i++) { u = ulist[i]; m = split(members[u], g, " "); for (j = 1; j <= m; j++) desc(u, g[j]) }
  for (i = 1; i <= nu; i++) { u = ulist[i]; m = split(members[u], g, " "); for (j = 1; j <= m; j++) if (isorphan(g[j])) orphan[u] = 1 }
  for (i = 1; i <= nu; i++) {
    u = ulist[i]; kind = ukind[u]; tk = utask[u]
    if (only != "" && !(tk in isonly)) continue
    inuse = 0; m = split(members[u], g, " "); for (j = 1; j <= m; j++) if (g[j] in P) inuse = 1
    iscur = 0; for (j = 1; j <= m; j++) if (src[g[j]] == "M" && pid[g[j]] == watcher) iscur = 1
    haswatch = 0; for (j = 1; j <= m; j++) if (cmd[g[j]] ~ /watch\.sh/) haswatch = 1
    verdict = "KEEP"
    kept = (tk in iskeep); for (j = 1; j <= m; j++) if ((src[g[j]] == "M" && pid[g[j]] in iskeep) || (win[g[j]] != "" && win[g[j]] in iskeep)) kept = 1
    if (kept) why = "listed in --keep or sweep.keep"
    else if (inuse) why = iscur ? "the current watcher" : "in use (a live lock holder, the current watcher, or this sweep)"
    else if (kind == "watcher") {
      if (orphan[u]) { verdict = "STOP"; why = "watcher pipeline whose top shell is gone" }
      else if (haswatch && watcher != "") { verdict = "STOP"; why = "watch.sh that is not the current watcher" }
      else why = "a running watcher whose shell is alive (stop its Monitor to end it)"
    } else if (kind == "loop") {
      if (tk != "" && !(tk in islive)) { verdict = "STOP"; why = "polling loop of finished task " tk }
      else if (tk != "") why = "polling loop of live task " tk
      else if (orphan[u]) { verdict = "STOP"; why = "polling loop on the mailbox whose shell is gone" }
      else why = "polling loop on the mailbox, its shell still running"
    } else if (kind == "task") {
      if (!(tk in islive)) { verdict = "STOP"; why = "started from the worktree of finished task " tk }
      else why = "task " tk " is live"
    } else why = "uses the mailbox; not a watcher, loop, or task process"
    print "UNIT\t" verdict "\t" kind "\t" why
    for (j = 1; j <= m; j++) {
      k = g[j]; c = cmd[k]; if (length(c) > 160) c = substr(c, 1, 157) "..."
      print "PROC\t" verdict "\t" (src[k] == "M" ? pid[k] : "-") "\t" win[k] "\t" c
    }
  }
}' "$tab")"

# --- report and act ---------------------------------------------------------------------
echo "sweep: mailbox $mail"
l="${live#,}"; echo "sweep: live tasks: ${l:-none}"
[ -n "$watcher" ] && echo "sweep: current watcher pid $watcher"
stops=(); wins=()
nstop=0; nkeep=0
while IFS=$'\t' read -r kind a b c d; do
  case "$kind" in
    UNIT)
      if [ "$a" = STOP ]; then nstop=$((nstop + 1)); echo "LEFTOVER $b: $c"; else nkeep=$((nkeep + 1)); echo "keep     $b: $c"; fi ;;
    PROC)
      echo "    pid ${b} win ${c:-?}  ${d}"
      if [ "$a" = STOP ]; then
        if [ "$b" != "-" ]; then stops+=("$b"); elif [ -n "$c" ]; then wins+=("$c"); fi
      fi ;;
  esac
done <<< "$plan"
for l in "${stale_locks[@]}"; do echo "LEFTOVER lock: $l (its recorded holder is gone)"; done
pidf_stale=""
if [ -f "$mail/.watch.pid" ] && [ -z "$watcher" ]; then pidf_stale=1; echo "LEFTOVER state: .watch.pid of a watcher that is not running"; fi
ticks=()
for tf in "$mail"/.watch-tick.*; do
  [ -e "$tf" ] || continue
  tp="${tf#"$mail"/.watch-tick.}"; tp="${tp%%.*}"
  pl_alive "$tp" || ticks+=("$tf")
done
[ "${#ticks[@]}" -gt 0 ] && echo "LEFTOVER state: ${#ticks[@]} tick file(s) of watchers that are not running"

total=$(( ${#stops[@]} + ${#wins[@]} ))
if [ "$KILL" -eq 0 ]; then
  echo "sweep: dry run: $nstop leftover group(s), $total process(es) would be stopped; $nkeep kept. Run with --kill to act."
  exit 0
fi
[ "${#stops[@]}" -gt 0 ] && pl_kill_pids "${stops[@]}"
if [ "${#wins[@]}" -gt 0 ] && command -v taskkill.exe >/dev/null 2>&1; then
  for w in "${wins[@]}"; do MSYS_NO_PATHCONV=1 taskkill.exe /F /T /PID "$w" >/dev/null 2>&1; done
fi
for l in "${stale_locks[@]}"; do pl_owner_alive "$l/owner"; [ $? -eq 1 ] && rm -rf "$l"; done
[ -n "$pidf_stale" ] && rm -f "$mail/.watch.pid"
[ "${#ticks[@]}" -gt 0 ] && rm -f "${ticks[@]}"
left=0
for p in "${stops[@]}"; do pl_alive "$p" && left=$((left + 1)); done
echo "sweep: stopped $((total - left)) of $total process(es) in $nstop leftover group(s); $nkeep kept"
[ "$left" -eq 0 ]
