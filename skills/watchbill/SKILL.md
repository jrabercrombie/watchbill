---
name: watchbill
description: Dispatch implementation work to subagents in a git repo, each in its own git worktree, coordinated through a file mailbox (.agent-mail/) with an independent reviewer, no agent-teams messaging needed. Use this whenever any implementation task, one or many, is being handed to a subagent in a git repo: a single bug fix, one feature, or a whole plan; parallelism is a bonus when there are several tasks, not the reason to use it. Also use it whenever the user mentions worktrees, parallel agents, dispatching implementers, watchbill, an agent mailbox, .agent-mail, batches of tasks, or wants cheaper models doing the implementation while this session only coordinates. Even if the user just says "run the plan" or "fix these bugs" and there are several independent items, use this skill.
---

# Watchbill: implementers in worktrees with a file mailbox

This session is the **controller**. It dispatches subagents, watches a mailbox, answers
questions, merges, and decides. It does not implement, and it never reads agent transcripts,
only final reports and mailbox lines. Every rule below exists because of something that went
wrong on a real project; the reason is given so you can apply the rule sensibly rather than
mechanically. The skill is general-purpose: nothing in it is specific to one kind of project,
and each project decides its own exclusive resources, hooks, and runtime notes, which live in
that project's `.agent-mail/`, never in the skill.

## Changelog

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

## When to use

This skill coordinates development work of every kind: code, and also assets and other content the agents make.

- Any implementer dispatch in a git repo, including a single task. The value is the mailbox (a
  `STATUS` before each item that the controller acknowledges or corrects before the first
  commit), the worktree (half-finished edits never hot-reload into the main checkout), and the
  independent reviewer. A bare Agent call has none of those, and a one-task job once went out
  that way because this section said the skill was only for parallel work.
- With several tasks, partition them by file so they do not need each other's edits; tasks that
  all touch the same few files are serialized or given to one agent. Running them at the same
  time is the bonus, not the requirement.
- A git repo, and a session that stays alive to run a persistent watcher.

## Roles and models

| Role | Model | Where it works | Writes |
|------|-------|----------------|--------|
| Controller (you) | the session's model | main checkout on the integration branch | only `.agent-mail/<task>.reply` files, staging merges, worktree cleanup |
| Implementer | the tier the model policy gives its type of work (below) | `.worktrees/<task>` on branch `<task>` | its allowlist, its own `inbox-<task>.log` |
| Reviewer | a strong tier: `opus` by default, `fable` for a high-stakes batch | main checkout, read-only | its own `inbox-review-<batch>.log` only |
| Merge agent | per the policy; `sonnet` by default (well-specified: resolve conflicts, run the suite) | `.worktrees/<task>` | conflict resolution on branch `<task>` |

**The user sets the model policy, by type of work; you do not guess it per task.** At setup
(step 0) show the user the tier table below, with its example work, and ask for their policy:
which tier for which kind of work. An earlier version suggested a model per task and leaned to
the strongest one for implementers; the user then had to correct it round after round, and a
dispatch that surprises them on quality or spend is a failure of this step. Record the answer in
the project, in `.agent-mail/models.conf` (one line per tier: tier, model, work types) or in the
project's own notes or memory, and read it before every dispatch. `setup.sh` reset leaves that
file alone.

| Tier | Model | Example work |
|------|-------|--------------|
| Light | `haiku` | lookups ("where is this defined", "what calls this"), code or doc surveys, log or transcript analysis, doc edits, simple generated reports |
| Standard | `sonnet` | well-specified work with a test or a number to hit: tools and generators, measurements, probe fixes, merge agents, the page keeper |
| Strong | `opus` (Claude Opus 5.5) | judgment calls on subjective quality, work spanning several systems, vetting of generated or captured output, diagnosis of unclear bugs, the final reviewer before landing |
| Strongest | `fable` (Claude Fable 5.1) | the highest-stakes review: a large batch, or one where a miss would be expensive |

The table is the default offer. It is a default, not a limit: the user may move any work type
to any tier (newer models change what each tier can be trusted with), rename the tiers, or
put everything on one model.

- **Every dispatch line names the tier and why**, in the message that tells the user what was
  dispatched ("task-b: Standard, a generator with a number to hit") and in the brief's `MODEL`
  line. The reason is what lets the user correct the policy instead of the single dispatch.
- **A standing user policy overrides per-task suggestions.** If a task looks mis-tiered, say so
  and ask; do not quietly choose differently.
- **Check Haiku's numbers before relaying them.** Counts, sizes, and timings from a Light-tier
  survey are confirmed by a command or a second look; its locations and summaries are usually
  fine.
- **Do not restart a running agent just to change its model.** The restart throws away its
  context and its place in the item. Switch at the next dispatch or at a pause.
- Reviewer: a strong tier by default, the strongest when the batch is large or a miss would be
  expensive. Review is cheaper than implementation (one pass over a merged tree, no fix rounds)
  and a strong reviewer catches more. Its independence comes from a fresh context and the "do
  not trust the reports" rule, not from being a different model than the implementer.
