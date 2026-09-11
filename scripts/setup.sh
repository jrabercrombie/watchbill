#!/usr/bin/env bash
# setup.sh [--setup "<command>"] <task> [<task> ...]
#
# Run from anywhere inside the repo, on the integration branch. It:
#   - appends the gitignore lines for .worktrees/ and .agent-mail/ if missing
#   - creates .agent-mail/ with PROTOCOL.md and watch.sh, and CLEARS old inbox/reply files
#     so the watcher does not replay history from a previous session
#   - creates .worktrees/<task> on branch <task> from the current branch (reuses the branch
#     if it already exists, skips a worktree that already exists)
#   - runs the optional --setup command inside each new worktree (e.g. "npm install")
#   - prints the values to paste into the prompt templates
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --setup) SETUP_CMD="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { echo "usage: setup.sh [--setup CMD] task [task ...]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
INTEGRATION="$(git rev-parse --abbrev-ref HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "warning: integration branch has uncommitted changes; worktrees branch from HEAD, not from them" >&2
fi

touch .gitignore
while IFS= read -r line; do
  [ -n "$line" ] || continue
  grep -qxF -- "$line" .gitignore || printf '%s\n' "$line" >> .gitignore
done < "$SKILL_DIR/mailbox/gitignore-lines.txt"

mkdir -p .agent-mail
cp "$SKILL_DIR/mailbox/PROTOCOL.md" "$SKILL_DIR/mailbox/watch.sh" .agent-mail/
rm -f .agent-mail/inbox-*.log .agent-mail/*.reply
echo "mailbox reset: $ROOT/.agent-mail"

mkdir -p .worktrees
for t in "$@"; do
  if [ -d ".worktrees/$t" ]; then
    echo "worktree .worktrees/$t already exists; leaving it" >&2
  elif git show-ref --verify --quiet "refs/heads/$t"; then
    git worktree add ".worktrees/$t" "$t"
  else
    git worktree add -b "$t" ".worktrees/$t" "$INTEGRATION"
  fi
  : > ".agent-mail/inbox-$t.log"
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
echo "next: Monitor({ command: \"bash .agent-mail/watch.sh\", description: \"agent mailbox\", persistent: true })"
