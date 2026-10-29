# Watchbill changelog

- **2026-10-28, page keeper lessons**: four additions. (1) **Fresh helper per batch**: a
  long-running relay helper re-reads its whole growing history on every wake, so its cost grows
  with its age; prefer a fresh short-lived helper per batch of updates that reads its handbook,
  the previous helper's handoff notes (a small, bounded, untracked notes file) and the target's
  current state, writes, appends its notes, and exits. (2) **The trigger moves to the
  controller**: with no standing helper nothing watches for updates, so each time the controller
  relays a meaningful update to the user, the same update goes into the helper's queue in the
  same step, and if none is running the controller starts one at once (one at a time; it takes
  everything queued); otherwise the target silently falls behind. (3) **Real dates only**: a
  brief that sets dates on records takes each record's real completion date from the project's
  own history (decision log, version control), never "now", and time-labeled lists ("done
  today") roll over by real date on every run. (4) **Cleanup by age and seen state**: a helper
  may archive items the user has seen once older than a set period; it archives, never deletes,
  and never touches open decisions or unseen items; seen-state keys are stable and independent
  of section titles, so renaming a section never makes a seen item look new.
- **2026-10-28, later**: eleven additions from the same runs. (e) **Use it like a user**: for any
  change a user will see or touch, the implementer exercises it in the real running product, in
  its normal context, beyond tests and captures, and reports a short honest note of what it did
  and how it looked or felt, problems included; a missing device is an explicit open item; the
  controller does the same before telling the user something is ready. (f) **One whole-project
  check at a time**: full suites are serialized machine-wide (the suite pool has one slot by
  default), agents run only the tests their change affects, and the full suite runs once, on the
  combined staging gate; parallel full runs slowed each other and caused load-only flaky
  failures. (g) The controller relays every meaningful update to the user as it arrives (plans,
  findings, problems, results, decisions needed, device state), skipping only pure heartbeats
  and exact repeats; a needed decision goes to the user at once; a relay layer such as a page
  keeper batches lines that arrive close together into one write and skips heartbeats. Savings
  come from efficiency, never from telling the user less. User messages always come first. (h) Relay layers (the controller, a page
  keeper) restate only what the source said, quote the user verbatim, and mark their own
  inferences. (i) Allowlists are a collision guardrail, not how work is divided; tasks are
  features or fixes and the allowlist is broad enough not to force a cramped solution. (j) The
  skill says "development work" throughout, since agents also make assets and other content.
  (k) An agent that dies mid-task (an API or authentication error) is resumed with a message
  naming what survived (scratch files, commits, locks) after its locks are checked and cleared;
  it is not restarted from zero.
- **2026-10-28, lessons from long runs**: (1) a full test suite or long measurement run under a
  lock exceeded the default 30-minute maximum hold, so `resources.conf` now takes a per-resource
  default on a line of its own (`suite max=5400`), used by `lock_run.sh` when neither `--max` nor
  `LOCK_MAX` is given (test 16d fails without it); a long run still sets its own `--max`, sized to
  the run, when it takes the lock. (2) Agents reported `no NOTEs` while a NOTE sat in their reply
  file, so a mandatory instruction now goes both to the reply file and as a direct message to the
  agent. (3) Exclusive devices and measurements: check the device's state at the start of each
  run (awake and unlocked, power state if it affects the measurement, thermal state with
  cool-down gates); see the runtime notes.
- **2026-10-22, hung runs**: two locked runs hung (a device-bound run for 46 minutes, whose own
  timeout never fired, and a capture bound to a shared accelerator for over an hour, in a visible window) and nobody
  noticed until the user did. `lock_run.sh` now has a maximum hold time: `LOCK_MAX` seconds,
  default 1800, or `--max SECONDS` per call (0 = no limit). Past it the command's whole tree is
  stopped, the release hook runs, the lock is freed, the helper exits 124, and
  `ISSUE: <task> <resource> held past N s; command stopped` is appended to the task's inbox, where
  the watcher sees it. Agents with a legitimately longer run pass a bigger limit explicitly and
  post a PROGRESS line at least every 20 minutes while holding a lock; the controller checks lock
  ages on each watcher re-arm and flags old holds with no progress. Tests 16 to 16c in
  `tests/lock_run_test.sh` fail without the feature.
- **2026-10-22, later**: an agent hard-killed a locked run on an exclusive device. The lock freed
  (the trap never ran, the next waiter saw a dead holder), but the command's Git Bash children
  are not in the Windows process tree, survived, and kept using the device for about 2.5 minutes
  alongside the next holder. `lock_run.sh` now records the command's pids in the lock folder;
  release, and a takeover of a dead holder's lock, stop any still running first. The safe way to
  stop a locked run early (`kill -TERM <pid>` from bash, never a hard kill) is in PROTOCOL.md and
  the implementer template. Tests 14 and 15 in `tests/lock_run_test.sh` fail without the fix.
- **2026-10-22**: two corrections. (1) The skill is generic: wording tied to one kind of project
  (wording tied to one kind of project) was replaced with domain-neutral
  examples; resources are just resources. (2) The page keeper runs its own read-only watcher,
  not `watch.sh` (which stops other watchers), under `timeout` just under the monitor limit, and
  on stop ends the watcher's whole process tree and verifies by listing processes. A real run on
  Windows left bash/timeout processes after a monitor stop while a dry-run sweep reported none.
- **2026-10-21, later**: two additions. (1) An optional **page keeper**: a long-running agent that
  owns a user-facing status and decisions page. Its controller had tried to keep such a page
  current itself, fell a whole day behind, claimed decisions were on the page that were not, and
  once forgot to resume the writer after a pause; a dedicated keeper with its own watcher and a
  per-project handbook fixed all three. New "Page keeper (optional)" section,
  `templates/page-keeper.md`, and a setup question. (2) **Model policy set by the user, by type of
  work**, replacing the per-task suggestion default that leaned to the strongest model: setup
  shows a tier table with example work, the user's answer is recorded in the project, and every
  dispatch names the tier and why. New `MODEL` line in the dispatch brief. The user also asked
  for **spot checks**: the best model samples cheaper agents' work so a quiet failure on a
  cheaper tier is caught early (see "Roles and models"), and for **plain outcome feedback**: the controller tells the user
  whether each agent succeeded, partly succeeded, or failed, with how it was verified (see
  "Tell the user how each agent did").
- **2026-10-21**: clean up after yourself, as long as nothing is using the resource. After 113
  orphaned watcher processes, duplicate polling loops, and orphaned test shards piled up
  overnight on Windows: `watch.sh` exits by itself just under the 30-minute Monitor limit,
  runs under `timeout`, keeps one instance per mailbox, spawns almost nothing per pass, and
  covers inboxes added later without a re-arm; new `sweep.sh` (dry run, `--kill`) stops this
  mailbox's leftovers and spares live locks, live tasks, and the current watcher; `lock_run.sh`
  records the holder's pid, takes over a dead holder's lock at once, never takes over a live
  holder's, and stops a stopped command's whole tree before releasing; shared `proc_lib.sh`;
  templates forbid polling loops and require stopping started process trees;
  `setup.sh --update-helpers`; `cleanup.sh` sweeps the tasks it removes and takes `--scratch`.
  Tests in `tests/sweep_test.sh` and `tests/lock_run_test.sh`. Also in this change: the
  implementer template's earlier edits (time-stamped inbox lines, timeboxes and heartbeats,
  `DONE ALL` quoting the last NOTE read, re-orienting after a resume, affected-tests-first
  testing).
