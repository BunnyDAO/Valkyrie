---
id: 0006
title: Fill real Anthropic and OpenAI prices in rates.json
type: HITL
status: open
blocked_by: [0003]
parent: docs/prd/afk-budget-caps.md
---

## What to build

Replace the placeholder values in `scripts/rates.json` (shipped in 0003) with current published API prices, sourced from the official pricing pages. **HITL** because the source-of-truth is human-maintained pricing pages that change over time and require human verification — auto-merging current LLM-extracted rates would be risky.

- For each Anthropic model in the file (claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5), look up current prices on `anthropic.com/pricing` (or the equivalent docs page) and fill in:
  - `input_per_mtok` (USD per 1M input tokens)
  - `output_per_mtok` (USD per 1M output tokens)
  - `cache_write_5m_per_mtok` (5-minute cache writes)
  - `cache_write_1h_per_mtok` (1-hour cache writes)
  - `cache_read_per_mtok` (cache reads)
- For each OpenAI / codex model, look up current prices on `openai.com/api/pricing` and fill:
  - `input_per_mtok`
  - `output_per_mtok`
- The PR description must include the URL of the pricing page consulted and the date of the lookup.
- Add a comment at the top of `scripts/rates.json` (or in a sibling `rates-source.md`) that notes the last-verified date and pricing-page URLs, so future updates know what they're regenerating from.

This issue is HITL because:
- LLM-extracted prices from web content are not reliably accurate.
- A wrong rate silently underestimates spend, defeating the cap.
- The official pages occasionally restructure; a human eye catches structural changes.

## Acceptance criteria

- [ ] All five Anthropic rate fields are filled in for claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5 with values that match the current published Anthropic pricing page.
- [ ] All two OpenAI rate fields are filled in for at least one codex model.
- [ ] No field still contains the placeholder value from 0003.
- [ ] A note (top of file, comment block, or sibling file) records: the URL consulted, the date of the lookup, and the human reviewer's identifier.
- [ ] After `git pull && ./install.sh`, `~/.claude/valkyrie/rates.json` reflects the new prices.
- [ ] A smoke test: `afk --debug-cost test/fixtures/known-opus-100k-tokens.log` produces a USD value within 1% of the expected published-rate calculation.

## Blocked by

- 0003 (the file, schema, and install wiring must exist first)
