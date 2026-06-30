# to-intent

Authors a per-task intent brief — the crystal-clear why, scope, success criteria, and trade-offs for one change — saved to `docs/intent/<slug>.md`. The strictest no-inference skill in Valkyrie: every gap is a question, never an assumption.

## When to use

Type `/to-intent` or say "pin down the intent", "write the intent brief", "lock what we're building before we start." Also offered by the DESIGN Intent Lock at the end of the why/domain exchange. Run it before `/valk` when you want a durable, reviewable why document rather than just the inline intent lock.

## Example

```
/to-intent add export to CSV for the orders table
```

## Output

A brief at `docs/intent/<slug>.md` covering outcome, why, domain, in scope, out of scope, success criteria, and trade-offs. The user must confirm the outcome and why in their own words before the file is written — a bare "yes" is rejected. The brief feeds `/grill-with-docs` as the design premise and constrains the PRD's problem statement and solution sections.
