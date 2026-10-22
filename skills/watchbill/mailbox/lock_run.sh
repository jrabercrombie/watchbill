#!/usr/bin/env bash
# Run one command while holding a lock on an exclusive resource, then release it.
#
#   bash <mail>/lock_run.sh <task> <resource> <command...>
#
# A resource may have several interchangeable instances (two build machines, three device
# slots, two test databases). Declare them in <mail>/resources.conf, one resource per line:
#
#   <resource> = <instance> [<instance> ...]      e.g.   testdb = a b
#
# A resource not listed there has a single instance. The command runs with the chosen
# instance in $LOCK_INSTANCE (and $LOCK_RESOURCE, $LOCK_TASK), so it can pass it on (a device
# id, a port, a database name). Set LOCK_PREFER=<instance> to require one particular instance,
# e.g. when two measurements must be taken on the same hardware.
#
# Hooks: a shared device or service left in a changed state by one holder (a process still
# running, a setting changed, a file left open) spoils the next holder's work. If
# <mail>/hooks/<resource>.acquire is executable, it runs right after the lock is taken and
# before the command; if <mail>/hooks/<resource>.release is executable, it runs just before
# the lock is removed: on normal exit, on failure, and on TERM or INT. Both get LOCK_TASK,
# LOCK_RESOURCE and LOCK_INSTANCE, and should return the resource to a known state, quickly
# and idempotently. A hook is stopped after LOCK_HOOK_TIMEOUT seconds (default 60); a failing
# or stopped hook is reported on stderr and never keeps the lock held or changes the exit code.
#
# Guarantees: the command never runs without a lock; the helper only ever removes its own
# lock; a lock whose owner process is gone is taken over at once (the owner file records the
# holder's pid), and a lock with no pid in its owner file is taken over once it is older than
# LOCK_STALE_MIN minutes (default 30); a lock whose holder is alive is never taken over. It
# gives up with exit 75 after LOCK_WAIT_MIN minutes (default 30) of waiting.
# Agents use this helper instead of hand-written mkdir/rm locking.
#
# Stopping: if the command is stopped (TERM or INT to this helper, or this helper or the
# process that started it disappears), the command's whole process tree is stopped before the
# lock is released, so no orphan keeps using the resource. On Windows the tree is stopped
# with taskkill /T as well, because stopping a Git Bash shell leaves its children running.
# Starting it detached on purpose (`lock_run.sh ... &` in a shell that then exits)? Set
# PL_KEEP_ORPHAN=1 so the caller exiting is not taken as a stop. Needs proc_lib.sh next to it;
# without it the command runs unguarded, as before.
#
# To update this file while it may be running, write the new version to a temporary file in
# the same folder and rename it over this one. Never edit or copy over it in place: bash reads
# a script as it runs, so a running copy would continue with the new file's bytes.
set -u
if [ "$#" -lt 3 ]; then
  echo "usage: lock_run.sh <task> <resource> <command...>" >&2; exit 64
fi
task="$1"; resource="$2"; shift 2
mail="$(cd "$(dirname "$0")" && pwd)"
dir="$mail/locks"
mkdir -p "$dir"
have_lib=""
# shellcheck source=proc_lib.sh
if [ -f "$mail/proc_lib.sh" ] && . "$mail/proc_lib.sh"; then have_lib=1; fi

instances=""
if [ -f "$mail/resources.conf" ]; then
  instances="$(sed -n "s/^[[:space:]]*$resource[[:space:]]*=[[:space:]]*//p" "$mail/resources.conf" | head -n1)"
fi
[ -n "$instances" ] || instances="1"
if [ -n "${LOCK_PREFER:-}" ]; then instances="$LOCK_PREFER"; fi

stale="${LOCK_STALE_MIN:-30}"
# Waits longer than LOCK_WARN_MIN minutes (default 5) are logged to <mail>/locks/waits.log, once
# per interval while waiting and once more when the lock is finally taken, so the controller can
# watch for excessive waiting on a resource (tail -F that file next to the inboxes).
warn=$(( ${LOCK_WARN_MIN:-5} * 60 )); next_warn=$warn
limit=$(( ${LOCK_WAIT_MIN:-30} * 60 ))
lock=""; chosen=""; waited=0
while [ -z "$lock" ]; do
  for i in $instances; do
    f="$dir/$resource.$i"
    if mkdir "$f" 2>/dev/null; then lock="$f"; chosen="$i"; break; fi
    # The holder's pid decides: alive means in use, gone means stale. No pid: go by age.
    owner_state=2
    [ -n "$have_lib" ] && { pl_owner_alive "$f/owner"; owner_state=$?; }
    if [ "$owner_state" -eq 1 ]; then
      echo "lock_run: taking over $resource.$i, its holder is gone (owner: $(cat "$f/owner" 2>/dev/null))" >&2
      rm -rf "$f"
    elif [ "$owner_state" -eq 2 ] && [ -n "$(find "$f" -maxdepth 0 -mmin +"$stale" 2>/dev/null)" ]; then
      echo "lock_run: taking over stale $resource.$i (owner: $(cat "$f/owner" 2>/dev/null))" >&2
      rm -rf "$f"
    fi
    # Taken over: try it again now rather than after the next wait.
    if [ ! -e "$f" ] && mkdir "$f" 2>/dev/null; then lock="$f"; chosen="$i"; break; fi
  done
  if [ -z "$lock" ]; then
    if [ "$waited" -ge "$limit" ]; then
      printf '%s GAVE-UP %s %s after %d min