- **Spot checks.** Cheaper tiers only stay trustworthy if someone looks. The best model
  available (`opus`, or `fable` for high stakes) samples the work of agents on cheaper tiers.
  Code is already covered: the post-merge reviewer (step 7) runs on the strongest tier whatever
  tier wrote the code. For non-code output (page keeper writes, measurements, output vetting,
  lookups), a strong agent re-verifies one or two claims per cheaper agent per batch against the
  primary source (the page itself, the measuring command, the output, the code the lookup named),
  and makes an early check when an agent starts a long job, since a wrong start is cheapest to
  catch in the first minutes. A miss widens the check to that agent's whole output, and the fix
  goes into its brief or handbook so the same miss does not recur. Dispatch these checks as
  small read-only tasks on the strong tier; report their results to the user with the dispatch
  lines.
- Controller: this session's model. Coordination is the smallest share of the spend and a
  misjudgment there costs the most.

Opus 5.5 defaults to `medium` effort; pass a higher effort explicitly for implementation with
runtime verification, or it will under-think exactly the tasks it was chosen for. A run of
three Opus agents still produced tests that could not fail, a false alarm from stubbed
runtime data, and a commit made past a scope change; the model does not replace the rules above.

Dispatch with the Agent tool: `subagent_type: "general-purpose"`, `model` per the task,
`run_in_background: true`, and a **short brief that points at the template file** (step 4).
The template on disk is the contract; the brief only supplies the values.

## The rules, and what they prevent

1. **One worktree per task.** `.worktrees/<task>` on branch `<task>`, created from the
   integration branch. Before worktrees, agents edited the same folder, stomped each other's
   changes, and half-finished edits hot-reloaded into a running app.
2. **Unique dev-server port per agent, and never stop a server you did not start.** An agent
   once killed another agent's server because it looked stray.
3. **File allowlists.** Every prompt names the files the agent may edit. The allowlist is a
   collision guardrail, not how the work is divided: tasks are features or fixes, and the list
   is broad enough that it never forces a cramped solution. Anything else needs a
   `CLAIM` line first. Never modify source materials or user-owned assets; fix alignment or
   behavior through code, config, or data.
4. **Evidence, not claims.** Tests and typecheck clean before every commit; a runtime check
   with described evidence for any behavior change (captures, logged values, measured
   numbers); a "Deviations and concerns" section; an "Issues found" section; proof that
   temporary hooks and scratch files are gone. Agents have said "fixed" on unit tests alone
   while the live behavior was still broken. Three refinements from later runs: test counts
   are the runner's final line pasted verbatim (a report said 15 new tests, the runner said
   13); every new test comes with a mutation proof, shown failing against a deliberate break
   of the code it guards (the reviewer kept finding tests that could not fail); and any claim
   about what a user sees or gets needs a capture from the real environment, and, beyond
   captures and tests, the implementer uses the change like a user would in the real running
   product, in its normal context, and reports honestly what it did and how it looked or felt
   (a device it lacked is stated as an open item); the controller does the same before telling
   the user something is ready. The capture rule in full: it comes from the real environment that the agent
   opened and described honestly, because an environment with stubbed services (a display-less environment, a mocked
   API, a fake device) returns data that looks real and has produced both a false alarm and a
   flawed capture called "correct".
5. **Findings go out immediately, and so does intent.** An `ISSUE` line the moment something is
   noticed, not in the final report thirty minutes later. A `STATUS PLAN` line before each item
   saying how it will be done, which the controller acknowledges or corrects; a wrong reading
   of the brief is cheapest to fix before the first commit. Observations and heartbeats go as
   `STATUS PROGRESS`, which the controller reads but does not answer. With seven agents the
   controller spent most of its effort acknowledging progress lines that needed no answer.
6. **Other people's work is expected.** Agents will see commits, files, servers, and hooks they
   did not create. Report what you see, ask if it changes your plan, never revert or work
   around it without a message from the controller or the owning agent. No message means
   proceed as briefed.
7. **Nothing waits on another agent.** Claims are notices, not locks. Questions carry a default
   assumption and a time limit. So there is no deadlock. The one bounded exception is an
   **exclusive resource** (rule 11).
8. **Independent reviewer, after every merged batch, no exceptions.** A read-only reviewer is
   told not to trust the implementer reports and to verify by reading code and running
   commands. One day six branches merged with no review, after every earlier review had found
   real bugs the implementers reported as fine: a converter corrupting its output, a test runner
   passing broken tests four ways, a boundary check that let things through, a click firing on
   release.
9. **One writer per shared document.** A spec that several agents would edit goes to one
   agent per batch, or each agent writes `docs/notes/<task>.md` and the controller folds the
   notes in afterwards.
10. **One scratch folder per agent.** The session scratchpad is shared by every subagent, so
    each agent works only in `<scratchpad>/<task>/` and deletes only inside it. One agent's
    cleanup once deleted another's helper scripts mid-run. Reviewers never put probe files in
    the repository; a probe test dropped into the test folder hung the controller's suite run.
