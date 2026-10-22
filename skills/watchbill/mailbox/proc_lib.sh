# proc_lib.sh: process helpers shared by lock_run.sh, sweep.sh, watch.sh and any project-side
# wrapper. Source it; it defines functions only and runs nothing.
#
# Why it exists: on Windows (Git Bash / MSYS), stopping a shell kills that one process and
# leaves its children running. Pipelines and test shards left behind that way piled up to
# over a hundred processes overnight. These helpers stop a whole tree, and run a command so
# that its tree is stopped when its caller goes away.
#
# Works with the MSYS /proc (ppid, pgid, winpid files) and on POSIX with ps.

# pl_alive <pid>: true if the process exists.
pl_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# pl_winpid <pid>: the Windows pid of an MSYS process, empty elsewhere.
pl_winpid() { local w=""; [ -r "/proc/$1/winpid" ] && read -r w < "/proc/$1/winpid" 2>/dev/null; printf '%s' "$w"; }

# pl_table: one "pid ppid pgid" line per process.
pl_table() {
  if [ -r /proc/self/ppid ]; then
    local d p pp pg
    for d in /proc/[0-9]*; do
      p="${d#/proc/}"
      read -r pp < "$d/ppid" 2>/dev/null || continue
      read -r pg < "$d/pgid" 2>/dev/null || pg="$p"
      printf '%s %s %s\n' "$p" "$pp" "$pg"
    done
  else
    ps -eo pid=,ppid=,pgid= 2>/dev/null
  fi
}

# pl_descendants <pid>: the pid's descendants (not the pid itself), parents before children.
pl_descendants() {
  pl_table | awk -v root="$1" '
    { kids[$2] = kids[$2] " " $1 }
    END {
      n = 1; q[1] = root
      for (i = 1; i <= n; i++) {
        m = split(kids[q[i]], k, " ")
        for (j = 1; j <= m; j++) if (!(k[j] in seen)) { seen[k[j]] = 1; q[++n] = k[j]; print k[j] }
      }
    }'
}

# pl_kill_pids [--grace N] <pid...>: TERM the pids, wait up to N seconds (default 2) for them
# to exit, then KILL what is left. On Windows each one also gets taskkill /F /T on its
# Windows pid, which reaches native children that the MSYS process table does not list.
pl_kill_pids() {
  local grace=2 p w left i wins=""
  if [ "${1:-}" = "--grace" ]; then grace="$2"; shift 2; fi
  [ "$#" -gt 0 ] || return 0
  for p in "$@"; do
    w="$(pl_winpid "$p")"; [ -n "$w" ] && wins="$wins $w"
    kill -TERM "$p" 2>/dev/null
  done
  for ((i = 0; i < grace * 4; i++)); do
    left=0
    for p in "$@"; do pl_alive "$p" && left=1; done
    [ "$left" -eq 0 ] && break
    sleep 0.25
  done
  for p in "$@"; do pl_alive "$p" && kill -KILL "$p" 2>/dev/null; done
  if [ -n "$wins" ] && command -v taskkill.exe >/dev/null 2>&1; then
    for w in $wins; do MSYS_NO_PATHCONV=1 taskkill.exe /F /T /PID "$w" >/dev/null 2>&1; done
  fi
  return 0
}

# pl_kill_tree [--grace N] <pid>: stop the pid and every descendant. The tree is listed
# before anything is signalled, so children are found while their parent still lives.
pl_kill_tree() {
  local g=()
  if [ "${1:-}" = "--grace" ]; then g=(--grace "$2"); shift 2; fi
  pl_alive "$1" || return 0
  # shellcheck disable=SC2046
  pl_kill_pids "${g[@]}" "$1" $(pl_descendants "$1")
}

