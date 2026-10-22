#!/usr/bin/env bash
# cleanup.sh [--scratch <dir>] <task> [<task> ...]
#
# Stops the tasks' leftover processes (.agent-mail/sweep.sh --kill, limited to these tasks),
# removes .worktrees/<task>, deletes <dir>/<task> when --scratch names the session scratch
# folder (agent scratch and per-agent app-data folders live there), and deletes branch <task>
# if it is fully merged into the current branch. An unmerged branch is kept and reported, so
# nothing is lost by running this early.
# The name "_staging" removes the staging worktree and its "integration-staging" branch.
#
# Windows note: a folder a sync client, indexer, or test runner just touched can be locked for a
# few seconds. If git cannot remove the worktree, this waits, retries, and finally falls back
# to deleting the folder and pruning git's registration. Pruning the .git/worktrees/<task>
# record often fails once or twice on Windows/OneDrive with "Permission denied"; that used to
# print on every run, so the prune now retries quietly and the script ends with one summary
# line saying what, if anything, is left.
set -uo pipefail
SCRATCH=""
if [ "${1:-}" = "--scratch" ]; then SCRATCH="$2"; shift 2; fi
[ $# -ge 1 ] || { echo "usage: cleanup.sh [--scratch DIR] task [task ...]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$ROOT" || exit 1

# Agents sometimes report a dev server stopped when it is not. A node process (dev server,
# test worker) whose command line points inside .worktrees/<task> keeps the folder locked
# and the port busy, so stop such processes first. Restricted to node so it can never hit
# the shell running this script.
stop_processes_in() {
  local task="$1"
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" | Where-Object { \$_.CommandLine -like '*.worktrees\\${task}*' -or \$_.CommandLine -like '*.worktrees/${task}*' } | ForEach-Object { Write-Output ('stopped node ' + \$_.ProcessId + ' in .worktrees/${task}'); Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" 2>/dev/null
  elif command -v pkill >/dev/null 2>&1; then
    pkill -f -- "node.*\.worktrees/${task}" 2>/dev/null && echo "stopped node processes in .worktrees/${task}"
  fi
}

remove_worktree() {
  local dir="$1"
  stop_processes_in "$(basename "$dir")"
  git worktree remove --force "$dir" 2>/dev/null && return 0
  sleep 3
  git worktree remove --force "$dir" 2>/dev/null && return 0
  rm -rf "$dir" 2>/dev/null
  # Git Bash rm can be refused where PowerShell succeeds (Windows handle quirks).
  if [ -e "$dir" ] && command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Remove-Item -Recurse -Force -LiteralPath '$(cygpath -w "$dir")' -ErrorAction SilentlyContinue" >/dev/null 2>&1
  fi
  quiet_prune
  [ ! -e "$dir" ]
}

# git worktree prune can fail transiently on a record folder a sync client holds open.
quiet_prune() {
  local i
  for i in 1 2 3; do
    git worktree prune 2>/dev/null && return 0
    sleep 2
  done
  git worktree prune 2>/dev/null || true
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

# Processes first: a test runner or engine still running from a worktree keeps it locked.
# The tasks named here are over, so their processes are leftovers unless a live lock holds them.
if [ -f .agent-mail/sweep.sh ]; then
  list="$(IFS=,; echo "$*")"
  bash .agent-mail/sweep.sh --kill --done "$list" --only "$list" | grep -E '^(LEFTOVER|sweep: stopped)' || true
fi

status=0
for t in "$@"; do
  if [ -n "$SCRATCH" ] && [ -n "$t" ] && [ -d "$SCRATCH/$t" ]; then
    rm -rf "${SCRATCH:?}/$t" && echo "removed scratch folder $SCRATCH/$t"
  fi
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
  br="$t"; [ "$t" = "_staging" ] && br="integration-staging"
  if git show-ref --verify --quiet "refs/heads/$br"; then
    if git branch --merged HEAD --format='%(refname:short)' | grep -qx -- "$br"; then
      git branch -d "$br" >/dev/null && echo "deleted branch $br"
    else
      echo "branch $br is NOT merged into $(git rev-parse --abbrev-ref HEAD); kept" >&2
      status=1
    fi
  fi
done
quiet_prune
for t in "$@"; do prune_records "$t"; done
rmdir .worktrees 2>/dev/null || true
leftover=""
for t in "$@"; do [ -e ".git/worktrees/$t" ] && leftover="$leftover .git/worktrees/$t"; done
if [ -n "$leftover" ]; then
  echo "cleanup done; stale records survived (harmless once 'git worktree list' shows only the main checkout, delete by hand later):$leftover"
else
  echo "cleanup done; no stale worktree records"
fi
exit $status
