#!/usr/bin/env bash
# setup.sh [--setup "<command>"] [--force] <task> [<task> ...]     reset mode: start a round
# setup.sh --add [--setup "<command>"] <task> [<task> ...]          add mode: extend a live round
#
# Run from anywhere inside the repo, on the integration branch.
#
# Reset mode (default), once at the start of a round:
#   - appends the gitignore lines for .worktrees/ and .agent-mail/ if missing
#   - creates .agent-mail/ with PROTOCOL.md and watch.sh, and CLEARS inbox, reply, and lock
#     files plus the watcher's saved offsets, so the round starts from an empty mailbox
#   - REFUSES when the mailbox looks live: an inbox or reply file written in the last
#     $WATCHBILL_LIVE_MINUTES (default 30) minutes, or task folders under .worktrees/.
#     A reset run mid-round to add one task once wiped every agent's inbox and reply file,
#     and an agent lost two instructions. Pass --force only when you know no agent is running.
#   - creates .worktrees/<task> on branch <task> from the current branch (reuses the branch
#     if it already exists, skips a worktree that already exists)
#   - runs the optional --setup command inside each new worktree (e.g. "npm install")
#
# Add mode (--add), while agents are running:
#   - creates only the new worktree(s) and their empty inbox and reply files. It never
#     truncates an existing inbox, never touches other tasks' files, and never overwrites
#     watch.sh (a running watcher reads its script incrementally).
#
# Both modes print the values to paste into the dispatch brief.
set -euo pipefail
shopt -s nullglob

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_CMD=""
MODE=reset
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --setup) SETUP_CMD="$2"; shift 2 ;;
    --add) MODE=add; shift ;;
    --force) FORCE=1; shift ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { echo "usage: setup.sh [--setup CMD] [--force] task [task ...]  |  setup.sh --add [--setup CMD] task [task ...]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
INTEGRATION="$(git rev-parse --abbrev-ref HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "warning: integration branch has uncommitted changes; worktrees branch from HEAD, not from them" >&2
fi

LIVE_MIN="${WATCHBILL_LIVE_MINUTES:-30}"
live_reason() {
  local f
  for f in .agent-mail/inbox-*.log .agent-mail/*.reply; do
    if [ -n "$(find "$f" -mmin "-$LIVE_MIN" 2>/dev/null)" ]; then
      echo "$f was written in the last $LIVE_MIN minutes"
      return 0
    fi
  done
  if [ -d .worktrees ] && [ -n "$(ls -A .worktrees 2>/dev/null)" ]; then
    echo ".worktrees/ still holds: $(ls -A .worktrees | tr '\n' ' ')"
    return 0
  fi
  return 1
}

if [ "$MODE" = reset ] && [ "$FORCE" -eq 0 ]; then
  if reason="$(live_reason)"; then
    echo "refusing to reset a live mailbox: $reason" >&2
    echo "to add a task to the running round:  setup.sh --add <task>" >&2
    echo "to reset anyway (no agent running):  setup.sh --force <tasks>" >&2
    exit 3
  fi
fi

touch .gitignore
while IFS= read -r line; do
  [ -n "$line" ] || continue
  grep -qxF -- "$line" .gitignore || printf '%s\n' "$line" >> .gitignore
done < "$SKILL_DIR/mailbox/gitignore-lines.txt"

mkdir -p .agent-mail
if [ "$MODE" = reset ]; then
  cp "$SKILL_DIR/mailbox/PROTOCOL.md" "$SKILL_DIR/mailbox/watch.sh" "$SKILL_DIR/mailbox/lock_run.sh" .agent-mail/
  rm -f .agent-mail/inbox-*.log .agent-mail/*.reply .agent-mail/.watch-state
  rm -rf .agent-mail/locks
  echo "mailbox reset: $ROOT/.agent-mail"
else
  [ -e .agent-mail/PROTOCOL.md ] || cp "$SKILL_DIR/mailbox/PROTOCOL.md" .agent-mail/
  [ -e .agent-mail/watch.sh ] || cp "$SKILL_DIR/mailbox/watch.sh" .agent-mail/
  [ -e .agent-mail/lock_run.sh ] || cp "$SKILL_DIR/mailbox/lock_run.sh" .agent-mail/
  echo "mailbox kept: $ROOT/.agent-mail (add mode)"
fi
mkdir -p .agent-mail/locks

mkdir -p .worktrees
for t in "$@"; do
  if [ -d ".worktrees/$t" ]; then
    echo "worktree .worktrees/$t already exists; leaving it" >&2
  elif git show-ref --verify --quiet "refs/heads/$t"; then
    git worktree add ".worktrees/$t" "$t"
  else
    git worktree add -b "$t" ".worktrees/$t" "$INTEGRATION"
  fi
  # Never truncate: in add mode the inbox may already carry lines.
  [ -e ".agent-mail/inbox-$t.log" ] || : > ".agent-mail/inbox-$t.log"
  [ -e ".agent-mail/$t.reply" ] || : > ".agent-mail/$t.reply"
  if [ -n "$SETUP_CMD" ]; then
    echo "running setup in .worktrees/$t: $SETUP_CMD"
    (cd ".worktrees/$t" && bash -c "$SETUP_CMD")
  fi
done

echo
echo "INTEGRATION=$INTEGRATION"
echo "MAIL=$ROOT/.agent-mail"
for t in "$@"; do
  echo "WORKTREE[$t]=$ROOT/.worktrees/$t  BRANCH=$t"
done
echo
if [ "$MODE" = reset ]; then
  echo "next: Monitor({ command: \"bash .agent-mail/watch.sh\", description: \"agent mailbox\", persistent: true })"
else
  echo "the running watcher picks up the new inbox on its next pass; no restart needed"
fi
