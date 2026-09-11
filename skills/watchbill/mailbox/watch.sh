#!/usr/bin/env bash
# watch.sh — controller-side mailbox monitor.
# Every 2 seconds, print any new lines from every inbox-*.log that carry a signal prefix
# (STATUS, ISSUE, QUESTION, DONE, TO, CLAIM).
# Run from the controller as a persistent Monitor: bash .agent-mail/watch.sh
# Only complete lines (terminated by a newline) are consumed, so a line an agent is still
# writing is never printed half-way.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
shopt -s nullglob
declare -A seen

echo "[watch] started in $(pwd)"

while true; do
  for f in inbox-*.log; do
    n=$(( $(wc -l < "$f") ))
    prev=${seen[$f]:-0}
    if [ "$n" -gt "$prev" ]; then
      head -n "$n" "$f" | tail -n +$((prev + 1)) | tr -d '\r' \
        | grep -E --line-buffered 'STATUS|ISSUE|QUESTION|DONE|TO |CLAIM' || true
      seen[$f]=$n
    fi
  done
  sleep 2
done
