# Agent mailbox protocol

This folder is the only channel between the controller and the agents, and between agents.
It is gitignored. Paths may contain spaces, so always quote them.

## Files

- `inbox-<task>.log` — owned by agent `<task>`. Append-only. **Exactly one writer per file**;
  no agent ever writes to another agent's inbox. Everyone may read every inbox.
- `<task>.reply` — written only by the controller, append-only. Agent `<task>` reads it.
- `locks/<resource>` — one file per exclusive resource in use (see "Exclusive resources").
- `watch.sh` — the controller's monitor. Prints new signal lines from every inbox every 2 s
  and remembers its place in `.watch-state`, so a restart does not replay history.

Append with a single `printf` so a line lands whole:

```bash
printf '[%s] ISSUE: %s\n' "task-a" "level.json has a duplicate id 17; not in my scope" >> "<mail>/inbox-task-a.log"
```

## Line types (every line starts with `[<task>]`)

| Prefix | Meaning | When |
|--------|---------|------|
| `STATUS #n:` | What you are about to do and how, in one or two lines: the approach for the item, the evidence you plan to collect, a decision you just made. Ends with the NOTE lines you have applied so far (`applied NOTE@14:02, NOTE@14:20` or `no NOTEs`). The controller answers every status with `#n: ACK` or `#n: <correction>`. | At task start (your plan), at the start of each item, after each runtime check (what you observed), and whenever 10 minutes pass with no line from you. |
| `ISSUE:` | Any finding, in or out of scope: a bug noticed, a stale doc, odd data, an environment quirk, something another agent did that looks wrong or relevant to anyone. | **Immediately**, the moment it is noticed. Not in the final report. |
| `QUESTION #n:` | A blocking question. Must include `default:` with the assumption you will proceed on. | When you cannot proceed without a decision. |
| `DONE:` | A milestone, with the commit hash, ending with the NOTE lines applied in that commit (`applied NOTE@14:02` or `no NOTEs`). | After each item's commit. |
| `DONE ALL:` | Every item finished, with all hashes and the full list of NOTEs applied. The controller merges on the agent's final report, so this line is the early warning that the report is coming. | Once, right before the final report. |
| `TO <other>:` | A message for another agent. Written to **your own** inbox. | When something you found or did concerns a specific agent. |
| `CLAIM:` | A path outside your allowlist, or a server port, that you are about to use. | Before the first edit or start. |

`STATUS` and `QUESTION` share one numbering sequence per agent (#1, #2, #3 ...), so every
reply line `#n:` in your reply file maps to exactly one thing you sent.

The `applied NOTE@...` suffix exists because agents have committed before seeing a NOTE that
changed their scope. Listing what you applied lets the controller see at a glance that an
instruction reached you, and repeat it as a numbered reply if it did not.

## Questions and replies

After appending `QUESTION #n`, poll for a reply for at most 8 minutes, in the background, and
keep doing work that does not depend on the answer:

```bash
for i in $(seq 1 48); do
  grep -q '^#n:' "<mail>/<task>.reply" 2>/dev/null && { grep '^#n:' "<mail>/<task>.reply"; exit 0; }
  sleep 10
done
echo "NO REPLY to #n; proceeding on default"
```

If no reply arrives, proceed on your stated default and say so in your report. The controller
answers by appending `#n: <answer>` to `<task>.reply`. Because replies are numbered and the file
is append-only, a stale answer to an earlier question is never mistaken for the current one.

## Reading messages addressed to you

Read both the `TO` lines in every inbox and your own reply file at every checkpoint: before
each item, **immediately before every `git commit` (the same shell command, not a minute
earlier)**, before starting any step you expect to take more than 5 minutes (a long test run,
a build, a capture session), after each runtime check, and before writing the final report:

```bash
grep -h "TO <task>" "<mail>"/inbox-*.log
cat "<mail>/<task>.reply" 2>/dev/null
```

The commit-time read is the one that matters most. Agents have committed work seconds after a
scope change landed in their reply file because the last read was at the start of the item.

In the reply file:

- `#n: ACK` means the controller saw status n and agrees.
- `#n: <anything else>` is a correction to status or question n and changes what you do next.
- `NOTE@HH:MM: ...` is an unsolicited instruction, stamped with the time it was written. Apply
  it before your next commit and cite it (`applied NOTE@HH:MM`) in your next STATUS and DONE.
- `NOTE@HH:MM: PAUSE` means: finish the step you are in, commit the work that is green, skip
  every remaining item, and write your final report now. Do not start anything new.

Do not wait for an ACK; keep working and pick up replies at the next checkpoint. A status
that never gets a reply means "carry on".

## Claims

Claims are **notices, never locks**. Before claiming, check whether someone else already holds
it:

```bash
grep -h 'CLAIM:' "<mail>"/inbox-*.log
```

If another agent holds the file or port, do not wait for them: skip that edit, append an
`ISSUE` describing exactly what you wanted to change (file, lines, intent) so the controller can
apply it after merge, and continue. Nothing in this protocol ever waits on another agent, so
there is no deadlock.

## Exclusive resources

Some things cannot be shared or skipped: the one GPU window for captures, a hardware device, a
license seat. The controller names them in the brief under `EXCLUSIVE`. These, and only these,
use a lock file `locks/<resource>` holding your task name and a timestamp. Before "wait 30 s
and retry" became this rule, several agents needing the same window collided and produced
garbage captures.

```bash
# acquire: succeeds for exactly one caller; a lock older than 10 minutes is stale and taken over
lock() {
  local f="<mail>/locks/$1" i
  for i in $(seq 1 40); do
    ( set -o noclobber; printf '%s %s\n' "<task>" "$(date -u +%FT%TZ)" > "$f" ) 2>/dev/null && return 0
    if [ -n "$(find "$f" -mmin +10 2>/dev/null)" ]; then rm -f "$f"; continue; fi
    sleep 15
  done
  return 1
}
# release: only your own lock
unlock() { local f="<mail>/locks/$1"; grep -q "^<task> " "$f" 2>/dev/null && rm -f "$f"; }
```

Rules: acquire immediately before use and release immediately after; never hold a lock while
polling for a reply or running anything unrelated; if `lock` returns 1 after its 10 minutes,
append an `ISSUE`, do the rest of your work, and retry the capture last. A stale lock is one
whose owner crashed; taking it over is expected, not rude.

## Other people's work

You will see commits, files, servers, hooks, and worktrees you did not create. They belong to
other agents or the controller. Do not revert, clean up, stop, or work around them on your own.
Say what you noticed: an `ISSUE` if it looks wrong or relevant to anyone, a `TO` line if it
concerns a specific agent, a `QUESTION` with a default if it changes what you should do next.
A plan change reaches you as a reply from the controller or a `TO` line from the other agent,
never as your own unilateral decision. No message means proceed as briefed.
