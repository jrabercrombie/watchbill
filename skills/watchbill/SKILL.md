---
name: watchbill
description: Dispatch implementation work to subagents in a git repo, each in its own git worktree, coordinated through a file mailbox (.agent-mail/) with an independent reviewer, no agent-teams messaging needed. Use this whenever any implementation task, one or many, is being handed to a subagent in a git repo: a single bug fix, one feature, or a whole plan; parallelism is a bonus when there are several tasks, not the reason to use it. Also use it whenever the user mentions worktrees, parallel agents, dispatching implementers, watchbill, an agent mailbox, .agent-mail, batches of tasks, or wants cheaper models doing the implementation while this session only coordinates. Even if the user just says "run the plan" or "fix these bugs" and there are several independent items, use this skill.
---

# Watchbill: implementers in worktrees with a file mailbox

This session is the **controller**. It dispatches subagents, watches a mailbox, answers
questions, merges, and decides. It does not implement, and it never reads agent transcripts,
only final reports and mailbox lines. Every rule below exists because of something that went
wrong on a real project; the reason is given so you can apply the rule sensibly rather than
mechanically. The skill is general-purpose: nothing in the rules is specific to games,
engines, or graphics; those appear only as examples, and each project decides its own
exclusive resources and runtime notes.

## Changelog

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
  mutation proof; Windows and OneDrive hazards; the controller never `cd`s.
- **2026-09-10 to 09-13**: first version. Worktrees, allowlists, file mailbox with acknowledged
  statuses, claims as notices, independent reviewer, templates read from disk, single-task use.

## When to use

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
| Implementer | chosen per task (below) | `.worktrees/<task>` on branch `<task>` | its allowlist, its own `inbox-<task>.log` |
| Reviewer | the strongest model you can afford: `opus`, or `fable` for a high-stakes batch | main checkout, read-only | its own `inbox-review-<batch>.log` only |
| Merge agent | same as the task's implementer | `.worktrees/<task>` | conflict resolution on branch `<task>` |

**State the model plan before dispatching, and offer the alternatives.** The brief carries a
model for each task. Decide it in the partition step using the suggestions below, then, in
the same message that presents the partition, tell the user which model each task gets and
why, and offer the other options with their cost implication: the cheaper plan (what it
risks), the stronger plan (what it costs). The user picks against their budget; a dispatch
that surprises them on either quality or spend is a failure of this step, not of the model.

- `opus` (Claude Opus 5.5) for judgment-heavy work: multi-file changes, anything subjective
  (look, feel, copy, API shape), a brief that cannot fully specify the answer. A stronger implementer
  finishes in fewer turns and fewer fix rounds, and one avoided fix round (an implementer
  dispatch plus a reviewer pass) pays for its price gap over Sonnet.
- `sonnet` for well-specified work: a single-file fix with a clear test, data encoding, config.
- `haiku` for trivial edits: doc nits, renames.
- Reviewer: the strongest model you can afford. Review is cheaper than implementation (one
  pass over a merged tree, no fix rounds) and a strong reviewer catches more. `opus` by
  default; `fable` (Claude Fable 5.1) when the batch is large or a miss would be expensive.
  Its independence comes from a fresh context and the "do not trust the reports" rule, not
  from being a different model than the implementer.
- Controller: this session's model. Coordination is the smallest share of the spend and a
  misjudgment there costs the most.
- Whatever the user chooses stands for the round, and a standing preference they state
  (for example, every agent on the strongest model) stands across rounds without re-asking.

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
3. **File allowlists.** Every prompt names the files the agent may edit. Anything else needs a
   `CLAIM` line first. Never modify source artwork or user-owned assets; fix alignment or
   behavior through code, config, or data.
4. **Evidence, not claims.** Tests and typecheck clean before every commit; a runtime check
   with described evidence for any behavior change (screenshots, logged values, measured
   numbers); a "Deviations and concerns" section; an "Issues found" section; proof that
   temporary hooks and scratch files are gone. Agents have said "fixed" on unit tests alone
   while the live behavior was still broken. Three refinements from later runs: test counts
   are the runner's final line pasted verbatim (a report said 15 new tests, the runner said
   13); every new test comes with a mutation proof, shown failing against a deliberate break
   of the code it guards (the reviewer kept finding tests that could not fail); and any claim
   about how something looks needs a windowed capture the agent opened and described
   honestly, because an environment with stubbed services (a headless renderer, a mocked API,
   a fake device) returns data that looks real and has produced both a false alarm and a
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
   real bugs the implementers reported as fine: a converter washing out colours, a test runner
   passing broken tests four ways, colliders you could walk through, a click firing on release.
