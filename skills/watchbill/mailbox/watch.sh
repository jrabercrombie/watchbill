#!/usr/bin/env bash
# watch.sh [--replay] — controller-side mailbox monitor.
# Every 2 seconds, print any new lines from every inbox-*.log that carry a signal prefix
# (STATUS, ISSUE, QUESTION, DONE, TO, CLAIM).
# Run from the controller as a persistent Monitor: bash .agent-mail/watch.sh
#
# Per-file line offsets are saved in .watch-state after every pass, so a restart (the
# Monitor expires every 30 minutes) resumes where the last run stopped instead of replaying
# the whole inbox as if it were new. Pass --replay to print history from line 1, for
# example when resuming a round after a session restart.
#
# Only complete lines (terminated by a newline) are consumed, so a line an agent is still
# writing is never printed half-way.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
shopt -s nullglob
declare -A seen
STATE=.watch-state

if [ "${1:-}" = "--replay" ]; then
  echo "[watch] started in $(pwd), replaying history"
else
  if [ -f "$STATE" ]; then
    while read -r f n; do
      [ -n "$f" ] && seen[$f]=$n
    done < "$STATE"
    echo "[watch] started in $(pwd), resuming from $STATE"
  else
    echo "[watch] started in $(pwd)"
  fi
fi

save_state() {
  local f tmp="$STATE.tmp"
  : > "$tmp"
  for f in "${!seen[@]}"; do printf '%s %s\n' "$f" "${seen[$f]}" >> "$tmp"; done
  mv -f "$tmp" "$STATE"
}

while true; do
  changed=0
  for f in inbox-*.log; do
    n=$(( $(wc -l < "$f") ))
    prev=${seen[$f]:-0}
    # A file that shrank was reset by setup.sh; start over so new lines are not skipped.
    if [ "$n" -lt "$prev" ]; then prev=0; fi
    if [ "$n" -gt "$prev" ]; then
      head -n "$n" "$f" | tail -n +$((prev + 1)) | tr -d '\r' \
        | grep -E --line-buffered 'STATUS|ISSUE|QUESTION|DONE|TO |CLAIM' || true
      seen[$f]=$n
      changed=1
    fi
  done
  [ "$changed" -eq 1 ] && save_state
  sleep 2
done
