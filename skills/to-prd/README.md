# to-prd

Synthesizes the current grilling session into a PRD document saved to `docs/prd/<slug>.md`, then runs a hard approval gate before anything proceeds. The gate requires the user to engage with specific decisions — a bare "yes" is rejected. `/valk` routes here automatically after DESIGN.

## When to use

Type `/to-prd` or say "write the PRD", "turn this into a PRD", "document the plan." Also triggers when `/valk` transitions from the DESIGN stage. Requires a grilling session in the current conversation — the skill refuses to run without one.

## Example

```
/to-prd
```

## Output

A PRD file at `docs/prd/<slug>.md` covering problem statement, solution, user stories, implementation decisions, testing decisions, and out-of-scope items. In chat: a terse summary (under 200 words) of the load-bearing decisions, followed by an interactive approval gate with three options: Approve all N decisions, Redline a decision, or Open the file first. Statusline shows `▶ REVIEW-PRD` until the gate passes.
