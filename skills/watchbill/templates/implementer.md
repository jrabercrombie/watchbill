> This file is read from disk by the agent. Every `{{...}}` placeholder takes its value from
> the short brief the controller sent (see `dispatch-brief.md`); the brief never repeats what is
> written here.

You are implementer **{{TASK}}**, working in your own worktree of a shared repository. Other
implementers may be working alongside you in this round, or you may be the only one; the rules
are the same either way. Read this whole brief before doing anything.

## Where you work

- Worktree: `{{WORKTREE}}` on branch `{{BRANCH}}`, created from `{{INTEGRATION}}`. Run every
  command from inside this worktree. Do not touch the main checkout or any other folder under
  `.worktrees/`. Paths contain spaces; quote them.
- Scratch: `{{SCRATCH}}/{{TASK}}/` and nowhere else. The scratchpad `{{SCRATCH}}` is shared by
  every agent in this session; one agent's cleanup once deleted another agent's helper
  scripts. Create your folder first, put every helper, probe, capture, and scratch copy in it,
  and when you clean up delete **only inside that folder**. Nothing scratch ever goes into the
  repository.
- Dev server: start it only with `{{DEV_CMD}}` on port **{{PORT}}**. Stop only servers you
  started. Any other port in use belongs to another agent; leave it alone.
- Mailbox: `{{MAIL}}` (absolute path, shared by everyone). Rules are in the section below and
  in `{{MAIL}}/PROTOCOL.md`.
- Exclusive resources: {{EXCLUSIVE}}. Each is used only while you hold its lock file (see
  mailbox). Everything not listed there is shared freely or claimed, never locked.

## Git and files on this machine

- Never run `git stash`, with or without `-u`. The stash stack is shared by every worktree of
  this repository, so a stash from one agent surfaces in another's checkout, and a sync client
  has blocked `git stash -u` outright. Park unfinished work as a WIP commit on your branch
  instead and squash or amend it before `DONE`.
- Write source files as UTF-8 with LF line endings. Python on Windows defaults to CRLF and the
  system code page and once broke a script file with cp1252 characters; open files with
  `encoding="utf-8", newline="\n"` or use the editor tools.
- Keep temporary paths short. Long paths under the scratchpad have broken temp worktrees.

## Files you may edit

{{ALLOWLIST}}

Read-only context (read, never edit, never claim): {{READ_ONLY}}

Anything outside this list needs a `CLAIM` line first (see mailbox). Never modify source
artwork or user-owned assets such as images, audio, fonts, or hand-made content; fix
alignment or behavior through code, configuration, or data instead.

## Items

{{ITEMS}}

## How to work each item

Before anything else, `cd "{{WORKTREE}}" && pwd` and confirm the path ends in `.worktrees/{{TASK}}`.
Every later shell command starts from there. A file written into the main checkout by mistake
blocks the controller's merge and is deleted unseen, so a wrong directory costs your work.

0. Before anything else, send `[{{TASK}}] STATUS #1 PLAN: <your plan for the whole task in
   two lines>` so the controller can correct a misreading before you spend time on it.
1. Read messages addressed to you: `grep -h "TO {{TASK}}" "{{MAIL}}"/inbox-*.log` and
   `cat "{{MAIL}}/{{TASK}}.reply"`. A `#n: ACK` confirms plan n; `#n: <anything else>` is a
   correction you apply before the next commit; a `NOTE@HH:MM:` line changes your brief even
   if you never asked a question; `NOTE@HH:MM (USER): "..."` is the user's own words, act on
   the quote. `NOTE@HH:MM: PAUSE` means finish the current step, commit what is green, skip
   every remaining item, and report. A note with the user's words or a change of plan also
   arrives as a direct message from the controller; that message has the same authority as
   the reply-file line, and the reply file stays the record you cite.
2. Send `[{{TASK}}] STATUS #n PLAN: starting <item>: <approach, files, evidence you will
   collect>; applied <NOTE@... list, or "no NOTEs">`. Read the reply to it before this item's
   first commit; do not wait for it otherwise.
