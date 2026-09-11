---
name: watchbill
description: Run an implementation plan or bug list as parallel subagents, each in its own git worktree, coordinated through a file mailbox (.agent-mail/) instead of agent-teams messaging. Use this whenever a plan, spec, or bug list contains two or more tasks that could be worked at the same time in a git repo and the user wants them dispatched to subagents, reviewed, and merged; also whenever the user mentions worktrees, parallel agents, dispatching implementers, watchbill, an agent mailbox, .agent-mail, batches of tasks, or wants cheaper models doing the implementation while this session only coordinates. Even if the user just says "run the plan" or "fix these bugs" and there are several independent items, use this skill.
---

# Watchbill: parallel agents with a file mailbox

This session is the **controller**. It dispatches subagents, watches a mailbox, answers
questions, merges, and decides. It does not implement, and it never reads agent transcripts,
only final reports and mailbox lines. Every rule below exists because of something that went
wrong on a real project; the reason is given so you can apply the rule sensibly rather than
mechanically.

## When to use

- Two or more tasks that can be partitioned by file so they do not need each other's edits.
- A git repo, and a session that stays alive to run a persistent watcher.
- Not for a single task, or a set of tasks that all touch the same few files (serialize those
  or give them to one agent).

## Roles and models

| Role | Model | Where it works | Writes |
|------|-------|----------------|--------|
| Controller (you) | the session's model | main checkout on the integration branch | only `.agent-mail/<task>.reply` files, merges, worktree cleanup |
| Implementer | `sonnet` (`haiku` for trivial edits such as doc nits, renames, config) | `.worktrees/<task>` on branch `<task>` | its allowlist, its own `inbox-<task>.log` |
| Reviewer | `sonnet` | main checkout, read-only | its own `inbox-review-<batch>.log` only |
| Merge agent | `sonnet` | `.worktrees/<task>` | conflict resolution on branch `<task>` |

Dispatch with the Agent tool: `subagent_type: "general-purpose"`, `model: "sonnet"` or
`"haiku"`, `run_in_background: true`, and the **entire filled template as the prompt**. Do not
paraphrase the template; the mailbox and evidence paragraphs are the contract.

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
   while the live behavior was still broken.
5. **Findings go out immediately, and so does intent.** An `ISSUE` line the moment something is
   noticed, not in the final report thirty minutes later. A `STATUS` line before each item
   saying how it will be done, which the controller acknowledges or corrects. A wrong reading
   of the brief is cheapest to fix before the first commit.
6. **Other people's work is expected.** Agents will see commits, files, servers, and hooks they
   did not create. Report what you see, ask if it changes your plan, never revert or work
   around it without a message from the controller or the owning agent. No message means
   proceed as briefed.
7. **Nothing waits on another agent.** Claims are notices, not locks. Questions carry a default
   assumption and a time limit. So there is no deadlock.
8. **Independent reviewer.** After each batch a read-only reviewer is told not to trust the
   implementer reports and to verify by reading code and running commands.
9. **One writer per shared document.** A spec that several agents would edit goes to one
   agent per batch, or each agent writes `docs/notes/<task>.md` and the controller folds the
   notes in afterwards.

## Controller loop

### 1. Partition
Group the plan's items into tasks with disjoint file sets. For each task decide the allowlist,
port, model, and items. If two tasks need the same file, either combine them into one task or
give the file to one task and let the other log an `ISSUE` describing the change it wanted.

### 2. Set up the repo
`<skill-dir>` below is this skill's base directory, reported when the skill was loaded (a
plugin install puts it under `~/.claude/plugins/`, a clone under `~/.claude/skills/`).
```bash
bash "<skill-dir>/scripts/setup.sh" --setup "npm install" task-a task-b task-c
```
This appends the gitignore lines if missing, creates `.agent-mail/` with `PROTOCOL.md` and
`watch.sh`, **clears old inbox and reply files** (so the watcher does not replay history),
creates `.worktrees/<task>` on branch `<task>` from the current branch, and runs the optional
setup command in each worktree. It prints the absolute mailbox path and each worktree path for
the templates. Run it from the repo root on the integration branch.

### 3. Start the watcher
```
Monitor({ command: "bash .agent-mail/watch.sh", description: "agent mailbox", persistent: true, timeout_ms: 3600000 })
```
Each `ISSUE`, `QUESTION`, `DONE`, `TO`, and `CLAIM` line arrives as a notification.

### 4. Dispatch
Fill `templates/implementer.md` per task and launch all Agent calls **in one message** so they
run concurrently. Placeholders: `{{TASK}}`, `{{BRANCH}}`, `{{WORKTREE}}`, `{{MAIL}}`,
`{{INTEGRATION}}`, `{{PORT}}`, `{{ALLOWLIST}}`, `{{OTHER_TASKS}}`, `{{ITEMS}}`, `{{TEST_CMD}}`,
`{{TYPECHECK_CMD}}`, `{{BUILD_CMD}}`, `{{DEV_CMD}}`, `{{RUNTIME_NOTES}}`. Put project-specific
verification advice (see "Runtime verification notes") into `{{RUNTIME_NOTES}}`, and paste the
task's items from the plan verbatim into `{{ITEMS}}` together with the evidence the item must
produce. Name the read-only context files (shared types, the spec, the plan) next to the
allowlist so the agent knows what to read without claiming it.

