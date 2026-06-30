# zoom-out

Steps back from low-level code to produce a higher-level map of how a module fits into the system — its callers, collaborators, seams, and overall role. Read-only: no changes, no refactor proposals.

## When to use

Type `/zoom-out` or say "I'm lost in this code", "show me the bigger picture", "who calls this?", "how does X fit in the system." Also invokable from inside a Valkyrie flow when you need to re-orient before continuing. The previous stage is restored when this completes.

## Example

```
/zoom-out the payment processing module
```

## Output

A structured map in chat covering: relevant modules (one line each), every caller and what it passes, every collaborator and the contract, the seams (real vs. hypothetical), and one paragraph placing the module in the system. Ends with a single question: "Where do you want to focus next?" No file changes. Statusline shows `▶ zoom` for the duration, then reverts.