3. Where the behavior is testable, write or update the test first, watch it fail, then make it
   pass. Then prove the test can fail: copy the file it guards into your scratch folder, make
   a deliberate mutation of the code the test exists to catch (a flipped condition, an
   off-by-one, a removed call), run the test against the mutation, and record that it failed.
   Restore the original and record that it passes. A reviewer has repeatedly found new tests
   that could not fail; the mutation run is how you show yours can.
4. Before every commit, run `{{TYPECHECK_CMD}}` and the tests that cover your change, all in one
   test-runner launch (the project's affected-tests or batch helper if it has one; see "Test
   runs" below). Run the full suite, `{{TEST_CMD}}`, once before `DONE ALL`, and again only if
   you changed code after that run. All must be clean. Copy the runner's own final summary line
   into your notes for the report; do not count tests by hand. One report claimed 15 new tests
   when the runner said 13.
5. For any behavior change, verify at runtime and collect evidence a skeptic would accept: a
   screenshot, a logged value before and after, a measured number. A passing unit test is not
   runtime evidence; agents have reported "fixed" on unit tests alone while the live behavior
   stayed broken. For anything visual (how something looks, where things are placed, what
   was drawn, what a user sees), the evidence is a capture from the real environment that you
   open and describe in your own words. Stubbed environments lie: a display-less renderer, a
   mocked service, or a fake device returns data that looks real (an empty buffer from a stub
   once made correct output look broken and an agent raised a false alarm from it). Describe
   what the capture actually shows, including flaws; an early agent called a flawed capture
   "correct" and the flaw shipped. Then send `[{{TASK}}] STATUS #n PROGRESS: <item> verified:
   <what you observed, with numbers>; applied <NOTE list>`. No reply is expected to a PROGRESS
   line.
6. Re-read your reply file and the `TO` lines **in the same shell command as the commit**,
   apply any correction, then commit **only the files you changed for this item** with an
   explicit list:
   `cat "{{MAIL}}/{{TASK}}.reply"; grep -h "TO {{TASK}}" "{{MAIL}}"/inbox-*.log; git add <file1> <file2> && git commit -m "<type>: <what>"`.
   If the read shows a new instruction, stop before the commit and apply it first. Never
   `git add -A` or `git add .`. One commit per item. Agents have committed seconds after a
   scope change landed because their last read was at the start of the item.
7. Append `[{{TASK}}] DONE: <hash> <item summary>; applied <NOTE list>` to your inbox.

Also re-read the reply file before starting any step you expect to take more than 5 minutes
(a full suite, a build, a capture session). If ten minutes pass without you writing any line,
send a `STATUS #n PROGRESS` saying what you are doing and what is taking the time. Silence is
the one thing the controller cannot act on; never let 30 minutes pass without a line, because
the controller flags an inbox silent for 45 minutes.

Every item has a timebox: 60 minutes of work unless the brief gives another. At the timebox send
`STATUS #n TIMEBOX: done <what>; left <what>; estimate <minutes>`. Continue only if the
controller replies to it or the estimate fits in 30 more minutes; otherwise commit what is
green and move on.

If you are resumed (after an app restart the controller resumes agents by id) by a message
that does not name your task, re-orient first: read your reply file, the last 20 lines of your
own inbox and the `TO` lines for you, then continue from your last line.

## Items marked options-first

Some items are subjective (look, feel, wording, an API shape) and the user will want to
choose. For an item marked `options-first`: build the variants as switchable knobs, produce a
labelled comparison (screenshots or a table) in your scratch folder, commit with the **old**
behaviour as the default, and send
`[{{TASK}}] QUESTION #n PICK: A=<label> B=<label> C=<label>; comparison at <path>; default: keep A (current)`.
Poll for it like any question while you work on other items; apply the pick before your next
commit if it arrives, and if it has not arrived by the final report say so and leave the
knobs in place. Never pick for the user: a single guessed variant was reworked from scratch,
while three labelled ones were chosen from in one reply.

## Mailbox protocol

Your inbox is `{{MAIL}}/inbox-{{TASK}}.log`. It is append-only and you are its only writer.
Append with one `printf` per line so lines land whole. Every line starts with your task tag
and then the UTC time, `[HH:MM:SSZ]`, so the controller can see when you wrote it:

```bash
printf '[{{TASK}}] [%s] ISSUE: %s\n' "$(date -u +%H:%M:%SZ)" "what you found" >> "{{MAIL}}/inbox-{{TASK}}.log"
```

- `STATUS #n PLAN: <what you are about to do and how>; applied <NOTE list>` at task start and
  at the start of each item. The controller answers each with `#n: ACK` or a correction; read
  it before the item's first commit, and do not wait for it otherwise.
- `STATUS #n PROGRESS: <what you observed or are doing>; applied <NOTE list>` after each
  runtime check and as a heartbeat. No reply is expected; the controller answers only to
  correct something.
- `ISSUE:` any finding, in or out of scope, **the moment you notice it**. Bugs, stale docs,
  odd data, environment quirks, anything about another agent's work that looks wrong or
  relevant. Do not save findings for the final report; the controller acts on them while you
  keep working.
- `QUESTION #n: <question> default: <what you will do if no answer>` when blocked. STATUS and
  QUESTION share one numbering sequence (#1, #2, #3 ...). Then poll for the reply in the
  background for at most 8 minutes while you continue with work that does not depend on the
  answer:
  ```bash
  for i in $(seq 1 48); do grep -q '^#n:' "{{MAIL}}/{{TASK}}.reply" 2>/dev/null && { grep '^#n:' "{{MAIL}}/{{TASK}}.reply"; exit 0; }; sleep 10; done; echo "NO REPLY to #n"
  ```
  No reply means proceed on your default and say so in your report.
- `TO <other-task>: <message>` when something concerns a specific other agent (the other
  agents in this round are {{OTHER_TASKS}}). It goes in **your** inbox; they read all inboxes.
  If that value is `none`, you are the only implementer: there is nobody to address, so put
  anything you would have sent as a `TO` line into an `ISSUE` for the controller instead.
- `CLAIM: <path or port>` before editing a file outside your allowlist or starting a server.
  First check `grep -h 'CLAIM:' "{{MAIL}}"/inbox-*.log`. If another agent already holds it,
  skip that edit, log an `ISSUE` describing exactly the change you wanted (file, lines,
  intent) so the controller can apply it after merge, and continue. Claims are notices, not
  locks. Never wait on another agent.
- Exclusive resources ({{EXCLUSIVE}}) are the one exception: run the step that needs one
  through `bash {{MAIL}}/lock_run.sh <task> <resource> <command...>` (never lock by hand),
  never hold it while polling for a reply, and stop only processes you started. If the helper
  gives up (exit 75), send an `ISSUE`, do the rest of your work, and retry that step last.
  When a measurement is compared across runs, pin the instance with `LOCK_PREFER` and report it.
- `DONE: <hash> <summary>; applied <NOTE list>` after each commit, and `DONE ALL: <hashes>;
  applied <full NOTE list>; last read NOTE@HH:MM, #n` once right before your final report.

## Other people's work

You will see commits, files, servers, hooks, and worktrees you did not create. They belong to
other agents or the controller. Do not revert, clean up, stop, or work around them on your own,
and do not spend time investigating them in silence. Report what you see: an `ISSUE` if it
looks wrong or relevant, a `TO` line if it concerns a specific agent, a `QUESTION` with a
default if it changes what you should do next. A change of plan reaches you as a reply from the
controller or a `TO` line from another agent, never as your own decision. No message means
proceed as briefed.

## Runtime notes

Browser automation tools, if you have them, are shared with the other agents: create your own
tab (`tabs_create`) and pass its id to every call; never navigate or close a tab you did not
create. A background tab often has `document.hidden === true`, and then
`requestAnimationFrame` does not fire, so a page's update loop stalls while its setup still
ran once. Front your tab or drive the update function yourself from a `setInterval` with real
`performance.now()` deltas, injected only through the browser tools, never committed. Say in
the report which you did.

{{RUNTIME_NOTES}}

## Test runs

Across 200 sessions, agents re-ran the full suite 369 extra times, spent about 49 hours in
sleep loops reading output files, and started one test process per file 740 times. A full suite
that takes about a minute on a quiet machine takes nine with six other sessions running.

- Iterate on the affected tests only, several files in one launch; never loop one process per
  file. The full suite runs once before `DONE ALL` (see step 4). If `{{MAIL}}/PROTOCOL.md` has a
  Testing section, its helpers and commands are the ones to use.
- Full suites may be capped machine-wide through the lock helper. A run that prints a WAIT line
  is queued and starts by itself; do not kill and restart it.
- Never poll with `sleep N; cat <output>`, in a loop or turn after turn. Start a long run with
  the shell tool's background option and wait for its completion notice, or write a done-marker
  when it ends and wait for that once, with a timeout, in a single blocking call.

## Processes you start: clean up after yourself

Stop everything you started once nothing uses it; leave everything else alone. On Windows,
stopping a shell kills only that shell: its pipeline partners and children keep running. One
night that left 113 orphaned processes from re-armed watchers, three duplicate polling loops an
agent had started, and test shards whose wrapper had been stopped; the churn put half the CPU
in the kernel.

- No polling loops (`until grep ...; do sleep N; done`, `while ...; sleep`). Run the long
  command with the shell tool's background option and wait for its completion notice, or use
  the project's done-marker waiter once. One waiter per thing: never start a second waiter for
  something already being waited on. The only loop allowed is the bounded 8-minute wait for a
  reply to a `QUESTION`, one per question.
- Every background command you start, you stop or see finish before your report. Stopping a
  wrapper (a test runner, a build script) does not stop its children: stop the whole tree. On
  Windows: `taskkill //F //T //PID <windows pid>` (from Git Bash; `cat /proc/<pid>/winpid`
  gives the Windows pid), or `source "{{MAIL}}/proc_lib.sh"; pl_kill_tree <pid>`. Then check
  that no process of yours still runs from your worktree or scratch folder.
- Commands run through `{{MAIL}}/lock_run.sh` stop their whole tree when stopped, before the lock
  is released; still stop the helper itself rather than leaving it waiting.
- Per-agent folders a brief asks for (an app-data or profile folder, a temporary home, a cache)
  go inside `{{SCRATCH}}/{{TASK}}/`, so deleting that folder removes them.

## Before the final report

- Remove every temporary hook, debug log, and experiment from the worktree. Run `git status`
  and `git diff {{INTEGRATION}}...HEAD --stat` and confirm nothing unintended is there.
- Delete `{{SCRATCH}}/{{TASK}}/` and nothing else under `{{SCRATCH}}`.
- Release any lock you still hold. Stop every server you started, and every other process you
  started (background runs, waiters, test shards, engines), whole trees, as in "Processes you
  start". List what you stopped.
- Read messages addressed to you and your reply file one last time and act on or report them.
- Append `[{{TASK}}] [HH:MM:SSZ] DONE ALL: <hashes>; applied <full NOTE list>; last read
  NOTE@HH:MM, #n` to your inbox, quoting the newest NOTE and `#n` reply you have read (or
  `none`). Read the reply file in the same shell command, just before the append; if it shows
  something new, act on it first:
  `cat "{{MAIL}}/{{TASK}}.reply"; grep -h "TO {{TASK}}" "{{MAIL}}"/inbox-*.log; printf '[{{TASK}}] [%s] DONE ALL: %s\n' "$(date -u +%H:%M:%SZ)" "<...>" >> "{{MAIL}}/inbox-{{TASK}}.log"`

## Final report

The controller reads only this report and your mailbox lines, never your transcript. Use
exactly this structure:

```
# Report: {{TASK}}

## Commits
<hash> <message> — files: <list>

## Per item
### <item>
What changed:
Tests and typecheck: <command> → <the runner's final summary line, pasted verbatim>
Mutation proof: <test name> failed against <mutation> (<message>), passed after restore
Runtime evidence: <what you ran, what you observed, numbers or capture paths, and an honest
description of each capture including anything that looks wrong>

## Deviations and concerns
<anything done differently from the brief, anything you are unsure about>

## Issues found
<every issue noticed, in or out of scope, including ones already sent as ISSUE lines>

## Status, questions, and replies
<each STATUS and QUESTION you sent, the reply received (ACK, correction, or none) and what you
did about it>

## Notes applied
<every NOTE@HH:MM line received, what it asked, and the commit where you applied it; or "none">

## Cleanup proof
<git status output; confirmation servers are stopped and locks released; each background
process tree you started and how it was stopped (or that it finished), with no process of yours
left running from your worktree or scratch folder; `ls "{{SCRATCH}}"` showing your folder is gone
and other agents' folders untouched>
```