### 5. Handle mailbox lines

| Line | Controller action |
|------|-------------------|
| `STATUS #n` | Read it against the brief and the design. If the approach is right, append `#n: ACK`. If not, append `#n: <what to do instead>`, concrete enough to act on. Every status gets one of the two; an agent that hears nothing assumes it is on track. |
| `ISSUE` | Read it. If it needs a decision now, write a reply. Otherwise note it for the review or the post-merge list. |
| `QUESTION #n` | Decide, then append `#n: <answer>` to `.agent-mail/<task>.reply`. The agent proceeds on its default after 8 minutes, so answer promptly or accept the default. |
| `TO <other>` | Nothing, unless the target has already finished or is not running; then relay by reply file to whoever needs it. |
| `CLAIM` | Check for a conflicting claim from another agent. If there is one, reply to the later claimant to skip and log an ISSUE. |
| `DONE` | Progress only (one per item). Nothing to do. |
| `DONE ALL` | The final report is about to arrive. Merge (step 6) when the agent's completion notification lands, not before: the report is what you check for evidence. |

Reply file (the only file the controller writes). Numbered lines answer a status or question
with that number; `NOTE:` lines are unsolicited instructions. Agents read the file before each
item, before each commit, after each runtime check, and before the report, and apply any
correction before their next commit:
```bash
printf '#1: ACK\n' >> .agent-mail/task-a.reply
printf '#2: no, keep the bounds in src/types.ts; formation already reads them from there\n' >> .agent-mail/task-a.reply
printf 'NOTE: formation now owns src/types.ts; do not claim it\n' >> .agent-mail/task-b.reply
```

Answering statuses is the controller's main job while agents run. Each one is a chance to
catch a misread brief before it costs an hour, so read the status, not just the prefix. Keep
replies to one line; an agent that needs more than that needs a new brief, not a longer reply.
A `NOTE:` can land between an agent's last checkpoint and its commit, so check the next
`DONE` or `STATUS` for evidence the correction took effect; if it did not, repeat it as a
numbered reply to that status, which the agent cannot miss.

### 6. Merge on DONE
Run in the main checkout:
```bash
git merge --no-ff task-a -m "merge: task-a"
```
then the test, typecheck, and build commands on the merged tree. Small conflicts: resolve
yourself. Large ones: `git merge --abort`, dispatch `templates/merge-agent.md` for that task,
merge again on its `DONE`. Keep the worktree until the review is done; fix agents reuse it.

### 7. Review the batch
When every task in the batch is merged and the merged tree is green, dispatch
`templates/reviewer.md` (model `sonnet`, read-only, own port). It reports per item PASS/FAIL
with `file:line` and a concrete fix for each FAIL.

### 8. Fix, re-merge, clean up
Dispatch fixes to the original task's worktree (same implementer template, items = the FAIL
list for that task, branch already exists). Merge on `DONE`, run the suite again. Then:
```bash
bash "<skill-dir>/scripts/cleanup.sh" task-a task-b task-c
```
which removes each worktree and deletes each fully-merged branch (it refuses unmerged ones).
On Windows, worktree folders can stay locked for a while after agents
finish; the script retries and falls back to a plain delete, and stale `.git/worktrees/<task>`
record folders that survive are harmless once `git worktree list` shows only the main
checkout. Delete them later by hand if they bother you.

### 9. Fold in and report
Apply any ISSUE-listed edits that were skipped because of claims, fold `docs/notes/<task>.md`
into the shared doc, and tell the user what merged, what the reviewer found, and what is still
open.

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
- A background browser tab suspends `requestAnimationFrame`, so an engine's update loop never
  runs there even though scene creation did. The template tells agents to front the tab or
  drive the update function themselves with real time deltas. Expect the report to say which.
- Pure data tasks (encoding a table, writing config) need no runtime evidence; say so
  explicitly in the brief so the agent does not start a server for nothing.

## Checklist

- [ ] Tasks partitioned; every file in exactly one allowlist; shared docs assigned to one agent or routed to notes files
- [ ] `setup.sh` run; old inboxes cleared; worktrees exist; setup command succeeded in each
- [ ] Monitor started on `watch.sh`, persistent
- [ ] All implementers dispatched in one message with full templates, unique ports, cheap models
- [ ] Every STATUS answered with ACK or a correction; every QUESTION answered, or its default accepted consciously
- [ ] Each DONE merged; suite, typecheck, and build run on the merged tree
- [ ] Reviewer dispatched on the batch, told not to trust reports
- [ ] FAIL items dispatched as fixes, re-merged, re-tested
- [ ] Worktrees and branches removed; skipped edits and notes folded in; user told what is open

## Files in this skill

- `templates/implementer.md`, `templates/reviewer.md`, `templates/merge-agent.md`
- `mailbox/PROTOCOL.md`, `mailbox/watch.sh`, `mailbox/gitignore-lines.txt` (copied into the repo by `setup.sh`)
- `scripts/setup.sh`, `scripts/cleanup.sh`