' "$(date -u +%FT%TZ)" "$task" "$resource" $((waited / 60)) >> "$dir/waits.log"
      echo "lock_run: gave up waiting for $resource ($instances)" >&2; exit 75
    fi
    sleep 15; waited=$((waited + 15))
    if [ "$waited" -ge "$next_warn" ]; then
      printf '%s WAIT %s %s %d min (instances: %s)
' "$(date -u +%FT%TZ)" "$task" "$resource" $((waited / 60)) "$instances" >> "$dir/waits.log"
      next_warn=$((next_warn + warn))
    fi
  fi
done
if [ "$waited" -ge "$warn" ]; then
  printf '%s GOT %s %s.%s after %d min
' "$(date -u +%FT%TZ)" "$task" "$resource" "$chosen" $((waited / 60)) >> "$dir/waits.log"
fi
# The holder's pid lets others (and sweep.sh) tell a live holder from a dead one.
winpid=""; [ -r "/proc/$$/winpid" ] && read -r winpid < "/proc/$$/winpid"
printf '%s %s pid=%s winpid=%s\n' "$task" "$(date -u +%FT%TZ)" "$$" "${winpid:-none}" > "$lock/owner"
export LOCK_TASK="$task" LOCK_RESOURCE="$resource" LOCK_INSTANCE="$chosen"

# Runs <mail>/hooks/<resource>.<kind> if it is executable, stopping it after
# LOCK_HOOK_TIMEOUT seconds. Never fails.
run_hook() {
  local kind="$1" h="$mail/hooks/$resource.$1" limit="${LOCK_HOOK_TIMEOUT:-60}" hp wp rc
  [ -f "$h" ] && [ -x "$h" ] || return 0
  if [ -z "${LOCK_HOOK_WATCHDOG:-}" ] && command -v timeout >/dev/null 2>&1; then
    # GNU timeout signals the hook's whole process group, so its children stop too.
    timeout -k 5 "$limit" "$h" </dev/null >&2; rc=$?
    [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] && echo "lock_run: $kind hook for $resource.$chosen timed out after $limit s" >&2
  else
    # No timeout command (or LOCK_HOOK_WATCHDOG set): a watchdog TERMs the hook at the limit
    # and KILLs it 5 s later if it is still running.
    "$h" </dev/null >&2 & hp=$!
    ( n=0
      while kill -0 "$hp" 2>/dev/null; do
        if [ "$n" -eq "$limit" ]; then
          echo "lock_run: $kind hook for $resource.$chosen timed out after $limit s" >&2
          kill -TERM "$hp" 2>/dev/null
        elif [ "$n" -ge $((limit + 5)) ]; then
          kill -KILL "$hp" 2>/dev/null; break
        fi
        sleep 1; n=$((n + 1))
      done ) >/dev/null & wp=$!
    wait "$hp"; rc=$?
    kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
  fi
  [ "$rc" -eq 0 ] || echo "lock_run: $kind hook for $resource.$chosen failed (exit $rc); continuing" >&2
  return 0
}

released=""
release() {
  [ -z "$released" ] || return 0
  released=1
  local line=""
  read -r line < "$lock/owner" 2>/dev/null
  # Only our own lock: same task and, when the owner file records one, our pid.
  case "$line" in "$task "*) ;; *) return 0 ;; esac
  case " $line " in *" pid="*) [[ " $line " == *" pid=$$ "* ]] || return 0 ;; esac
  run_hook release
  rm -rf "$lock"
}
trap release EXIT
trap 'release; exit 143' TERM
trap 'release; exit 130' INT
echo "lock_run: $task holds $resource.$chosen" >&2
run_hook acquire
if [ -n "$have_lib" ]; then
  pl_guarded_run release "$@"
else
  "$@"
fi
