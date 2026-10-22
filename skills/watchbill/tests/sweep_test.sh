#!/usr/bin/env bash
# Tests for mailbox/sweep.sh: it lists and stops only leftovers of its own mailbox.
#
#   bash tests/sweep_test.sh                  tests the skill's mailbox/sweep.sh
#   SWEEP=<path> bash tests/sweep_test.sh     tests another copy (proc_lib.sh and lock_run.sh
#                                             are taken from the same folder)
#
# Builds a throwaway repository folder with a mailbox and two worktrees (task "fin" has
# reported DONE ALL, task "act" has not), then starts:
#   A  an orphaned watcher pipeline (tail | grep | cut on an inbox, its top shell killed), and
#   H  an unrelated sleep started by that same shell (same process group, not in the pipeline)
#   B  the same pipeline shape on a file outside the mailbox (must never be touched)
#   C  an unrelated sleep (must never be touched)
#   D  a command from fin's worktree holding a live lock through lock_run.sh (in use: spared)
#   E  a command from fin's worktree with no lock (leftover)
#   F  a polling loop waiting on a file in fin's worktree (leftover)
#   G  a command from act's worktree (task live: kept)
# plus a lock folder whose recorded holder is gone.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
sw="${SWEEP:-$here/../mailbox/sweep.sh}"
lib="$(dirname "$sw")"
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1  [$2]"; fi; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
gone() { [ -n "$1" ] || return 1; for i in $(seq 1 40); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.25; done; return 1; }
wait_file() { for i in $(seq 1 100); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1; }
# Members of process group <pgid>, from ps (works on MSYS and POSIX).
group_of() { ps -eo pid=,pgid= 2>/dev/null | awk -v g="$1" '$2 == g { print $1 }' 2>/dev/null \
  || ps | awk -v g="$1" 'NR > 1 && $3 == g { print $1 }'; }
members() { local m; m="$(group_of "$1")"; [ -n "$m" ] || m="$(ps | awk -v g="$1" 'NR > 1 && $3 == g { print $1 }')"; echo $m; }

T="$(mktemp -d)"; R="$T/repo"; MB="$R/.agent-mail"
mkdir -p "$MB/locks" "$R/.worktrees/fin" "$R/.worktrees/act" "$T/other"
cp "$sw" "$MB/sweep.sh"; cp "$lib/proc_lib.sh" "$lib/lock_run.sh" "$MB/"
printf '[fin] [10:00:00Z] STATUS #1 PLAN: x\n[fin] [10:30:00Z] DONE ALL: abc\n' > "$MB/inbox-fin.log"
printf '[act] [10:00:00Z] STATUS #1 PLAN: y\n' > "$MB/inbox-act.log"
: > "$T/other/x.log"

# A and B: pipelines in their own process group whose top shell is then killed, as when a
# tool stops a Monitor on Windows.
start_orphan_pipeline() { # <dir> <file> <leader-file> [<extra command run first>]
  ( set -m; bash -c "cd '$1' && ${4:-} tail -F '$2' | grep --line-buffered NEVER | cut -c1-5" >/dev/null 2>&1 & echo $! > "$3" )
}
start_orphan_pipeline "$R" ".agent-mail/inbox-act.log" "$T/A.leader" "{ sleep 305 & echo \$! > '$T/H.pid'; } ;"
start_orphan_pipeline "$T/other" "x.log" "$T/B.leader"
sleep 2
A_lead="$(cat "$T/A.leader")"; B_lead="$(cat "$T/B.leader")"
H="$(cat "$T/H.pid" 2>/dev/null)"
A_mem="$(members "$A_lead" | tr ' ' '
' | grep -vx "${H:-x}" | tr '
' ' ')"; B_mem="$(members "$B_lead")"
kill -KILL "$A_lead" "$B_lead" 2>/dev/null; sleep 1
A_mem="$(for p in $A_mem; do alive "$p" && echo "$p"; done)"
B_mem="$(for p in $B_mem; do alive "$p" && echo "$p"; done)"
check "setup: A left an orphaned pipeline" '[ "$(echo $A_mem | wc -w)" -ge 3 ]'
check "setup: H started in A's group" 'alive "$H"'
check "setup: B left an orphaned pipeline" '[ "$(echo $B_mem | wc -w)" -ge 3 ]'

sleep 301 >/dev/null 2>&1 & C=$!
( set -m; bash -c "bash '$MB/lock_run.sh' fin res bash -c \"cd '$R/.worktrees/fin' && echo \\\$\\\$ > '$T/D.pid' && exec sleep 302\"" >/dev/null 2>&1 & )
wait_file "$T/D.pid"; D="$(cat "$T/D.pid")"
bash -c "cd '$R/.worktrees/fin' && exec sleep 303" >/dev/null 2>&1 & E=$!
bash -c "until [ -f '$R/.worktrees/fin/never.done' ]; do sleep 1; done" >/dev/null 2>&1 & F=$!
bash -c "cd '$R/.worktrees/act' && exec sleep 304" >/dev/null 2>&1 & G=$!
mkdir -p "$MB/locks/gone.1"; echo "ghost 2026-01-01T00:00:00Z pid=999999 winpid=none" > "$MB/locks/gone.1/owner"
sleep 1