# pl_record_tree <file> <root-pid>: write "pid winpid" for the root and every descendant, so a
# later process can still find them after the root is hard-killed (a hard kill runs no trap, and
# on Windows the MSYS children are not in the Windows process tree, so they survive it).
pl_record_tree() {
  local f="$1" p
  { for p in "$2" $(pl_descendants "$2"); do pl_alive "$p" && printf '%s %s
' "$p" "$(pl_winpid "$p")"; done; } > "$f.tmp" 2>/dev/null
  [ -s "$f.tmp" ] && mv -f "$f.tmp" "$f" || rm -f "$f.tmp"
}

# pl_kill_recorded <file>: stop every process listed by pl_record_tree that is still running
# (a pid reused by another process is skipped when the Windows pid no longer matches).
pl_kill_recorded() {
  local f="$1" p w pids=""
  [ -r "$f" ] || return 0
  while read -r p w; do
    pl_alive "$p" || continue
    if [ -n "$w" ] && [ "$(pl_winpid "$p")" != "$w" ]; then continue; fi
    pids="$pids $p"
  done < "$f"
  # shellcheck disable=SC2086
  [ -n "$pids" ] && pl_kill_pids $pids
  return 0
}

# pl_guarded_run <on_stop> <command...>
# Runs the command (stdin kept) and returns its exit code. If this shell gets TERM or INT,
# or if this shell or the process that started it disappears (stopped by a tool that kills
# only the top process), the command's whole tree is stopped and <on_stop> is called (a
# function name, or ":"). A small guardian checks every PL_GUARD_SEC seconds (default 10).
# Set PL_KEEP_ORPHAN=1 when starting it detached on purpose, so the caller exiting does not
# count as a stop. With PL_TREE_FILE=<file> set, the guardian also records the command's pids
# there (first after 1 second, then every pass) for pl_kill_recorded.
pl_guarded_run() {
  local on_stop="$1"; shift
  local main=$$ parent=$PPID
  [ "${PL_KEEP_ORPHAN:-0}" = 1 ] && parent=""
  [ "$parent" = 1 ] && parent=""
  "$@" <&0 &
  PL_CHILD=$!
  local guard_sec="${PL_GUARD_SEC:-10}"
  (
    exec </dev/null >/dev/null 2>&1
    if [ -n "${PL_TREE_FILE:-}" ]; then sleep 1; pl_alive "$main" && pl_record_tree "$PL_TREE_FILE" "$PL_CHILD"; fi
    while pl_alive "$main" && { [ -z "$parent" ] || pl_alive "$parent"; } && pl_alive "$PL_CHILD"; do
      sleep "$guard_sec"
      [ -n "${PL_TREE_FILE:-}" ] && pl_alive "$main" && pl_record_tree "$PL_TREE_FILE" "$PL_CHILD"
    done
    if pl_alive "$PL_CHILD"; then
      pl_kill_tree "$PL_CHILD"
      pl_alive "$main" || "$on_stop"
    fi
  ) &
  PL_GUARD=$!
  # shellcheck disable=SC2064
  trap "pl_kill_tree $PL_CHILD; pl_kill_tree --grace 0 $PL_GUARD; $on_stop; exit 143" TERM
  # shellcheck disable=SC2064
  trap "pl_kill_tree $PL_CHILD; pl_kill_tree --grace 0 $PL_GUARD; $on_stop; exit 130" INT
  local rc=0
  wait "$PL_CHILD" || rc=$?
  pl_kill_tree --grace 0 "$PL_GUARD"
  trap - TERM INT
  return "$rc"
}

# pl_owner_alive <owner-file>: true if the lock owner file names a pid that is still running.
# Returns 2 when the file names no pid (written by an older helper), so callers fall back to age.
pl_owner_alive() {
  local f="$1" line pid=""
  [ -r "$f" ] || return 2
  read -r line < "$f" 2>/dev/null || return 2
  case " $line " in *" pid="*) pid="${line##* pid=}"; pid="${pid%% *}" ;; *) return 2 ;; esac
  pl_alive "$pid"
}