9. **One writer per shared document.** A spec that several agents would edit goes to one
   agent per batch, or each agent writes `docs/notes/<task>.md` and the controller folds the
   notes in afterwards.
10. **One scratch folder per agent.** The session scratchpad is shared by every subagent, so
    each agent works only in `<scratchpad>/<task>/` and deletes only inside it. One agent's
    cleanup once deleted another's helper scripts mid-run. Reviewers never put probe files in
    the repository; a probe test dropped into the test folder hung the controller's suite run.
11. **Exclusive resources are locked, briefly.** Every project has things only one agent can
    use at a time (a render or capture window, a single test database, an emulator or device,
    a rate-limited API, a licensed tool, the shared browser pane). The controller identifies
    them when partitioning and lists them in the brief; the skill supplies one generic
    mechanism: agents take `.agent-mail/locks/<resource>` immediately before use and release
    immediately after, a lock older than 10 minutes is stale, and nobody holds one while
    waiting for anything else. Before this, agents sharing one window "waited 30 s and
    retried" into each other and produced garbage.
12. **Instructions must be seen before they matter.** Agents read the reply file in the same
    shell command as every commit and before any step longer than five minutes; every
    `STATUS` and `DONE` lists the `NOTE@HH:MM` lines applied; anything mandatory goes out as a
    numbered reply to the agent's latest status, never as a bare NOTE; `NOTE@HH:MM: PAUSE`
    means finish the step, commit green work, skip the rest, report. Agents have committed
    seconds after a scope change landed because their last read was at the start of the item.
13. **Merge through a staging branch.** Two branches that each passed alone once produced a
    failing integration branch when merged, and undoing the merge needed a `git reset --hard`
    the safety system refused. Merges land in a staging worktree, the suite runs there, and
    integration fast-forwards only when green.
14. **The controller never `cd`s.** A `cd` into a worktree moved the session's working
    directory and every later relative path with it. Use `git -C <path>` and absolute paths.

## Controller loop

### 1. Partition
Group the plan's items into tasks with disjoint file sets. With one task the partition is
trivial: one allowlist, one port, one model; still write them down, the brief needs them. For
each task decide the allowlist, port, model, and items. If two tasks need the same file, either
combine them into one task or give the file to one task and let the other log an `ISSUE`
describing the change it wanted. List every **exclusive resource** this project has by
name (a render or capture window, a test database, an emulator, a rate-limited API, a
licensed tool, the shared browser pane); agents lock those and only those. Mark subjective
items `options-first` so the agent builds labelled variants instead of guessing.

### 2. Set up the repo
`<skill-dir>` below is this skill's base directory, reported when the skill was loaded (a
plugin install puts it under `~/.claude/plugins/`, a clone under `~/.claude/skills/`).
```bash
bash "<skill-dir>/scripts/setup.sh" --setup "npm install" task-a task-b task-c
```
This appends the gitignore lines if missing, creates `.agent-mail/` with `PROTOCOL.md` and
`watch.sh`, **clears old inbox, reply, lock, and watcher-state files**, creates
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
the refusal when you know nothing is running.

### 3. Start the watcher
```
Monitor({ command: "bash .agent-mail/watch.sh", description: "agent mailbox", persistent: true, timeout_ms: 3600000 })
```
Each `ISSUE`, `QUESTION`, `DONE`, `TO`, and `CLAIM` line arrives as a notification. The
watcher saves its per-file offsets in `.agent-mail/.watch-state`, so when the Monitor expires
(every 30 minutes) and you re-arm it, it continues from where it stopped. It used to replay
the whole inbox on every restart, and each replay read as a flood of new events. Pass
`--replay` only when you want the history, such as when resuming after a session restart.

### 4. Dispatch
Do not paste the template into the prompt. The lead model's output is the most expensive
token in the system, and a full template per agent was the single largest line in a real
run's bill. Instead send each agent a short **brief**: the values that fill the template, plus
one instruction to read the template file itself. `templates/dispatch-brief.md` is the shape;
copy it, fill it, and launch all Agent calls **in one message** so they run concurrently.

The brief carries: `TASK`, `BRANCH`, `WORKTREE`, `MAIL`, `INTEGRATION`, `PORT`, `SCRATCH`
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
| `QUESTION #n PICK` | An options-first item is ready. Show the user the comparison and relay their choice as `#n: B`, quoting any reason verbatim. If it arrives after the agent's report, switch the knob yourself after merge. |
| `TO <other>` | Nothing, unless the target has already finished or is not running; then relay by reply file to whoever needs it. |
| `CLAIM` | Check for a conflicting claim from another agent. If there is one, reply to the later claimant to skip and log an ISSUE. |
| `DONE` | Progress only (one per item). Nothing to do. |
| `DONE ALL` | The final report is about to arrive. Merge (step 6) when the agent's completion notification lands, not before: the report is what you check for evidence. |

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
report. Use it when the plan changes under an agent or the budget is gone; it beats letting
the agent finish items you will throw away.