11. **Exclusive resources are locked, briefly, through one helper.** Every project has things
    only one agent can use at a time (a capture or display window, a single test database, a
    device or emulator, a rate-limited API, a licensed tool, the shared browser pane). The
    controller identifies them when partitioning and lists them in the brief. When the machine
    has several interchangeable instances of one (two build machines, two devices, two test
    databases),
    the controller lists them in `.agent-mail/resources.conf` so two agents can work at once
    instead of queueing. Agents run the step that needs the resource through
    `.agent-mail/lock_run.sh <task> <resource> <command...>`, which waits, never runs without
    the lock, frees only its own lock, takes over stale ones, and hands the chosen instance to
    the command. Hand-written locking failed repeatedly: commands ran after a failed acquire,
    agents deleted each other's locks, and measurements were silently taken on shared hardware.
    When one holder can leave the resource in a changed state (a process still running, a
    setting changed), the controller adds a project-side `.agent-mail/hooks/<resource>.release`
    (and optionally `.acquire`) that returns it to a known state; see PROTOCOL.md.
    A resource whose runs are long (a full suite, a long measurement) gets its own default
    maximum hold with a `<resource> max=<seconds>` line in `resources.conf`, and a long
    measured run passes `--max` sized to the run when it takes the lock.
12. **Instructions must be seen before they matter.** Agents read the reply file in the same
    shell command as every commit and before any step longer than five minutes; every
    `STATUS` and `DONE` lists the `NOTE@HH:MM` lines applied; anything mandatory goes out as a
    numbered reply to the agent's latest status, never as a bare NOTE, and also sent as a direct
    message so a missed file read cannot hide it; `NOTE@HH:MM: PAUSE`
    means finish the step, commit green work, skip the rest, report. Agents have committed
    seconds after a scope change landed because their last read was at the start of the item.
13. **Merge through a staging branch.** Two branches that each passed alone once produced a
    failing integration branch when merged, and undoing the merge needed a `git reset --hard`
    the safety system refused. Merges land in a staging worktree, the suite runs there, and
    integration fast-forwards only when green.
14. **The controller never `cd`s.** A `cd` into a worktree moved the session's working
    directory and every later relative path with it. Use `git -C <path>` and absolute paths.
15. **Clean up after yourself, as long as nothing is using the resource.** Every process,
    lock, folder, and state file the round creates is removed by whoever created it once
    nothing uses it, and the controller sweeps for what slipped through. On Windows, stopping
    a shell kills only that shell: one night, each 30-minute re-arm of a hand-written
    `tail -F | grep | cut` watcher left the previous pipeline running, agents left duplicate
    `until grep ...; sleep` loops, and stopped test wrappers left their shards; 113 orphans
    (about 583 MB) and the process churn put half the CPU in the kernel. So watchers time out
    by themselves, agents write no polling loops and stop every tree they start,
    `lock_run.sh` stops a stopped command's tree before releasing (and stops a command that holds
    its lock longer than the maximum hold, 30 minutes unless the call asks for more), and `sweep.sh` stops what is
    left, never anything a live lock, a live task, or the current watcher is using. None of
    this depends on the platform changing how it stops processes. What is cleaned, by whom,
    and when is tabled in PROTOCOL.md, "Cleaning up".

## Controller loop

### 0. Ask the setup questions
Once per project (read the recorded answers on later rounds instead of asking again):

1. **Model policy.** Show the tier table from "Roles and models" and ask which tier the user
   wants for which kind of work; record the answer (`.agent-mail/models.conf` or the project's
   notes).
2. **Page keeper.** Ask whether they want a user-facing page kept current by a dedicated agent
   (see "Page keeper (optional)"). Offer it plainly when the round is long, has several agents,
   or the user makes decisions during it; say what it costs (one agent for the round, Standard
   tier by default). If yes, get the page URL and where its handbook lives.

### 1. Partition
Group the plan's items into tasks with disjoint file sets. With one task the partition is
trivial: one allowlist, one port, one tier; still write them down, the brief needs them. For
each task decide the allowlist, port, tier (from the user's policy), and items. If two tasks need the same file, either
combine them into one task or give the file to one task and let the other log an `ISSUE`
describing the change it wanted. List every **exclusive resource** this project has by
name (a capture or display window, a test database, a device, a rate-limited API, a
licensed tool, the shared browser pane); agents lock those and only those. Mark subjective
items `options-first` so the agent builds labelled variants instead of guessing.

### 2. Set up the repo
`<skill-dir>` below is this skill's base directory, reported when the skill was loaded (a
plugin install puts it under `~/.claude/plugins/`, a clone under `~/.claude/skills/`).
```bash
bash "<skill-dir>/scripts/setup.sh" --setup "npm install" task-a task-b task-c
```
This appends the gitignore lines if missing, creates `.agent-mail/` with `PROTOCOL.md` and
the helpers (`watch.sh`, `lock_run.sh`, `proc_lib.sh`, `sweep.sh`), **clears old inbox, reply, lock, and watcher-state files**, creates
`.worktrees/<task>` on branch `<task>` from the current branch, and runs the optional setup
command in each worktree. It prints the absolute mailbox path and each worktree path for the
templates. Run it from the repo root on the integration branch.

