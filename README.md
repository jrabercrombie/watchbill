# watchbill

*Who stands which watch, and who they report to.*

The deckhands do the work, the officer of the watch runs the deck: parallel Claude subagents
in git worktrees, coordinated through a file mailbox with live status, corrections, claims,
and evidence-checked merges.

Watchbill is a [Claude Code skill](https://code.claude.com/docs/en/skills) for running an
implementation plan as a coordinated crew instead of a single expensive session. The lead
session, on your best model, does only coordination: it partitions the plan, dispatches
implementers on Sonnet and trivial edits on Haiku, and never reads a transcript. Each agent
works in its own git worktree, branch, and port, with a file allowlist. Coordination runs
through an append-only file mailbox: every agent posts a status before each step and the lead
answers it with an acknowledgement or a one-line correction, so a misread brief is caught
before the first commit rather than after an hour of work. Issues go out the moment they are
found, questions carry a default and a timeout, claims on shared files are notices rather than
locks, and nothing ever waits on another agent. When a report lands, the lead merges, runs the
full suite on the merged tree, and sends a read-only reviewer who is told not to trust the
reports. Implementers must show evidence: tests and typecheck clean per commit, runtime proof
for behaviour changes, deviations and issues sections, a clean tree.

In practice the lead's share of the spend is a few coordination turns; the implementation
tokens land on models that cost a fraction as much. No agent-teams feature required, just a
shell, a repo, and a session that stays alive to watch a file.

## Why it exists

Built on two real projects after agents overwrote each other's edits in one working folder,
sat on findings for half an hour, killed each other's dev servers, reported "fixed" on unit
tests while the live behaviour was still broken, and burned premium-model budget on work a
cheaper model does fine. Every rule in the skill is there because one of those happened.

## Install

```bash
git clone https://github.com/jrabercrombie/watchbill.git ~/.claude/skills/watchbill
```

The repo root is the skill, so that is the whole install. Claude Code picks it up on the next
session. Requires git and a bash (Git Bash on Windows is fine).

## Use

In a repo with a plan or bug list that has two or more tasks touching different files, say
something like *"run docs/plans/batch-1.md with watchbill"* or just *"use watchbill"*. The
lead session then:

1. Partitions the plan into tasks with disjoint file allowlists.
2. Runs `scripts/setup.sh --setup "npm install" task-a task-b task-c`, which adds the
   gitignore lines, resets `.agent-mail/`, and creates `.worktrees/<task>` on branch `<task>`.
3. Starts a persistent monitor on `.agent-mail/watch.sh`.
4. Dispatches every implementer in one message from `templates/implementer.md`.
5. Answers each `STATUS` with `ACK` or a correction, answers `QUESTION`s, notes `ISSUE`s.
6. Merges each branch when its report lands and runs the suite on the merged tree.
7. Sends a reviewer from `templates/reviewer.md`, dispatches fixes, merges again.
8. Runs `scripts/cleanup.sh` to remove worktrees and merged branches, and folds in notes.

`SKILL.md` has the full controller loop and checklist. `mailbox/PROTOCOL.md` is the contract
agents follow; it is copied into the repo so agents can read it.

## The mailbox in one table

Every line starts with `[<task>]`. Each agent owns exactly one append-only file,
`.agent-mail/inbox-<task>.log`; the lead writes only `.agent-mail/<task>.reply`.

| Line | Meaning |
|------|---------|
| `STATUS #n:` | What the agent is about to do and how. The lead replies `#n: ACK` or `#n: <correction>`. |
| `ISSUE:` | Any finding, in or out of scope, the moment it is noticed. |
| `QUESTION #n:` | A blocking question with a `default:`; the agent polls for a reply for 8 minutes, then proceeds on the default. |
| `TO <task>:` | A message for another agent, written in the sender's own inbox. |
| `CLAIM:` | A file outside the allowlist or a port. A notice, never a lock. |
| `DONE:` / `DONE ALL:` | A commit landed / every item is finished and the report is coming. |

Nothing waits on another agent, so there is no deadlock.

## Files

```
SKILL.md                  workflow, rules, controller loop, checklist
templates/implementer.md  prompt for an implementing agent (Sonnet or Haiku)
templates/reviewer.md     prompt for the read-only batch reviewer
templates/merge-agent.md  prompt for resolving a large merge conflict in the task's worktree
mailbox/PROTOCOL.md       the mailbox contract, copied into each repo
mailbox/watch.sh          the lead's 2-second poller that surfaces signal lines
mailbox/gitignore-lines.txt
scripts/setup.sh          gitignore, mailbox reset, worktrees, per-worktree setup command
scripts/cleanup.sh        remove worktrees, delete merged branches, prune stale records
```

## Pitfalls it already knows about

- Agents in one working folder stomp each other; half-finished edits hot-reload into a running app.
- An agent stops another agent's dev server because it looks stray.
- "Fixed" on unit tests alone while the live behaviour is still broken.
- Findings held until the final report.
- Agents quietly investigating or undoing other agents' work instead of reporting it.
- Engines with wall-clock tweens stall when frames are stepped in a tight loop.
- A shared spec edited by several agents; give it to one, or route notes through files the lead folds in.
- The Claude browser pane is one shared pane; each agent needs its own tab, and a hidden tab suspends `requestAnimationFrame`.
- A correction can land between an agent's last checkpoint and its commit; the lead checks the next status and repeats it as a numbered reply if needed.
- Worktree folders under OneDrive can stay locked after agents finish; cleanup retries and falls back.

## License

MIT. See [LICENSE](LICENSE).