Answering statuses is the controller's main job while agents run. Each one is a chance to
catch a misread brief before it costs an hour, so read the status, not just the prefix. Keep
replies to one line; an agent that needs more than that needs a new brief, not a longer reply.
**Anything mandatory goes out as a numbered reply to the agent's latest `STATUS`, never as a
bare NOTE.** A NOTE can land between checkpoints and be missed; a numbered reply is read
against a status the agent is waiting to hear about. Then check the next `STATUS` or `DONE`:
each one ends with the NOTEs applied (`applied NOTE@14:02` or `no NOTEs`), so a missing entry
means the instruction did not land, and you repeat it as a numbered reply. Agents have
committed with the old scope because a NOTE arrived after their last read.

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
Merge on `DONE`, run the suite again. Do not clean up until the review is in and the follow-up
list for each task is decided: twice a worktree was removed and the same agent then needed
more work, which forced a new task name and fresh mailbox files. Follow-ups reuse the task
name. Then:
```bash
bash "<skill-dir>/scripts/cleanup.sh" task-a task-b task-c
```
which removes each worktree and deletes each fully-merged branch (it refuses unmerged ones).
Include `_staging` in the list. On Windows, worktree folders can stay locked for a while
after agents finish; the script retries quietly, falls back to a plain delete, and ends with
one summary line. Stale `.git/worktrees/<task>` records it names there are harmless once
`git worktree list` shows only the main checkout; delete them later by hand if they bother you.

### 9. Fold in and report
Apply any ISSUE-listed edits that were skipped because of claims, fold `docs/notes/<task>.md`
into the shared doc, and tell the user what merged, what the reviewer found, and what is still
open.

## Decision log

The controller keeps `docs/DECISIONS.md` on the integration branch (a project may name another
path; say so in the partition). It is the durable record of what the user decided and what was
done about it, so neither the user nor a resumed session has to rely on memory or transcripts.
Keep it minimal: one line per entry, newest last, under a date heading. Two kinds of line:

```
## 2026-03-14
- D: dark theme becomes the default; light stays selectable ("dark reads better")
- A: dispatched task-b (dark theme default)
- A: merged task-b 1a2b3c4, suite 212 green
```

`D:` is a user decision in a few words, with a short quote when the wording matters. `A:` is a
step the controller took: a dispatch, a merge (commit and test count), a revert, a pick applied.
Point at commits, files, and screenshots instead of repeating their content. Append a `D:` when
the user decides and an `A:` after each dispatch and merge, and commit the log with the merge
or on its own. Do not log agent-internal steps, statuses, or reviewer findings; the mailbox and
reports hold those.

## Resuming after a session restart

Background agents and the watcher do not survive a session restart, but their worktrees,
commits, and mailbox lines do. On resume:

0. Read `docs/DECISIONS.md` for what the user decided and what was last dispatched and merged.
1. `git worktree list` and `git log main..<task>` for each task: the branch shows what landed;
   the mailbox `DONE` lines say which items those commits were.
2. Check the worktree is clean and no stray servers hold ports (`netstat -ano | grep LISTENING`).
3. Restart the Monitor on `watch.sh --replay` to see the whole history once, read as history,
   not as new events. Without `--replay` it resumes from `.watch-state` and shows only what
   arrived after the previous watcher stopped.
4. A stopped agent cannot be messaged back to life. Dispatch a fresh one with the same brief
   plus a paragraph naming the commits already on the branch and the item to start from, and
   tell it to number its statuses after the last one in the inbox.
5. Merge finished branches as usual; a branch whose agent died mid-item is still safe to merge
   if its last commit was green, which the rules guarantee.

### Single task
Same steps, one worktree, one implementer, and still a reviewer. `setup.sh` and `cleanup.sh`
take one task name as happily as six. The only things that fall away are partitioning and
merge ordering; the mailbox, the acknowledged statuses, the evidence rules, and the review are
the reason to run the skill at all, and they do not depend on how many agents there are.

## Runtime verification notes (project-specific advice for `{{RUNTIME_NOTES}}`)

- Behavior bugs need a runtime check, not just a unit test. Ask for the concrete evidence
  that would convince a skeptic: a screenshot, a logged value before and after, a measured
  number.