It **refuses** when the mailbox looks live (an inbox or reply written in the last 30 minutes,
or task folders under `.worktrees/`). A reset run mid-round to add one task once wiped every
agent's inbox and reply file and an agent lost two instructions. To add a task while agents
are running:
```bash
bash "<skill-dir>/scripts/setup.sh" --add --setup "npm install" task-d
```
which creates only the new worktree and its empty inbox and reply files. `--force` overrides
the refusal when you know nothing is running. `setup.sh --update-helpers` replaces only the
helper scripts (each renamed into place, safe while they run), for a mailbox created by an
older version of the skill.

### 3. Start the watcher
```
Monitor({ command: "timeout 1790 bash .agent-mail/watch.sh", description: "agent mailbox", timeout_ms: 1800000 })
```
Each `ISSUE`, `QUESTION`, `DONE`, `TO`, and `CLAIM` line arrives as a notification. One
watcher covers every inbox, including ones `setup.sh --add` creates later, so adding an agent
never needs a re-arm. The watcher saves its per-file offsets in `.agent-mail/.watch-state`,
so when the Monitor expires (at most 30 minutes) and you re-arm it, it continues from where it
stopped. It used to replay the whole inbox on every restart, and each replay read as a flood
of new events. Pass `--replay` only when you want the history, such as when resuming after a
session restart.

It cleans up after itself: it exits by itself at 29:40, the `timeout` stops it even if that
fails, and a new watcher stops the previous one (`.agent-mail/.watch.pid`). Never hand-write a
`tail -F inbox-*.log | grep | cut` Monitor: on Windows each re-arm left the old pipeline
running, 113 processes by morning. Before re-arming or replacing a watcher, run
`bash .agent-mail/sweep.sh --kill`.

### 4. Dispatch
Do not paste the template into the prompt. The lead model's output is the most expensive
token in the system, and a full template per agent was the single largest line in a real
run's bill. Instead send each agent a short **brief**: the values that fill the template, plus
one instruction to read the template file itself. `templates/dispatch-brief.md` is the shape;
copy it, fill it, and launch all Agent calls **in one message** so they run concurrently.

The brief carries: `TASK`, `MODEL` (tier and the reason), `BRANCH`, `WORKTREE`, `MAIL`, `INTEGRATION`, `PORT`, `SCRATCH`
(this session's scratchpad directory, from your system prompt; each agent uses only
`<scratchpad>/<task>/`), `EXCLUSIVE` (the lock-file resources, or `none`), the allowlist, the
read-only context files, `OTHER_TASKS`, the items pasted verbatim from the plan with the
evidence each must produce, the test / typecheck / build / dev commands, and the runtime notes
(see "Runtime verification notes"). The agent reads `<skill-dir>/templates/implementer.md`,
substitutes the `{{...}}` placeholders from the brief, and follows it. Reviewers and merge
agents get the same treatment with `templates/reviewer.md` and `templates/merge-agent.md`.

Keep the brief itself lean: items and evidence in full, everything else one line each. What
the template already says (mailbox rules, evidence rules, report format) is never repeated.

### 5. Handle mailbox lines

| Line | Controller action |
|------|-------------------|
| `STATUS #n PLAN` | Read it against the brief and the design. If the approach is right, append `#n: ACK`. If not, append `#n: <what to do instead>`, concrete enough to act on. Every PLAN gets one of the two; the agent reads it before that item's first commit. |
| `STATUS #n PROGRESS` | Read it; check the `applied NOTE@` suffix. Reply only to correct something. With seven agents, answering every progress line was most of the controller's effort and none of its value. |
| `ISSUE` | Read it. If it needs a decision now, write a reply. Otherwise note it for the review or the post-merge list. |
| `QUESTION #n` | Decide, then append `#n: <answer>` to `.agent-mail/<task>.reply`. The agent proceeds on its default after 8 minutes, so answer promptly or accept the default. |
| `QUESTION #n PICK` | An options-first item is ready. Show the user the comparison and relay their choice as `#n: B`, quoting any reason verbatim. If it arrives after the agent's report, switch the variant yourself after merge. |
| `TO <other>` | Nothing, unless the target has already finished or is not running; then relay by reply file to whoever needs it. |
| `CLAIM` | Check for a conflicting claim from another agent. If there is one, reply to the later claimant to skip and log an ISSUE. |
| `DONE` | Progress only (one per item). Nothing to do. |
| `DONE ALL` | The final report is about to arrive. Merge (step 6) when the agent's completion notification lands, not before: the report is what you check for evidence. When it lands, run `bash .agent-mail/sweep.sh --kill` (a task whose last line is `DONE ALL` counts as finished) and compare what it stopped with the report's cleanup proof. |

