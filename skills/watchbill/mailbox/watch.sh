#!/usr/bin/env bash
# watch.sh [--replay] [--for SECONDS] — controller-side mailbox monitor.
# Every 2 seconds, print any new lines from every inbox-*.log that carry a signal prefix
# (STATUS, ISSUE, QUESTION, DONE, TO, CLAIM). The inbox list is re-read on every pass, so an
# agent added mid-round is covered without restarting the watcher.
#
# Run it from the controller as a Monitor, under `timeout`, so nothing it starts can outlive it:
#   Monitor({ command: "timeout 1790 bash .agent-mail/watch.sh", timeout_ms: 1800000, ... })
#
# Cleaning up after itself (a Windows lesson: stopping a Monitor kills only its top shell, and
# re-arming a hand-written `tail -F | grep | cut` watcher every 30 minutes left over a hundred
# orphaned processes running overnight):
#   - It exits by itself after --for seconds (default WATCH_FOR, 1780: just under the 30-minute
#     Monitor limit), and the documented `timeout` stops it even if that fails.
#   - Only one watcher runs per mailbox: it records itself in .watch.pid, and a new watcher stops
#     the previous one (and its children) before it starts.
#   - It starts almost no processes: change detection uses the shell's own file-time test
#     against a tick file it rewrites with a builtin, and lines are read and filtered with
#     builtins. A quiet pass spawns nothing but the 2-second sleep. (The earlier version ran
#     wc on every inbox every pass: about 100 processes a second with 200 inboxes.)
#   - On exit it removes its pid and tick files.
#
# Per-file line offsets are saved in .watch-state, so a restart resumes where the last run
# stopped. With no .watch-state (a mailbox that never had this watcher), it starts at the end
# of every existing inbox instead of printing all history; --replay prints history from line 1.
#
# Only complete lines (terminated by a newline) are consumed, so a line an agent is still
# writing is never printed half-way.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
shopt -s nullglob
here="$(pwd)"
# shellcheck source=proc_lib.sh
[ -f proc_lib.sh ] && . ./proc_lib.sh
declare -A seen
STATE=.watch-state
PIDF=.watch.pid
replay=0; for_s="${WATCH_FOR:-1780}"
while [ $# -gt 0 ]; do
  case "$1" in
    --replay) replay=1; shift ;;
    --for) for_s="$2"; shift 2 ;;
    *) echo "usage: watch.sh [--replay] [--for SECONDS]" >&2; exit 64 ;;
  esac
done

# Replace a previous watcher of this mailbox, if one is still running.
if [ -f "$PIDF" ]; then
  old=""; read -r old _ < "$PIDF"
  if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null \
     && { tr '\0' ' ' < "/proc/$old/cmdline"; } 2>/dev/null | grep -q 'watch\.sh'; then
    if declare -F pl_kill_tree >/dev/null; then pl_kill_tree "$old"; else kill "$old" 2>/dev/null; fi
    echo "[watch] stopped the previous watcher (pid $old)"
  fi
fi
winpid=""; [ -r "/proc/$$/winpid" ] && read -r winpid < "/proc/$$/winpid"
printf '%s %s\n' "$$" "${winpid:-none}" > "$PIDF"

TICK0=".watch-tick.$$.0"; TICK1=".watch-tick.$$.1"
cleanup() {
  rm -f "$TICK0" "$TICK1"
  local p=""; read -r p _ < "$PIDF" 2>/dev/null
  [ "$p" = "$$" ] && rm -f "$PIDF"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

save_state() {
  local f tmp="$STATE.tmp"
  {
    for f in "${!seen[@]}"; do [ -e "$f" ] && printf '%s %s\n' "$f" "${seen[$f]}"; done
  } > "$tmp"
  mv -f "$tmp" "$STATE"
}

# read_new <file> <print 0|1>: consume complete lines past the saved offset, print signal lines.
read_new() {
  local f="$1" print="$2" n=0 prev line
  prev=${seen[$f]:-0}
  while IFS= read -r line; do
    n=$((n + 1))
    [ "$n" -le "$prev" ] && continue
    [ "$print" -eq 1 ] || continue
    line="${line%$'\r'}"
    [[ $line =~ STATUS|ISSUE|QUESTION|DONE|TO\ |CLAIM ]] && printf '%s\n' "$line"
  done < "$f"
  # A file that shrank was reset by setup.sh; start over so new lines are not skipped.
  if [ "$n" -lt "$prev" ]; then seen[$f]=0; read_new "$f" "$print"; return; fi
  seen[$f]=$n
}

printf 'x' > "$TICK0"
changed=0
if [ "$replay" -eq 1 ]; then
  echo "[watch] started in $here, replaying history, exits after ${for_s}s"
  for f in inbox-*.log; do read_new "$f" 1; done; changed=1
elif [ -f "$STATE" ]; then
  while read -r f n; do [ -n "$f" ] && seen[$f]=$n; done < "$STATE"
  echo "[watch] started in $here, resuming from $STATE, exits after ${for_s}s"
  for f in inbox-*.log; do
    if [ -z "${seen[$f]+x}" ] || ! [ "$f" -ot "$STATE" ]; then read_new "$f" 1; changed=1; fi
  done
else
  for f in inbox-*.log; do read_new "$f" 0; done; changed=1
  echo "[watch] started in $here, no saved state: starting at the end of every inbox (--replay for history), exits after ${for_s}s"
fi
[ "$changed" -eq 1 ] && save_state

old="$TICK0"; new="$TICK1"
while [ "$SECONDS" -lt "$for_s" ]; do
  sleep 2
  printf 'x' > "$new"
  changed=0
  for f in inbox-*.log; do
    # Written since the previous tick (or at the same instant), or never seen: read it.
    if [ -z "${seen[$f]+x}" ] || ! [ "$f" -ot "$old" ]; then
      read_new "$f" 1; changed=1
    fi
  done
  [ "$changed" -eq 1 ] && save_state
  t="$old"; old="$new"; new="$t"
done
echo "[watch] stopping after ${for_s}s as designed; re-arm the Monitor"
