#!/usr/bin/env bash
# Tests for mailbox/lock_run.sh: acquire and release hooks, and plain locking without hooks.
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
check "watchdog: stopped (took ${took}s)" '[ $took -le 25 ]'
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

echo "lock_run tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