Reply file (the only file the controller writes). Numbered lines answer a status or question
with that number; `NOTE@HH:MM:` lines are unsolicited instructions stamped with the time.
Agents read the file before each item, in the same command as each commit, before any step
over five minutes, after each runtime check, and before the report, and list the NOTEs they
applied in every `STATUS` and `DONE`:
```bash
printf '#1: ACK\n' >> .agent-mail/task-a.reply
printf '#2: no, keep the bounds in src/types.ts; formation already reads them from there\n' >> .agent-mail/task-a.reply
printf 'NOTE@%s: formation now owns src/types.ts; do not claim it\n' "$(date +%H:%M)" >> .agent-mail/task-b.reply
printf 'NOTE@%s: PAUSE\n' "$(date +%H:%M)" >> .agent-mail/task-c.reply
printf 'NOTE@%s (USER): "the jump feels floaty, cut the hang time"\n' "$(date +%H:%M)" >> .agent-mail/task-a.reply
```
Relayed user feedback is always the user's exact words in a `(USER)` line; put your own
interpretation on a separate line if it is needed at all. Agents acted best on the quote and
worst on paraphrases of it.
`PAUSE` means: finish the current step, commit what is green, skip the remaining items,
report. After a paused agent's report, run `sweep.sh --kill --done <task>`. Use it when the plan changes under an agent or the budget is gone; it beats letting
the agent finish items you will throw away.

Answering statuses is the controller's main job while agents run. Each one is a chance to
catch a misread brief before it costs an hour, so read the status, not just the prefix. Keep
replies to one line; an agent that needs more than that needs a new brief, not a longer reply.
**Anything mandatory goes out as a numbered reply to the agent's latest `STATUS`, never as a
bare NOTE.** A NOTE can land between checkpoints and be missed; a numbered reply is read
against a status the agent is waiting to hear about. Then check the next `STATUS` or `DONE`:
each one ends with the NOTEs applied (`applied NOTE@14:02` or `no NOTEs`), so a missing entry
means the instruction did not land, and you repeat it as a numbered reply. Agents have
committed with the old scope because a NOTE arrived after their last read. Agents have also
reported `no NOTEs` while a NOTE sat in their reply file. So **every mandatory instruction goes
to both places: the reply file and a direct message to the agent**, and the next status must
still quote it as applied.

**Scope changes are broadcast.** When you move an item, or a file, from agent A to agent B,
tell both, in numbered replies, with the exact file ownership after the change:
```bash
printf '#4: item 3 (spawner tuning) moves to task-b; you no longer own src/spawner.ts; skip it\n' >> .agent-mail/task-a.reply
printf '#2: you now own item 3 (spawner tuning) and src/spawner.ts; task-a has been told\n' >> .agent-mail/task-b.reply
```
Told only one side, A keeps the item in its plan and B flags an overlap, and both lose time.

### 6. Merge on DONE, through staging
Two branches that each passed alone have produced a failing integration branch when merged,
and undoing a merge in the main checkout needs a `git reset --hard` that the safety system
refuses. So merge into a staging worktree, test there, and fast-forward integration only when
green. Never `cd` into it; a `cd` from the controller moved the session's working directory.
```bash
git worktree add --force -B integration-staging .worktrees/_staging <integration>
git -C .worktrees/_staging merge --no-ff task-a -m "merge: task-a"
git -C .worktrees/_staging merge --no-ff task-b -m "merge: task-b"
bash -c 'cd .worktrees/_staging && <test cmd> && <typecheck cmd> && <build cmd>'
git merge --ff-only integration-staging          # in the main checkout, only when green
```
If staging is red, nothing has touched integration: fix on the task branch (a fix dispatch),
or `git worktree remove --force .worktrees/_staging` and start staging again from
integration. Small conflicts: resolve in the staging worktree with `git -C`. Large ones:
`git -C .worktrees/_staging merge --abort`, dispatch `templates/merge-agent.md` for that task,
merge again on its `DONE`. `git merge-tree --write-tree <integration> <task>` previews a
conflict without touching any checkout. Keep task worktrees until the review is done; fix
agents reuse them. Remove `_staging` with the other worktrees at cleanup.

Integration must be green after every fast-forward. If a test is red for a reason nobody is
fixing now, quarantine it explicitly: skip it with a reason and an owner in the skip itself,
record an `ISSUE`, and put it on the open list. A known-red test left in place for hours made
every agent report "all pass except the known one", which hid a new failure in that test.

### 7. Review the batch, every batch
When every task in the batch is merged and the merged tree is green, dispatch the reviewer.
This step is never skipped, however small the batch or however clean the reports: the one day
it was skipped, six branches went in unreviewed, after every previous review had found real
bugs the implementers had reported as fine. Dispatch
`templates/reviewer.md` (the strongest model you can afford, read-only, own port, its own
`SCRATCH` folder, the same `EXCLUSIVE` list). It reports per item PASS/FAIL with `file:line` and a concrete fix for
each FAIL, repeats at least one mutation proof per item, and pastes the runner's final line.

