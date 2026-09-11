# Agent mailbox protocol

This folder is the only channel between the controller and the agents, and between agents.
It is gitignored. Paths may contain spaces, so always quote them.

## Files

- `inbox-<task>.log` — owned by agent `<task>`. Append-only. **Exactly one writer per file**;
  no agent ever writes to another agent's inbox. Everyone may read every inbox.
- `<task>.reply` — written only by the controller, append-only. Agent `<task>` reads it.
- `watch.sh` — the controller's monitor. Prints new signal lines from every inbox every 2 s.

Append with a single `printf` so a line lands whole:

```bash
printf '[%s] ISSUE: %s\n' "task-a" "level.json has a duplicate id 17; not in my scope" >> "<mail>/inbox-task-a.log"
```

## Line types (every line starts with `[<task>]`)

| Prefix | Meaning | When |
|--------|---------|------|
| `STATUS #n:` | What you are about to do and how, in one or two lines: the approach for the item, the evidence you plan to collect, a decision you just made. The controller answers every status with `#n: ACK` or `#n: <correction>`. | At task start (your plan), at the start of each item, after each runtime check (what you observed), and whenever 10 minutes pass with no line from you. |
| `ISSUE:` | Any finding, in or out of scope: a bug noticed, a stale doc, odd data, an environment quirk, something another agent did that looks wrong or relevant to anyone. | **Immediately**, the moment it is noticed. Not in the final report. |
| `QUESTION #n:` | A blocking question. Must include `default:` with the assumption you will proceed on. | When you cannot proceed without a decision. |

`STATUS` and `QUESTION` share one numbering sequence per agent (#1, #2, #3 ...), so every
reply line `#n:` in your reply file maps to exactly one thing you sent.
| `DONE:` | A milestone, with the commit hash. | After each item's commit. |
| `DONE ALL:` | Every item finished, with all hashes. The controller merges on the agent's final report, so this line is the early warning that the report is coming. | Once, right before the final report. |
| `TO <other>:` | A message for another agent. Written to **your own** inbox. | When something you found or did concerns a specific agent. |
| `CLAIM:` | A path outside your allowlist, or a server port, that you are about to use. | Before the first edit or start. |

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

## Reading messages addressed to you

Before each item, before each commit, after each runtime check, and before writing the final
report, read both the `TO` lines in every inbox and your own reply file:

```bash
grep -h "TO <task>" "<mail>"/inbox-*.log
cat "<mail>/<task>.reply" 2>/dev/null
```

In the reply file, `#n: ACK` means the controller saw status n and agrees; `#n: <anything
else>` is a correction to status or question n and changes what you do next; `NOTE: ...` is an
unsolicited instruction. Apply corrections before the next commit and mention them in the
report. Do not wait for an ACK; keep working and pick up replies at the next checkpoint. A
status that never gets a reply means "carry on".

## Other people's work

You will see commits, files, servers, hooks, and worktrees you did not create. They belong to
other agents or the controller. Do not revert, clean up, stop, or work around them on your own.
Say what you noticed: an `ISSUE` if it looks wrong or relevant to anyone, a `TO` line if it
concerns a specific agent, a `QUESTION` with a default if it changes what you should do next.
A plan change reaches you as a reply from the controller or a `TO` line from the other agent,
never as your own unilateral decision. No message means proceed as briefed.
