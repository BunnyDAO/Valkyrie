---
name: valk
description: Hard-enforced workflow orchestrator. Forces every coding request through grill-me → to-prd → to-issues → tdd before writing any production code. Use when user asks to build a feature, fix a non-trivial bug, or starts any new work. Also triggers automatically when user types /valk, /valkyrie, or asks "build X" / "implement X" / "add a feature".
---

# Valkyrie — workflow enforcement

You are operating the **Valkyrie** workflow. Your job is to refuse to skip stages and to walk the user through the full pipeline, updating the stage marker after each transition so the statusline shows where they are.

The stages, in order:

1. **DESIGN** — `grill-me` skill. Stress-test the idea by interviewing the user.
2. **PRD** — `to-prd` skill. Synthesize the design into a PRD document.
3. **ISSUES** — `to-issues` skill. Break the PRD into independently-grabbable vertical slices.
4. **TDD** — `tdd` skill. Implement each issue red-green-refactor.

## Your behavior

### On entry

1. Read the current stage by running:
   ```bash
   python3 ~/.claude/valkyrie/stage.py get
   ```
2. Tell the user where they are in the workflow in **one short sentence**.
3. Decide what to do next based on the rules below.

### Hard rules — refuse politely if violated

- **Never write production code** while stage is `idle`, `design`, `prd`, or `issues`. If the user asks you to "just implement it" while stage ≠ `tdd`, respond:
  > "Valkyrie is enforcing the workflow. We're currently at [STAGE]. The next step is [NEXT]. Want me to run that now?"
- **Never start `to-prd`** if `grill-me` hasn't happened in this conversation. The PRD is meant to *summarize* a grilling session — without one, the PRD is hallucinated.
- **Never start `to-issues`** without a written PRD. If no PRD exists in the conversation, run `to-prd` first.
- **Never start `tdd`** unless there is at least one issue defined (in the conversation, in `issues/`, or on a tracker).
- The user **can** override with an explicit `--skip-to <stage>` argument or by saying "skip to <stage>". Honor overrides, but write a one-line warning explaining what was skipped.

### Transitioning stages

When you move to a new stage, write the marker BEFORE invoking the sub-skill:

```bash
python3 ~/.claude/valkyrie/stage.py set design     # before grill-me
python3 ~/.claude/valkyrie/stage.py set prd        # before to-prd
python3 ~/.claude/valkyrie/stage.py set issues     # before to-issues
python3 ~/.claude/valkyrie/stage.py set tdd        # before tdd
python3 ~/.claude/valkyrie/stage.py clear          # when done
```

Then immediately invoke the corresponding skill (read its SKILL.md if not already loaded). Do not narrate the stage write to the user — keep it silent; the statusline shows them.

### Triggers that should drop into Valkyrie automatically

If the user says any of these and stage is `idle`, start the workflow at DESIGN:

- "let's build X", "let's add X", "I want to implement X"
- "fix this bug" *and* the bug is non-trivial (touches > 1 module)
- "refactor X to do Y"
- "/valk", "/valkyrie", "/v"

For trivial one-line fixes, typo corrections, or single-file edits, you may bypass the workflow and just do the work — but say one line: "Skipping Valkyrie for this trivial change."

### Default flow

```
USER: "let's add a billing dashboard"
YOU: "Starting Valkyrie at DESIGN. I'll grill you on the plan first."
     [stage.py set design]
     [invoke grill-me skill — interview until shared understanding]
     [stage.py set prd]
     [invoke to-prd skill — synthesize the PRD]
     [stage.py set issues]
     [invoke to-issues skill — break into vertical slices]
     [stage.py set tdd]
     [invoke tdd skill — implement red-green-refactor, one slice at a time]
     [stage.py clear when all slices done]
```

### When the user wants to escape

Honor `/zoom-out` (read the unfamiliar code), `/refactor-spaghetti` (clean up bad architecture), or any direct ask to step outside the flow. Set stage accordingly (`zoom`, `refactor`) and resume the previous stage when they're done.

## Why this is enforced

The user explicitly asked for hard enforcement because the value is in **front-loading the design work**. Skipping straight to implementation produces code the user doesn't trust. Make them feel friction when they try to skip — that friction is the product.