### 8. Fix, re-merge, clean up
Dispatch fixes to the original task's worktree (same implementer template, same task name,
same inbox and reply files, items = the FAIL list for that task, branch already exists).
Merge on `DONE`, run the suite again. The full suite runs once, here, on the combined staging
gate, and one whole-project check at a time: the `suite` pool has one slot by default (a resource
not listed in `resources.conf` has a single instance; add a `suite max=<seconds>` line for the
maximum hold), and
the controller runs it through `lock_run.sh`. Agents ran full suites in parallel and slowed each
other into load-only flaky failures. Do not clean up until the review is in and the follow-up
list for each task is decided: twice a worktree was removed and the same agent then needed
more work, which forced a new task name and fresh mailbox files. Follow-ups reuse the task
name. Then:
```bash
bash "<skill-dir>/scripts/cleanup.sh" task-a task-b task-c
```
which first stops those tasks' leftover processes (`sweep.sh --kill --only`), then removes
each worktree and deletes each fully-merged branch (it refuses unmerged ones). Add
`--scratch <scratchpad>` to delete each task's scratch folder too, which also holds any
per-agent app-data folder the brief created.
Include `_staging` in the list. On Windows, worktree folders can stay locked for a while
after agents finish; the script retries quietly, falls back to a plain delete, and ends with
one summary line. Stale `.git/worktrees/<task>` records it names there are harmless once
`git worktree list` shows only the main checkout; delete them later by hand if they bother you.

### 9. Fold in and report
Run `bash .agent-mail/sweep.sh` once more; with no agent running, anything it lists to stop is
a leftover, and `--kill` takes it. Apply any ISSUE-listed edits that were skipped because of claims, fold `docs/notes/<task>.md`
into the shared doc, and tell the user what merged, what the reviewer found, and what is still
open.

### 10. Tell the user how each agent did
Do this as each event happens, not only at wrap-up. When each agent finishes (its final report
or `DONE ALL` landing, a paused agent's report, a fix agent's report), and after each spot
check and each review, tell the user plainly whether it **succeeded, partly succeeded, or
failed**. Every such message has:

