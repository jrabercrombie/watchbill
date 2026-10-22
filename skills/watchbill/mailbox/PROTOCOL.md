# Agent mailbox protocol

This folder is the only channel between the controller and the agents, and between agents.
It is gitignored. Paths may contain spaces, so always quote them.

## Files

- `inbox-<task>.log` — owned by agent `<task>`. Append-only. **Exactly one writer per file**;
  no agent ever writes to another agent's inbox. Everyone may read every inbox.
- `<task>.reply` — written only by the controller, append-only. Agent `<task>` reads it.
- `locks/<resource>` — one file per exclusive resource in use (see "Exclusive resources").
- `watch.sh` — the controller's monitor. Prints new signal lines from every inbox every 2 s,
  remembers its place in `.watch-state` so a restart does not replay history, exits by itself
  just under 30 minutes, and keeps one instance per mailbox (`.watch.pid`).
- `lock_run.sh`, `proc_lib.sh`, `sweep.sh` — the lock helper, its process-tree helpers, and the
  leftover-process sweep (see "Cleaning up").

Append with a single `printf` so a line lands whole:

```bash
printf '[%s] ISSUE: %s\n' "task-a" "prices.json has a duplicate id 17; not in my scope" >> "<mail>/inbox-task-a.log"
```

## Line types (every line starts with `[<task>]`)

| Prefix | Meaning | When |
|--------|---------|------|
| `STATUS #n PLAN:` | What you are about to do and how, in one or two lines: the approach for the item, the files, the evidence you plan to collect. Ends with the NOTE lines applied so far (`applied NOTE@14:02, NOTE@14:20` or `no NOTEs`). The controller answers every PLAN with `#n: ACK` or `#n: <correction>`; read the reply before the item's first commit. | At task start (the whole plan) and at the start of each item. |
| `STATUS #n PROGRESS:` | An observation, a runtime result, a heartbeat. Same suffix. The controller reads it but does not answer unless it needs correcting, so do not expect a reply. | After each runtime check (what you observed), and whenever 10 minutes pass with no line from you. |
| `ISSUE:` | Any finding, in or out of scope: a bug noticed, a stale doc, odd data, an environment quirk, something another agent did that looks wrong or relevant to anyone. | **Immediately**, the moment it is noticed. Not in the final report. |
| `QUESTION #n:` | A blocking question. Must include `default:` with the assumption you will proceed on. | When you cannot proceed without a decision. |
| `DONE:` | A milestone, with the commit hash, ending with the NOTE lines applied in that commit (`applied NOTE@14:02` or `no NOTEs`). | After each item's commit. |
| `DONE ALL:` | Every item finished, with all hashes and the full list of NOTEs applied. The controller merges on the agent's final report, so this line is the early warning that the report is coming. | Once, right before the final report. |
| `TO <other>:` | A message for another agent. Written to **your own** inbox. | When something you found or did concerns a specific agent. |
| `CLAIM:` | A path outside your allowlist, or a server port, that you are about to use. | Before the first edit or start. |

