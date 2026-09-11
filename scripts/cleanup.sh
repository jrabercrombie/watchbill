#!/usr/bin/env bash
# cleanup.sh <task> [<task> ...]
#
# Removes .worktrees/<task> and deletes branch <task> if it is fully merged into the current
# branch. An unmerged branch is kept and reported, so nothing is lost by running this early.
#
# Windows note: a folder under OneDrive or one a test runner just used can be locked for a
# few seconds. If git cannot remove the worktree, this waits, retries, and finally falls back
# to deleting the folder and pruning git's registration.
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: cleanup.sh task [task ...]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$ROOT" || exit 1

remove_worktree() {
  local dir="$1"
  git worktree remove --force "$dir" 2>/dev/null && return 0
  sleep 3
  git worktree remove --force "$dir" 2>/dev/null && return 0
  rm -rf "$dir" 2>/dev/null
  # Git Bash rm can be refused where PowerShell succeeds (OneDrive / handle quirks).
  if [ -e "$dir" ] && command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Remove-Item -Recurse -Force -LiteralPath '$(cygpath -w "$dir")' -ErrorAction SilentlyContinue" >/dev/null 2>&1
  fi
  git worktree prune
  [ ! -e "$dir" ]
}

prune_records() {
  # Stale .git/worktrees/<task> folders sometimes survive prune on Windows.
  local rec=".git/worktrees/$1"
  [ -e "$rec" ] || return 0
  rm -rf "$rec" 2>/dev/null
  if [ -e "$rec" ] && command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Remove-Item -Recurse -Force -LiteralPath '$(cygpath -w "$rec")' -ErrorAction SilentlyContinue" >/dev/null 2>&1
  fi
}

status=0
for t in "$@"; do
  if [ -e ".worktrees/$t" ]; then
    if remove_worktree ".worktrees/$t"; then
      echo "removed worktree .worktrees/$t"
    else
      echo "could not remove .worktrees/$t (still locked); remove it by hand later" >&2
      status=1
    fi
  else
    echo "no worktree at .worktrees/$t"
  fi
  if git show-ref --verify --quiet "refs/heads/$t"; then
    if git branch --merged HEAD --format='%(refname:short)' | grep -qx -- "$t"; then
      git branch -d "$t" >/dev/null && echo "deleted branch $t"
    else
      echo "branch $t is NOT merged into $(git rev-parse --abbrev-ref HEAD); kept" >&2
      status=1
    fi
  fi
done
git worktree prune
for t in "$@"; do prune_records "$t"; done
rmdir .worktrees 2>/dev/null || true
exit $status