# Dry run: lists A's pipeline, E and F as leftovers, D and G as kept; B and C never appear.
out="$(bash "$MB/sweep.sh" 2>&1)"; rc=$?
echo "$out" > "$T/dry.txt"
listed() { grep -E "^    pid $1 " "$T/dry.txt" | head -n1; }
check "dry run: exit 0" '[ $rc -eq 0 ]'
for p in $A_mem; do check "dry run: watcher member $p listed as leftover" 'awk -v p="$p" "/^(LEFTOVER|keep)/{v=\$1} \$1==\"pid\" && \$2==p {print v}" "$T/dry.txt" | grep -qx LEFTOVER'; done
check "dry run: watcher group named" 'grep -q "^LEFTOVER watcher" "$T/dry.txt"'
check "dry run: task process E leftover" 'awk -v p="$E" "/^(LEFTOVER|keep)/{v=\$1} \$1==\"pid\" && \$2==p {print v}" "$T/dry.txt" | grep -qx LEFTOVER'
check "dry run: loop F leftover" 'awk -v p="$F" "/^(LEFTOVER|keep)/{v=\$1} \$1==\"pid\" && \$2==p {print v}" "$T/dry.txt" | grep -qx LEFTOVER'
check "dry run: lock holder D kept" 'awk -v p="$D" "/^(LEFTOVER|keep)/{v=\$1} \$1==\"pid\" && \$2==p {print v}" "$T/dry.txt" | grep -qx keep'
check "dry run: live task G kept" 'awk -v p="$G" "/^(LEFTOVER|keep)/{v=\$1} \$1==\"pid\" && \$2==p {print v}" "$T/dry.txt" | grep -qx keep'
for p in $B_mem $C $H; do check "dry run: unrelated $p not listed" '[ -z "$(listed "$p")" ]'; done
check "dry run: dead lock listed" 'grep -q "LEFTOVER lock: .*gone.1" "$T/dry.txt"'
check "dry run: nothing stopped" 'alive "$E" && alive "$F" && alive "$(echo $A_mem | cut -d" " -f1)"'
check "dry run: dead lock not yet removed" '[ -d "$MB/locks/gone.1" ]'

# --kill: stops only the leftovers.
bash "$MB/sweep.sh" --kill > "$T/kill.txt" 2>&1; rc=$?
check "kill: exit 0 (rc $rc)" '[ $rc -eq 0 ]'
for p in $A_mem; do check "kill: watcher member $p stopped" 'gone "$p"'; done
check "kill: E stopped" 'gone "$E"'
check "kill: F stopped" 'gone "$F"'
check "kill: lock holder D spared" 'alive "$D"'
check "kill: live lock kept" '[ -d "$MB/locks/res.1" ]'
check "kill: live task G spared" 'alive "$G"'
for p in $B_mem $C $H; do check "kill: unrelated $p spared" 'alive "$p"'; done
check "kill: dead lock removed" '[ ! -d "$MB/locks/gone.1" ]'

# --done marks a live task finished.
out="$(bash "$MB/sweep.sh" --done act 2>&1)"
check "--done: G now leftover" 'echo "$out" | awk -v p="$G" "/^(LEFTOVER|keep)/{v=\$1} \$1==\"pid\" && \$2==p {print v}" | grep -qx LEFTOVER'
out="$(bash "$MB/sweep.sh" --done act --keep act 2>&1)"
check "--keep: G kept" 'echo "$out" | awk -v p="$G" "/^(LEFTOVER|keep)/{v=\$1} \$1==\"pid\" && \$2==p {print v}" | grep -qx keep'

if [ "$fail" -gt 0 ]; then echo "--- dry run output"; cat "$T/dry.txt"; echo "--- kill output"; cat "$T/kill.txt"; fi

# Tidy up everything this test started.
for p in $B_mem $C $H $D $G $A_mem $E $F; do kill -KILL "$p" 2>/dev/null; done
pkill -f "$R" 2>/dev/null
lr="$(ps -eo pid=,args= 2>/dev/null | awk -v r="$R" 'index($0, r) { print $1 }')"; [ -n "$lr" ] && kill -KILL $lr 2>/dev/null
for i in $(seq 1 20); do [ ! -d "$MB/locks/res.1" ] && break; sleep 0.25; done
rm -rf "$T"

echo "sweep tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
