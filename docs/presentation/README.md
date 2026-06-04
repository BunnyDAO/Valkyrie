# Valkyrie — technical-team presentation

A visual-first deck explaining Valkyrie: what Matt Pocock's skills are, why they matter standalone, and what Valkyrie layers on top (the harness, gates, telemetry, optional docs, the AFK enhancements, the model-tier rule, the roadmap).

- **`valkyrie-overview.pptx`** — the deck. Open in PowerPoint, Keynote, or Google Slides.
- **`build_deck.py`** — the source of truth. Regenerate the `.pptx` from this Python script so edits live in git, not in a binary file.

## Re-generate

```bash
pip3 install --user python-pptx          # one-time
python3 docs/presentation/build_deck.py  # writes valkyrie-overview.pptx
```

## Deck shape (28 slides)

1. Title
2. The problem — raw Claude Code is structureless
3. Matt Pocock's `skills` repo — the foundation
4. DESIGN (grill-with-docs)
5. PRD (to-prd)
6. ISSUES (to-issues) — vertical slices + LLM-context optimization
7. TDD (tdd)
8. AFK (Ralph pattern)
9. **Block diagram — Matt Pocock stack alone**
10. Where Pocock alone breaks down
11. What Valkyrie adds (overview)
12. INTENT Lock — new gate before DESIGN
13. **Block diagram — INTENT + Pocock + Agent Creator + harness**
14. The harness (statusline + 3 hooks)
15. The mechanical TDD-gate wall
16. Concise UI: bullets + options vs prose
17. HITL gates — PRD-REVIEW · Manual checklist · Loop-back · Handoff routing
18. AFK enhancements
19. Model tier follows leverage, not code volume
20. Progressive-enhancement docs (intent / DOMAIN / PRODUCT-MAP / CONTEXT / ADR)
21. Where each doc is read — matrix
22. Loop-back + concurrent worktrees
23. Crew Shim — optional Agent Creator at TDD
24. Compounding effect
25. Takeaway
26. Roadmap (AZDO PR, auto-docs, org templates, profile system)
27. Other pieces worth knowing (zoom-out, refactor-spaghetti, telemetry, install fallback…)
28. Q & A

## Design notes

- Widescreen 16:9, dark theme matching the Valkyrie repo aesthetic.
- Three accent colours used consistently:
  - **Amber** — Matt Pocock layer
  - **Cyan** — Valkyrie harness / additions
  - **Emerald** — TDD-side enhancements + Agent Creator
  - **Violet** — INTENT (new gate)
- Block diagrams are real shapes (PowerPoint-editable), not embedded images.
- Each slide makes one point; bullets are short.
- Slide 9 and 13 are the two key block diagrams the script grows from Pocock alone to the full Valkyrie shape.