- Game engines animate on real time. An agent that fast-forwards frames in a loop to speed up
  a check sees every animation freeze and reports a false failure. Checks need real delays
  between frames.
- Tell the agent how to start the app on its port and which existing preview config, if any,
  it must not reuse.
- Browser automation tools (the Claude browser pane) are one shared pane for every agent in
  the session. The template already tells agents to create their own tab and never touch
  another's; an agent that ignores this navigates a peer's tab mid-measurement.
  With five or six agents the pane still thrashes (tabs swapped, screenshots timing out), so
  plan rounds so that at most two or three tasks need the browser, give pure-module tasks
  "no runtime evidence needed", and tell agents to pass their tab id on every single call.
- A background browser tab suspends `requestAnimationFrame`, so an engine's update loop never
  runs there even though scene creation did. The template tells agents to front the tab or
  drive the update function themselves with real time deltas. Expect the report to say which.
- Pure data tasks (encoding a table, writing config) need no runtime evidence; say so
  explicitly in the brief so the agent does not start a server for nothing.
- Stubbed environments lie. Anything with stubbed services (a headless renderer, a mocked
  API, a fake device, an in-memory database) returns data that looks real. Example: a headless
  renderer returned an empty instance buffer, a correct scene looked broken, and an agent
  raised a false alarm. Any claim about what a user would see or get needs evidence from the
  real environment that the agent opens and describes, flaws included. Say in the notes how
  to launch the real thing on this project, and name it under `EXCLUSIVE` if only one agent
  can use it at a time.
- Ask for the runner's final line, not a count. Reports have said "15 new tests" when the
  runner said 13; the pasted line settles it.

## Windows and OneDrive hazards (put the relevant ones in `{{RUNTIME_NOTES}}`)

- `git stash` is shared across every worktree of a repository, so an agent's stash surfaces in
  another agent's checkout, and OneDrive has blocked `git stash -u` outright. Agents park work
  as a WIP commit instead; the templates say so.
- Python on Windows writes CRLF and the system code page by default and once broke a GDScript
  file with cp1252 characters. Files are written as UTF-8 with LF; the templates say so.
- Long paths break temp worktrees and clones. Keep the scratchpad path short if you can, and
  tell agents to keep their scratch folder names short.
- OneDrive and indexers hold folders open. `cleanup.sh` expects this and retries; if a
  worktree will not go, leave it and run cleanup again later rather than fighting it.
- The controller never `cd`s into a worktree or staging folder; a `cd` moved the session's
  working directory and every later relative path with it. `git -C <path>` and absolute paths
  throughout.

## Checklist

- [ ] Tasks partitioned (trivial for one task); every file in exactly one allowlist; shared docs assigned to one agent or routed to notes files; exclusive resources named
- [ ] Model plan stated per task with the cheaper and stronger alternatives and their cost; user's choice recorded in each brief
- [ ] `setup.sh` run once (reset) at round start; `--add` for any task added mid-round; worktrees exist; setup command succeeded in each
- [ ] Monitor started on `watch.sh`, persistent; re-armed without `--replay` when it expires
- [ ] Every implementer (one or many) dispatched in one message with a brief, a unique port, its own scratch folder, the model chosen for that task (explicit effort for Opus)
- [ ] Every STATUS PLAN answered with ACK or a correction; every PROGRESS read, not answered; every QUESTION answered, or its default accepted consciously; every PICK shown to the user; every mandatory instruction sent as a numbered reply; every STATUS/DONE checked for the NOTEs it lists
- [ ] Scope moves told to both agents with the file ownership; user feedback relayed as a verbatim `(USER)` quote
- [ ] Integration green after each fast-forward, or the red test quarantined with reason and owner
- [ ] Each DONE merged into staging; suite, typecheck, and build green there before integration fast-forwards
- [ ] Reviewer dispatched on the batch, told not to trust reports; never skipped
- [ ] FAIL items dispatched as fixes, re-merged, re-tested
- [ ] Decision log updated: a `D:` for each user decision, an `A:` for each dispatch and merge
- [ ] Follow-ups decided before cleanup; worktrees (including `_staging`) and branches removed; skipped edits and notes folded in; user told what is open

## Files in this skill

- `templates/dispatch-brief.md` (what the controller sends), `templates/implementer.md`,
  `templates/reviewer.md`, `templates/merge-agent.md` (what the agent reads from disk)
- `mailbox/PROTOCOL.md`, `mailbox/watch.sh`, `mailbox/gitignore-lines.txt` (copied into the repo by `setup.sh`;
  at run time the mailbox also holds `.watch-state` and `locks/`)
- `scripts/setup.sh` (reset, `--add`, `--force`), `scripts/cleanup.sh`
