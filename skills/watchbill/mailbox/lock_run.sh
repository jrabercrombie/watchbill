#!/usr/bin/env bash
# Run one command while holding a lock on an exclusive resource, then release it.
#
#   bash <mail>/lock_run.sh <task> <resource> <command...>
#
# A resource may have several interchangeable instances (two GPUs, three device slots, two
# test databases). Declare them in <mail>/resources.conf, one resource per line:
#
#   <resource> = <instance> [<instance> ...]      e.g.   gpu = 0 1
#
# A resource not listed there has a single instance. The command runs with the chosen
# instance in $LOCK_INSTANCE (and $LOCK_RESOURCE), so it can pass it on (a device id, a port,
# a GPU index). Set LOCK_PREFER=<instance> to require one particular instance, e.g. when two
# measurements must be taken on the same hardware.
#
# Guarantees: the command never runs without a lock; the helper only ever removes its own
# lock; a lock whose owner is gone (older than LOCK_STALE_MIN minutes, default 30) is taken
# over; it gives up with exit 75 after LOCK_WAIT_MIN minutes (default 30) of waiting.
# Agents use this helper instead of hand-written mkdir/rm locking.
set -u
if [ "$#" -lt 3 ]; then
  echo "usage: lock_run.sh <task> <resource> <command...>" >&2; exit 64
fi
task="$1"; resource="$2"; shift 2
mail="$(cd "$(dirname "$0")" && pwd)"
dir="$mail/locks"
mkdir -p "$dir"

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
    if [ -n "$(find "$f" -maxdepth 0 -mmin +"$stale" 2>/dev/null)" ]; then
      echo "lock_run: taking over stale $resource.$i (owner: $(cat "$f/owner" 2>/dev/null))" >&2
      rm -rf "$f"
    fi
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
printf '%s %s\n' "$task" "$(date -u +%FT%TZ)" > "$lock/owner"
release() { if [ "$(cut -d" " -f1 "$lock/owner" 2>/dev/null)" = "$task" ]; then rm -rf "$lock"; fi; }
trap release EXIT
trap 'release; exit 143' TERM
trap 'release; exit 130' INT
echo "lock_run: $task holds $resource.$chosen" >&2
export LOCK_RESOURCE="$resource" LOCK_INSTANCE="$chosen"
"$@"
