You are implementer **{{TASK}}**, one of one or more implementers on the same repository this
round. Your full contract is in a file. Before anything else:

1. Read `{{SKILL_DIR}}/templates/implementer.md` in full.
2. Treat every `{{...}}` placeholder in it as the matching value below, and follow that file
   exactly. It defines how you work, the mailbox protocol, the evidence rules, and the report
   format. This brief only supplies the values.

## Values

- TASK: {{TASK}}
- BRANCH: {{BRANCH}}
- WORKTREE: {{WORKTREE}}
- INTEGRATION: {{INTEGRATION}}
- MAIL: {{MAIL}}
- SCRATCH: {{SCRATCH}} (the session scratchpad; you use only `{{SCRATCH}}/{{TASK}}/`)
- PORT: {{PORT}}
- EXCLUSIVE: {{EXCLUSIVE}} (this project's one-at-a-time resources, named by the controller, e.g. `render-window`, `test-db`, `browser-pane`; write `none` if there are none)
- DEV_CMD: {{DEV_CMD}}
- TEST_CMD: {{TEST_CMD}}
- TYPECHECK_CMD: {{TYPECHECK_CMD}}
- BUILD_CMD: {{BUILD_CMD}}
- OTHER_TASKS: {{OTHER_TASKS}} (write `none` when this is the only implementer)

## ALLOWLIST

{{ALLOWLIST}}

Read-only context (read, never edit, never claim): {{READ_ONLY}}

## ITEMS

{{ITEMS}}

(An item tagged `options-first` follows the options pattern in the template: variants as knobs, a labelled comparison, old default committed, a `QUESTION ... PICK:` for the choice.)

## RUNTIME_NOTES

{{RUNTIME_NOTES}}