- **2026-09-29**: `lock_run.sh` runs optional per-resource hooks,
  `.agent-mail/hooks/<resource>.acquire` and `.release`, so a shared device or service left in
  a changed state by one holder is returned to a known state before the next holder gets it;
  a failing or slow hook never keeps the lock. Tests in `tests/lock_run_test.sh`. Example
  wording made domain-neutral throughout.

- **2026-09-27, later**: exclusive resources go through one helper, `lock_run.sh`, which also
  shares a pool of interchangeable instances declared in `.agent-mail/resources.conf`;
  hand-written locking is no longer allowed.
- **2026-09-27**: the controller keeps a minimal decision log (`docs/DECISIONS.md`) of user
  decisions and the steps taken after them, committed on integration, and reads it first on
  resume.
- **2026-09-24, round 2** (a two-day run, about 25 dispatches, up to 7 parallel agents):
  `STATUS` split into `PLAN` (answered) and `PROGRESS` (read, not answered); relayed user
  feedback marked `NOTE (USER)` with a verbatim quote; options-first pattern for subjective
  work; reviewer after every merged batch without exception; red-integration policy; task
  worktrees kept until follow-ups are decided and follow-ups reuse the task name; a standing
  user model preference overrides the per-task suggestions; domain wording demoted to examples.
- **2026-09-24, round 1** (a multi-day run with 3 to 4 agents): per-agent scratch folders;
  `setup.sh --add` and live-mailbox refusal; watcher offsets in `.watch-state` with `--replay`;
  lock files for exclusive resources; `NOTE@HH:MM`, applied-NOTE suffixes, and `PAUSE`;
  scope-change broadcast; staging merges; windowed-capture evidence, verbatim test counts,
  mutation proof; Windows and cloud-sync hazards; the controller never `cd`s.
- **2026-09-10 to 09-13**: first version. Worktrees, allowlists, file mailbox with acknowledged
  statuses, claims as notices, independent reviewer, templates read from disk, single-task use.