`STATUS` and `QUESTION` share one numbering sequence per agent (#1, #2, #3 ...), so every
reply line `#n:` in your reply file maps to exactly one thing you sent. The PLAN/PROGRESS split
exists because with seven agents the controller spent most of its effort acknowledging
progress lines that needed no answer; a PLAN is the line that can save you an hour.

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
- `NOTE@HH:MM (USER): "..."` is the user's own words, quoted verbatim; any controller
  interpretation follows on its own line. Act on the quote first. Agents acted best on the
  user's exact words and worst on paraphrases of them.
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

A claim can be narrower than a file. Naming the functions or line ranges you will touch
(`CLAIM: src/billing.py functions apply_discount, _round`) lets several agents share one file: three
agents once edited the same file concurrently with zero conflicts by claiming disjoint
functions and telling each other with `TO` lines when a signature changed.

## Options for subjective work

When an item is marked `options-first` (look, feel, wording, an API shape, anything where the
user will want to choose), do not pick for them. Build the variants as switchable variants (for example a config flag),
produce a labelled comparison (captures or a table, in your scratch folder or the report),
commit with the **old** behaviour as the default, then ask:

```
[<task>] QUESTION #n PICK: A=<label> B=<label> C=<label>; comparison at <path>; default: keep A (current)
```

Poll for the reply as for any question, keep working on other items, and apply the pick
before your next commit if it arrives; if it has not arrived by the final report, say so and
leave the variants in place for the controller to switch. One guessed variant was reworked from
scratch; three labelled ones were chosen from in a single reply.

## Exclusive resources

Every project has things only one agent can use at a time: a capture or display window, a
single test database, a device or emulator, a rate-limited API, a licensed tool, a shared
service, the shared browser pane. The controller names this project's under `EXCLUSIVE` in the brief. These, and
only these, use a lock file `locks/<resource>` holding your task name and a timestamp. Before
"wait 30 s and retry" became this rule, several agents needing the same window collided and
produced garbage captures.

Use the helper, never hand-written locking. Across several real runs, agents that locked by
hand ran their command after a failed acquire, removed another agent's lock, or left locks
behind; each time a capture or measurement was silently spoiled.

```bash
bash <mail>/lock_run.sh <task> <resource> <command...>

Waits longer than `LOCK_WARN_MIN` minutes (default 5) are logged to `<mail>/locks/waits.log` (WAIT while waiting, GOT when taken, GAVE-UP at the limit). The controller watches that file alongside the inboxes and acts on excessive waiting (fewer parallel users of the resource, or more instances).
```

It waits for the resource, never runs the command without the lock, releases only its own
lock, and takes over a lock whose recorded holder is gone (or, with no pid recorded, one older
than 30 minutes). When a resource has
several interchangeable instances (two build machines, two device slots), the controller lists them in
`<mail>/resources.conf` (`<resource> = <instance> <instance>`); the helper takes whichever is
free and passes it to the command as `$LOCK_INSTANCE`. Set `LOCK_PREFER=<instance>` when the
work needs one particular instance, for example two measurements that must be compared on the
same hardware, and say in your report which instance produced each number.

A resource can have hooks that return it to a known state. A shared device or service left
in a changed state by one holder (a process still running, a setting changed, a file left
open) spoils the next holder's work, and a crashed holder never gets to tidy up. The
controller can add, per resource, in the mailbox:

- `hooks/<resource>.acquire`: runs right after the lock is taken, before the command.
- `hooks/<resource>.release`: runs just before the lock is removed, whether the command
  succeeded, failed, or was stopped with TERM or INT.

Each must be executable, gets `LOCK_TASK`, `LOCK_RESOURCE` and `LOCK_INSTANCE` in its
environment, and should be quick and idempotent (safe to run when there is nothing to tidy).
A hook is stopped after `LOCK_HOOK_TIMEOUT` seconds (default 60). A failing or stopped hook is
reported on stderr and never keeps the lock held or changes the command's exit code. Hooks
belong to the project, not to this protocol; agents never write or edit them unless their
brief says so.

**Stopping a locked run early.** Send `kill -TERM <lock_run pid>` from bash: its trap stops the
command's whole tree, runs the release hook, and frees the lock. **Never hard-kill it**
(`taskkill /F`, `kill -KILL`): no trap runs, and on Windows the command's Git Bash children are
not in the Windows process tree, so they survive and keep using the resource. In one incident
an agent hard-killed a locked run on an exclusive device; the next waiter took the lock as
stale while the old command's children kept using the device for about 2.5 minutes, overlapping
the new holder. As a safety net, `lock_run.sh` records the command's pids in the lock folder;
on release, and before taking over a dead holder's lock, it stops every recorded process still
running.

To update `lock_run.sh` while any agent may be inside it, write the new version to a temporary
file next to it and rename it over the old one; editing or copying over it in place makes
running copies read the new bytes mid-run (bash reads a script as it goes).

Rules: wrap only the step that needs the resource; never hold a lock while polling for a reply
or running anything unrelated; if the helper gives up (exit 75), append an `ISSUE`, do the rest
of your work, and retry that step last. Stop only processes you started yourself.

## Other people's work

You will see commits, files, servers, hooks, and worktrees you did not create. They belong to
other agents or the controller. Do not revert, clean up, stop, or work around them on your own.
Say what you noticed: an `ISSUE` if it looks wrong or relevant to anyone, a `TO` line if it
concerns a specific agent, a `QUESTION` with a default if it changes what you should do next.
A plan change reaches you as a reply from the controller or a `TO` line from the other agent,
never as your own unilateral decision. No message means proceed as briefed.

## Cleaning up: processes and state

Clean up after yourself, as long as nothing is using the resource. On Windows (Git Bash),
stopping a shell kills only that shell; its pipeline partners and children keep running. One
night 113 orphaned processes from re-armed watchers, duplicate polling loops, and test shards
whose wrapper had been stopped piled up and put half the CPU in the kernel.

- **Agents** never write polling loops (`until grep ...; do sleep N; done`). Start a long command
  with the shell tool's background option and wait for its completion notice; one waiter per
  thing. The bounded 8-minute wait for a reply to a `QUESTION` is the one exception. Before the
  final report, stop every process tree you started (on Windows `taskkill //F //T //PID
  <windows pid>`, or `source <mail>/proc_lib.sh; pl_kill_tree <pid>`) and list it in the cleanup
  proof. Per-agent folders (app data, profiles, caches) live inside your scratch folder.
- **Exclusive resources**: `lock_run.sh` records the holder's pid in the owner file. A lock
  whose holder is gone is taken over at once; a lock whose holder is alive is never taken over.
  If the command is stopped, its whole tree is stopped before the lock is released, so no
  orphan keeps using the resource. Its pids are recorded in the lock folder: release, and a
  takeover of a dead holder's lock, stop any that survived (for example after a hard kill).
  Never hard-kill a locked run; stop it with `kill -TERM <lock_run pid>` from bash.
- **`sweep.sh`** (dry run by default, `--kill` to act) lists and stops what this mailbox left
  behind and nothing else: watcher pipelines whose shell is gone, polling loops whose shell is
  gone or whose task is finished, and processes started from the worktree of a finished task.
  Live lock holders, the current watcher, and live tasks are spared. It also removes lock
  folders whose holder is gone and stale watcher pid and tick files. `--done <tasks>` marks
  tasks finished; `--keep <task|pid>` or a line in `sweep.keep` marks something in use (a build
  someone is trying out from a worktree).

| What | Cleaned by | When |
|------|-----------|------|
| Processes an agent started | the agent | before its final report (listed in the cleanup proof) |
| A stopped locked command's tree | `lock_run.sh` | when it is stopped, before the lock is released |
| Lock folders whose holder is gone | `lock_run.sh`, `sweep.sh --kill` | at the next acquire; at each sweep |
| Watcher processes | `watch.sh` itself | it exits after 29:40, runs under `timeout`, and replaces an older watcher |
| Leftover watchers, loops, task processes | `sweep.sh --kill` (controller) | before re-arming a watcher, after `DONE ALL` or `PAUSE`, at wrap-up |
| Stale `.watch.pid`, `.watch-tick.*` | `watch.sh` on exit, `sweep.sh --kill` | on exit; at each sweep |
| `.watch-state` lines for deleted inboxes | `watch.sh` | each time it saves state |
| An agent's scratch folder (and app data in it) | the agent; `cleanup.sh --scratch` | final report; task cleanup |
| Worktrees, merged branches, task processes | `cleanup.sh` (runs `sweep.sh --kill --only`) | once follow-ups are decided |