- **Result**: which of the three, in the first words.
- **How it was verified**: the tests (the runner's final line), measured numbers, captures the
  reviewer or you opened; say so when something rests only on the agent's own claim.
- **What failed or is still open, and what happens next**: the failing item, the follow-up
  dispatch, or the decision waiting on the user.
- **For a spot check**: whether that agent's claims held up, and which ones were re-verified.

Relay every meaningful update to the user as it arrives: plans, findings, problems, results,
decisions needed, device state. Skip only pure heartbeats and exact repeats. Anything needing a
user decision goes to the user at once. A relay layer such as a page keeper batches lines that
arrive close together into one write and skips heartbeats; the savings come from efficiency,
never from telling the user less. User messages always come first. **Relays are faithful**: the controller (and a
page keeper) restates only what the source said, quotes the user verbatim, and marks anything
it inferred as its own inference.

No silent finishes: an agent that completes and merges without a word to the user leaves them
guessing whether anything happened. A failure is reported as a failure, in those words, not as
"mostly done" or buried in a list of merges. If a page keeper runs, the same message also goes
to it as an event.

## Decision log

The controller keeps `docs/DECISIONS.md` on the integration branch (a project may name another
path; say so in the partition). It is the durable record of what the user decided and what was
done about it, so neither the user nor a resumed session has to rely on memory or transcripts.
Keep it minimal: one line per entry, newest last, under a date heading.

```
## 2026-03-14
- Decided: the dark theme is the default; the light theme stays selectable ("dark reads better")
- Done: dispatched task-b to make the dark theme the default
- Done: merged task-b (1a2b3c4), suite 212 green
```

Write every entry as a plain description a reader can understand months later without the
conversation. Never refer to a choice by its label from an options round ("option B", "variant
2", "N1"): write what was chosen ("rounded corners", not "B"). Quote the user briefly when the
wording matters. Point at commits, files, and captures instead of repeating their content.
Add a `Decided:` line when the user decides and a `Done:` line after each dispatch and merge, and
commit the log with the merge or on its own. Do not log agent-internal steps, statuses, or
reviewer findings; the mailbox and reports hold those.

## Page keeper (optional)

(A page keeper is a relay layer: it records only what the source said, quotes the user
verbatim, and marks its own inferences as such.)

Some users want a page (for example a hosted status board with a small database) that shows
what each agent is doing, highlights with real times, and the decisions waiting on them, with
attachments whose labels match the options, and that they answer on. Keeping it current is a job of
its own. On one project the controller kept it up itself, fell a whole day behind, claimed
decisions were on the page when they were not, and once forgot to resume the writer after a
pause. A dedicated long-running **page keeper** agent fixed all three.

**Offer it at setup** (step 0) and run it only if the user says yes. Dispatch it from
`templates/page-keeper.md` like any other agent, with its own inbox, reply file, and scratch
folder; it needs no task worktree.

**It owns:** every write to the page and its data, and the per-project handbook (for example
`docs/PAGE_KEEPER.md`: page URL, data schemas with examples, media rules, the event-to-write
mapping, don'ts, failure modes, and a cold-start checklist) so a replacement can take over with
no other context. It runs its own read-only watcher (never `watch.sh`, which would stop the controller's; a
bounded script under `timeout` just under the monitor limit, re-armed on expiry) and writes the
page on every event: agent
`PLAN`, `PROGRESS`, `DONE`, and `ISSUE` lines, merges, lands, and findings.

**It never** makes decisions, picks, or default changes, and never writes as the user. A pick
on the page is the user's; the keeper records only what the user actually chose.

**Stopping the keeper's watcher:** the keeper ends the watcher's whole process tree and
verifies by listing processes that none is left (a stopped monitor leaves its `timeout` and
bash children running on Windows, and a dry-run `sweep.sh` can report none while they live).

**The controller's duties:**
- Report each agent's outcome to the user (step 10), and send the keeper the same event.
- Send the keeper the events it cannot see in the mailbox (merges, lands, reviewer findings) and
  the user's words, directly and at once, not only by reply file.
- Resume the keeper after every pause or restart; check it is running in the same step that
  restarts the watcher.
- Read the user's picks from the page at the start of every user turn, and treat the page, not
  memory, as the record of what is pending. Never claim something is on the page without
  reading it.
- Never hand-edit the page while a keeper runs; a second writer makes the keeper's state wrong.
  Send it the change instead.

## Resuming after a session restart

Background agents and the watcher do not survive a session restart, but their worktrees,
commits, and mailbox lines do. On resume:

0. Read `docs/DECISIONS.md` for what the user decided and what was last dispatched and merged.
1. `git worktree list` and `git log main..<task>` for each task: the branch shows what landed;
   the mailbox `DONE` lines say which items those commits were.
2. Check the worktree is clean and no stray servers hold ports (`netstat -ano | grep LISTENING`).
3. Run `bash .agent-mail/sweep.sh` and read it: the agents are gone, so watcher pipelines,
   loops, and task processes it lists are leftovers; `--kill` them. Then restart the Monitor
   on `timeout 1790 bash .agent-mail/watch.sh --replay` to see the whole history once, read as history,
   not as new events. Without `--replay` it resumes from `.watch-state` and shows only what
   arrived after the previous watcher stopped.
4. A stopped agent cannot be messaged back to life after a session restart. Dispatch a fresh one
   with the same brief plus a paragraph naming the commits already on the branch and the item
   to start from, and tell it to number its statuses after the last one in the inbox.
   An agent that died mid-task on its own (an API or authentication error) is resumed, not
   restarted from zero: check for and clear its locks first (`ls .agent-mail/locks`, stale or
   dead-holder ones), then resume it with a message naming what survived: its scratch files,
   its commits on the branch, and any locks it still held.
5. If a page keeper was running, resume it with its handbook (it does not survive a restart
   either) before anything else writes to the page.
6. Merge finished branches as usual; a branch whose agent died mid-item is still safe to merge
   if its last commit was green, which the rules guarantee.

### Single task
Same steps, one worktree, one implementer, and still a reviewer. `setup.sh` and `cleanup.sh`
take one task name as happily as six. The only things that fall away are partitioning and
merge ordering; the mailbox, the acknowledged statuses, the evidence rules, and the review are
the reason to run the skill at all, and they do not depend on how many agents there are.

## Runtime verification notes (project-specific advice for `{{RUNTIME_NOTES}}`)

- Behavior bugs need a runtime check, not just a unit test. Ask for the concrete evidence
  that would convince a skeptic: a capture, a logged value before and after, a measured
  number.
- Anything driven by real time (timers, schedulers, animations, simulations) needs real time
  to pass. An agent that fast-forwards steps in a loop to speed up a check sees everything
  freeze and reports a false failure. Checks need real delays between steps.
- An exclusive device, or any measurement taken on shared hardware, is checked at the start of
  every run, not assumed: is it awake and unlocked, is its power state the one the measurement
  needs (for example running on its own power or on external power), and what is its thermal
  state. Record these with the result. Gate a measurement on a cool-down: wait until the
  temperature is below a stated threshold before starting, and say which threshold in the
  report. Runs compared with each other should be interleaved, so drift in temperature or
  background load affects them equally.
- A long run sets its own maximum hold when it takes the lock, sized to the run with some
  margin, rather than relying on the default.
- Tell the agent how to start the app on its port and which existing preview config, if any,
  it must not reuse.
- Browser automation tools (the Claude browser pane) are one shared pane for every agent in
  the session. The template already tells agents to create their own tab and never touch
  another's; an agent that ignores this navigates a peer's tab mid-measurement.
  With five or six agents the pane still thrashes (tabs swapped, captures timing out), so
  plan rounds so that at most two or three tasks need the browser, give pure-module tasks
  "no runtime evidence needed", and tell agents to pass their tab id on every single call.
- A background browser tab suspends animation callbacks and timers, so a page's update loop
  never runs there even though its setup did. The template tells agents to front the tab or
  drive the update function themselves with real time deltas. Expect the report to say which.
- Pure data tasks (encoding a table, writing config) need no runtime evidence; say so
  explicitly in the brief so the agent does not start a server for nothing.
- Stubbed environments lie. Anything with stubbed services (a display-less environment, a mocked
  API, a fake device, an in-memory database) returns data that looks real. Example: a stub
  returned an empty buffer, correct output looked broken, and an agent raised a false alarm.
  Any claim about what a user would see or get needs evidence from the
  real environment that the agent opens and describes, flaws included. Say in the notes how
  to launch the real thing on this project, and name it under `EXCLUSIVE` if only one agent
  can use it at a time.
- Ask for the runner's final line, not a count. Reports have said "15 new tests" when the
  runner said 13; the pasted line settles it.

## Windows and cloud-sync hazards (put the relevant ones in `{{RUNTIME_NOTES}}`)

- `git stash` is shared across every worktree of a repository, so an agent's stash surfaces in
  another agent's checkout, and a cloud-synced folder has blocked `git stash -u` outright. Agents park work
  as a WIP commit instead; the templates say so.
- Python on Windows writes CRLF and the system code page by default and once broke a script
  file with cp1252 characters. Files are written as UTF-8 with LF; the templates say so.
- Long paths break temp worktrees and clones. Keep the scratchpad path short if you can, and
  tell agents to keep their scratch folder names short.
- Cloud-sync clients and indexers hold folders open. `cleanup.sh` expects this and retries; if a
  worktree will not go, leave it and run cleanup again later rather than fighting it.
- Stopping a Git Bash shell (a Monitor expiring, a background task stopped) kills only that
  shell; the rest of its pipeline and its children keep running. `watch.sh`, `lock_run.sh`
  and `sweep.sh` are built around this (rule 15); anything else long-running needs `timeout`
  or a tree kill (`taskkill //F //T //PID <windows pid>`).
- The controller never `cd`s into a worktree or staging folder; a `cd` moved the session's
  working directory and every later relative path with it. `git -C <path>` and absolute paths
  throughout.

## Checklist

- [ ] Tasks partitioned (trivial for one task); every file in exactly one allowlist; shared docs assigned to one agent or routed to notes files; exclusive resources named
- [ ] Model policy asked once and recorded (`models.conf` or project notes); each dispatch names its tier and why, in the message and the brief's `MODEL` line
- [ ] Page keeper asked about at setup; if running: events sent to it, resumed after every pause, picks read from the page each user turn, no hand edits
- [ ] `setup.sh` run once (reset) at round start; `--add` for any task added mid-round; worktrees exist; setup command succeeded in each
- [ ] Monitor started on `timeout 1790 bash .agent-mail/watch.sh`; `sweep.sh --kill` before each re-arm; re-armed without `--replay` when it expires
- [ ] `sweep.sh --kill` after each `DONE ALL` report and each paused agent's report, and at wrap-up; each report's cleanup proof lists the process trees the agent stopped
- [ ] Every implementer (one or many) dispatched in one message with a brief, a unique port, its own scratch folder, the tier's model for that type of work (explicit effort for Opus)
- [ ] Every STATUS PLAN answered with ACK or a correction; every PROGRESS read, not answered; every QUESTION answered, or its default accepted consciously; every PICK shown to the user; every mandatory instruction sent as a numbered reply; every STATUS/DONE checked for the NOTEs it lists
- [ ] Scope moves told to both agents with the file ownership; user feedback relayed as a verbatim `(USER)` quote
- [ ] Integration green after each fast-forward, or the red test quarantined with reason and owner
- [ ] Each DONE merged into staging; suite, typecheck, and build green there before integration fast-forwards
- [ ] Reviewer dispatched on the batch, told not to trust reports; never skipped
- [ ] Spot checks: a strong agent re-verified 1-2 claims per cheaper-tier agent's non-code output this batch, and checked early on long jobs; a miss widened the check and updated the brief or handbook
- [ ] FAIL items dispatched as fixes, re-merged, re-tested
- [ ] Decision log updated: a `Decided:` line for each user decision, a `Done:` line for each dispatch and merge, all in plain words
- [ ] The user told, as each happened, whether each agent and each spot check or review succeeded, partly succeeded, or failed, with how it was verified and what happens next
- [ ] Follow-ups decided before cleanup; worktrees (including `_staging`) and branches removed; skipped edits and notes folded in; user told what is open

## Files in this skill

- `templates/dispatch-brief.md` (what the controller sends), `templates/implementer.md`,
  `templates/reviewer.md`, `templates/merge-agent.md`, `templates/page-keeper.md` (what the agent reads from disk)
- `mailbox/PROTOCOL.md`, `mailbox/watch.sh`, `mailbox/lock_run.sh`, `mailbox/proc_lib.sh`,
  `mailbox/sweep.sh`, `mailbox/gitignore-lines.txt` (copied into the repo by `setup.sh`;
  at run time the mailbox also holds `.watch-state`, `.watch.pid`, `locks/`, and the
  project's own `resources.conf`, `hooks/`, and optional `sweep.keep`, which never come from
  the skill)
- `scripts/setup.sh` (reset, `--add`, `--force`, `--update-helpers`), `scripts/cleanup.sh`
  (`--scratch`)
- `tests/lock_run_test.sh` and `tests/sweep_test.sh` (run each with `bash tests/<name>.sh`;
  about 2-3 minutes each on Windows, where each process start is slow)
