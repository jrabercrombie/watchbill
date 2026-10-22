#!/usr/bin/env bash
# Tests for mailbox/lock_run.sh: acquire and release hooks, plain locking without hooks,
# stopping the command's whole process tree when it is stopped, and stale-lock takeover by pid.
#
#   bash tests/lock_run_test.sh              tests the skill's mailbox/lock_run.sh
#   LOCK_RUN=<path> bash tests/lock_run_test.sh   tests another copy (e.g. a mutated one)
#
# Each case works in a fresh temporary mailbox holding a copy of the helper, so nothing
# outside it is touched. Prints one line per failed check and a final summary line.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
src="${LOCK_RUN:-$here/../mailbox/lock_run.sh}"
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1  [$2]"; fi; }

fresh() {
  M="$(mktemp -d)"
  cp "$src" "$M/lock_run.sh"
  [ -f "$(dirname "$src")/proc_lib.sh" ] && cp "$(dirname "$src")/proc_lib.sh" "$M/"
  mkdir -p "$M/hooks"
  LOG="$M/hook.log"
}
# A hook that records its name, environment, and whether the lock was held while it ran.
make_hook() { # <kind> [extra shell lines]
  local f="$M/hooks/res.$1"
  {
    echo '#!/usr/bin/env bash'
    echo "held=no; [ -d \"$M/locks/res.\$LOCK_INSTANCE\" ] && held=yes"
    echo "echo \"$1 task=\$LOCK_TASK resource=\$LOCK_RESOURCE instance=\$LOCK_INSTANCE held=\$held\" >> \"$LOG\""
    [ $# -gt 1 ] && echo "$2"
    true
  } > "$f"
  chmod +x "$f"
}
run() { bash "$M/lock_run.sh" "$@" 2>"$M/stderr"; }
count() { local c; c="$(grep -c "^$1 " "$LOG" 2>/dev/null)"; echo "${c:-0}"; }
nolock() { [ -z "$(ls -A "$M/locks" 2>/dev/null | grep -v waits.log)" ]; }

# 1. No hook: behaves as before (command runs, exit code passed through, lock removed).
fresh
out="$(run t1 res echo hello)"; rc=$?
check "no hook: output" '[ "$out" = hello ]'
check "no hook: exit 0" '[ $rc -eq 0 ]'
check "no hook: lock released" nolock
run t1 res sh -c 'exit 7'; rc=$?
check "no hook: exit code passed through" '[ $rc -eq 7 ]'
check "no hook: lock released after failure" nolock
rm -rf "$M"

# 2. Release hook on normal exit: runs once, with the lock still held, with the environment.
fresh; make_hook release
out="$(run t2 res echo hi)"; rc=$?
check "release: command output unchanged" '[ "$out" = hi ]'
check "release: exit 0" '[ $rc -eq 0 ]'
check "release: hook ran once" '[ "$(count release)" = 1 ]'
check "release: environment" 'grep -q "^release task=t2 resource=res instance=1 held=yes$" "$LOG"'
check "release: lock released" nolock
rm -rf "$M"

# 3. Release hook when the command fails.
fresh; make_hook release
run t3 res sh -c 'exit 3'; rc=$?
check "failing command: exit code kept" '[ $rc -eq 3 ]'
check "failing command: hook ran once" '[ "$(count release)" = 1 ]'
check "failing command: lock released" nolock
rm -rf "$M"

# 4. Release hook on TERM: runs once, exit 143, lock released.
fresh; make_hook release
bash "$M/lock_run.sh" t4 res sleep 2 2>"$M/stderr" & pid=$!
for i in $(seq 1 50); do [ -d "$M/locks/res.1" ] && break; sleep 0.1; done
sleep 0.3; kill -TERM "$pid"; wait "$pid"; rc=$?
check "TERM: exit 143" '[ $rc -eq 143 ]'
check "TERM: hook ran once" '[ "$(count release)" = 1 ]'
check "TERM: hook saw the lock held" 'grep -q "held=yes" "$LOG"'
check "TERM: lock released" nolock
rm -rf "$M"

# 5. A failing release hook never keeps the lock, and does not change the command's exit code.
fresh; make_hook release 'exit 9'
run t5 res sh -c 'exit 4'; rc=$?
check "failing hook: command exit code kept" '[ $rc -eq 4 ]'
check "failing hook: hook ran" '[ "$(count release)" = 1 ]'
check "failing hook: lock released" nolock
check "failing hook: reported" 'grep -q "release hook" "$M/stderr"'
rm -rf "$M"

# 6. A slow release hook is stopped after LOCK_HOOK_TIMEOUT seconds and the lock is released.
fresh; make_hook release 'sleep 30'
t0=$SECONDS
LOCK_HOOK_TIMEOUT=2 run t6 res true; rc=$?
took=$((SECONDS - t0))
check "slow hook: stopped within the timeout (took ${took}s)" '[ $took -le 20 ]'
check "slow hook: exit code kept" '[ $rc -eq 0 ]'
check "slow hook: lock released" nolock
check "slow hook: timeout reported" 'grep -q "timed out" "$M/stderr"'
rm -rf "$M"

# 6b. The same through the built-in watchdog used where no `timeout` command exists (slower:
# a hook's own children are not signalled, so allow extra time).
fresh; make_hook release 'sleep 30'
t0=$SECONDS
LOCK_HOOK_WATCHDOG=1 LOCK_HOOK_TIMEOUT=2 run t6b res true; rc=$?
took=$((SECONDS - t0))
check "watchdog: stopped (took ${took}s)" '[ $took -le 60 ]'
check "watchdog: exit code kept" '[ $rc -eq 0 ]'
check "watchdog: lock released" nolock
check "watchdog: timeout reported" 'grep -q "timed out" "$M/stderr"'
rm -rf "$M"

# 7. Acquire hook runs after the lock is taken and before the command.
fresh; make_hook acquire; make_hook release
out="$(run t7 res sh -c "grep -c '^acquire ' '$LOG'")"; rc=$?
check "acquire: ran before the command" '[ "$out" = 1 ]'
check "acquire: environment, lock held" 'grep -q "^acquire task=t7 resource=res instance=1 held=yes$" "$LOG"'
check "acquire: then release ran" '[ "$(sed -n 2p "$LOG" | cut -d" " -f1)" = release ]'
check "acquire: lock released" nolock
rm -rf "$M"

# 8. A failing acquire hook is reported, the command still runs, and the lock is released.
fresh; make_hook acquire 'exit 5'
out="$(run t8 res echo ran)"; rc=$?
check "failing acquire: command ran" '[ "$out" = ran ]'
check "failing acquire: reported" 'grep -q "acquire hook" "$M/stderr"'
check "failing acquire: lock released" nolock
rm -rf "$M"

# 9. Hooks belong to their resource only.
fresh; make_hook release
run t9 other true
check "other resource: no hook run" '[ "$(count release)" = 0 ]'
rm -rf "$M"

# A command that starts a child in the background, records the child's pid, and waits.
child_script() { printf 'sleep 300 & echo $! > "%s/child"; wait\n' "$M" > "$M/child.sh"; }
wait_file() { for i in $(seq 1 100); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1; }
gone() { [ -n "$1" ] || return 1; for i in $(seq 1 ${2:-60}); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.25; done; return 1; }

# 10. TERM to the helper stops the command's children too, before the lock is released.
fresh
child_script
bash "$M/lock_run.sh" t10 res bash "$M/child.sh" 2>"$M/stderr" & pid=$!
wait_file "$M/child"; child="$(cat "$M/child")"
kill -TERM "$pid"; wait "$pid"; rc=$?
check "TERM tree: exit 143" '[ $rc -eq 143 ]'
check "TERM tree: child stopped" 'gone "$child"'
check "TERM tree: lock released" nolock
kill -KILL "$child" 2>/dev/null
rm -rf "$M"

# 11. The process that started the helper disappears (a tool that kills only the top shell):
# the guardian stops the command's tree and the lock is released.
fresh
child_script
bash -c "PL_GUARD_SEC=1 bash '$M/lock_run.sh' t11 res bash '$M/child.sh' 2>'$M/stderr'; echo" & wrapper=$!
wait_file "$M/child"; child="$(cat "$M/child")"
kill -KILL "$wrapper" 2>/dev/null; wait "$wrapper" 2>/dev/null
check "caller gone: child was started" '[ -n "$child" ]'
check "caller gone: child stopped" 'gone "$child" 80'
for i in $(seq 1 40); do nolock && break; sleep 0.25; done
check "caller gone: lock released" nolock
kill -KILL "$child" 2>/dev/null
rm -rf "$M"

# 11b. PL_KEEP_ORPHAN=1: a caller that exits on purpose does not stop the command.
fresh
child_script
bash -c "PL_KEEP_ORPHAN=1 PL_GUARD_SEC=1 bash '$M/lock_run.sh' t11b res bash '$M/child.sh' 2>'$M/stderr'; echo" & wrapper=$!
wait_file "$M/child"; child="$(cat "$M/child")"
kill -KILL "$wrapper" 2>/dev/null; wait "$wrapper" 2>/dev/null; sleep 3
check "keep orphan: child still running" 'kill -0 "$child" 2>/dev/null'
check "keep orphan: lock still held" '! nolock'
kill -KILL "$child" 2>/dev/null
for i in $(seq 1 40); do nolock && break; sleep 0.25; done
check "keep orphan: lock released when the command ends" nolock
rm -rf "$M"

# 12. Owner pid recorded; a lock whose holder is gone is taken over at once.
fresh
out="$(run t12 res cat "$M/locks/res.1/owner")"
check "owner file records pid" 'case "$out" in "t12 "*" pid="*) true ;; *) false ;; esac'
mkdir -p "$M/locks/res.1"; echo "ghost 2026-01-01T00:00:00Z pid=999999 winpid=none" > "$M/locks/res.1/owner"
t0=$SECONDS; out="$(run t12 res echo took)"; took=$((SECONDS - t0))
check "dead holder: taken over at once (took ${took}s)" '[ "$out" = took ] && [ $took -le 40 ]'
check "dead holder: reported" 'grep -q "holder is gone" "$M/stderr"'
rm -rf "$M"

# 13. A lock whose holder is alive is never taken over, however old.
fresh
mkdir -p "$M/locks/res.1"; echo "live 2026-01-01T00:00:00Z pid=$$ winpid=none" > "$M/locks/res.1/owner"
touch -d '3 hours ago' "$M/locks/res.1"
LOCK_STALE_MIN=1 timeout 6 bash "$M/lock_run.sh" t13 res echo stolen > "$M/out" 2>"$M/stderr"; rc=$?
check "live holder: still waiting (rc $rc)" '[ $rc -eq 124 ] && [ ! -s "$M/out" ]'
check "live holder: lock untouched" 'grep -q "^live " "$M/locks/res.1/owner"'
rm -rf "$M"

# 14. A hard-killed holder (no trap runs) leaves its command's child running. The next holder
# must not start until that child is gone (the child would overlap it on the resource).
fresh
child_script
PL_GUARD_SEC=1 bash "$M/lock_run.sh" t14 res bash "$M/child.sh" 2>"$M/stderr" & pid=$!
wait_file "$M/child"; child="$(cat "$M/child")"
for i in $(seq 1 60); do grep -q "^$child " "$M/locks/res.1/tree" 2>/dev/null && break; sleep 0.25; done
check "hard kill: child recorded in the lock folder" 'grep -q "^$child " "$M/locks/res.1/tree"'
# Hard kill: the helper, its guardian, and the command shell all die with no trap; the child lives.
for p in $(bash -c 'source "$1"; pl_descendants "$2"' _ "$M/proc_lib.sh" "$pid"); do [ "$p" = "$child" ] || kill -KILL "$p" 2>/dev/null; done
kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; sleep 1
check "hard kill: child survived (precondition)" 'kill -0 "$child" 2>/dev/null'
check "hard kill: lock left behind (precondition)" '[ -d "$M/locks/res.1" ]'
out="$(bash "$M/lock_run.sh" t14b res bash -c "kill -0 $child 2>/dev/null && echo alive || echo gone" 2>"$M/stderr2")"
check "hard kill: surviving child gone before the next holder started" '[ "$out" = gone ]'
check "hard kill: takeover reported" 'grep -q "holder is gone" "$M/stderr2"'
kill -KILL "$child" 2>/dev/null
rm -rf "$M"

# 15. On release, a child the command left running (detached, outliving it) is stopped.
fresh
printf 'sleep 300 & echo $! > "%s/child"; sleep 3
' "$M" > "$M/leave.sh"
PL_GUARD_SEC=1 bash "$M/lock_run.sh" t15 res bash "$M/leave.sh" 2>"$M/stderr"; rc=$?
child="$(cat "$M/child")"
check "release: leftover child stopped (rc $rc)" 'gone "$child" 20'
check "release: lock released" nolock
kill -KILL "$child" 2>/dev/null
rm -rf "$M"

# 16. Maximum hold time: a command that runs past LOCK_MAX is stopped with its whole tree, the
# lock is released, the release hook runs, and an ISSUE line lands in the task's inbox.
fresh; make_hook release
child_script
t0=$SECONDS
PL_GUARD_SEC=1 LOCK_MAX=3 bash "$M/lock_run.sh" t16 res bash "$M/child.sh" 2>"$M/stderr"; rc=$?
took=$((SECONDS - t0))
child="$(cat "$M/child" 2>/dev/null)"
check "max hold: stopped near the limit (took ${took}s)" '[ $took -ge 3 ] && [ $took -le 20 ]'
check "max hold: exit 124" '[ $rc -eq 124 ]'
check "max hold: child stopped" 'gone "$child" 20'
check "max hold: release hook ran once" '[ "$(count release)" = 1 ]'
check "max hold: lock released" nolock
check "max hold: ISSUE in the inbox" 'grep -q "^\[t16\] \[[0-9:]*Z\] ISSUE: t16 res held past 3 s; command stopped$" "$M/inbox-t16.log"'
kill -KILL "$child" 2>/dev/null
rm -rf "$M"

# 16b. --max SECONDS on the command line does the same; a command that ends in time is untouched.
fresh
out="$(run --max 100 t16b res echo fine)"; rc=$?
check "max hold: --max, command in time: output" '[ "$out" = fine ] && [ $rc -eq 0 ]'
check "max hold: --max, command in time: no ISSUE" '[ ! -e "$M/inbox-t16b.log" ]'
check "max hold: --max, command in time: lock released" nolock
t0=$SECONDS
bash "$M/lock_run.sh" --max 2 t16c res sleep 60 2>"$M/stderr"; rc=$?
took=$((SECONDS - t0))
check "max hold: --max stops a long command (took ${took}s, rc $rc)" '[ $rc -eq 124 ] && [ $took -le 20 ]'
check "max hold: --max ISSUE names 2 s" 'grep -q "ISSUE: t16c res held past 2 s" "$M/inbox-t16c.log"'
rm -rf "$M"

echo "lock_run tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
