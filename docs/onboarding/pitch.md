---
marp: true
theme: default
paginate: true
---

<!-- _class: lead -->

![bg right:40% w:80%](./assets/helm.png)

# 🛡 Valkyrie

## The perfect agent is coming. We want it too.
## Until then — let's ship 5–10× today, and iterate.

<!--
TITLE-SLIDE IMAGE:
Drop a Valkyrie-helm image at:
  docs/onboarding/assets/helm.png
The `![bg right:40% w:80%]` directive puts it on the right 40% of the slide.

If no image is present, Marp silently omits it and you're left with the
🛡 emoji + headline — still readable.

Stock options to grab one (manual download):
  - unsplash.com   (search "viking helmet", "valkyrie")
  - pexels.com     (free, no attribution required)
  - flaticon.com   (icon-style — search "viking helm")
Or generate with any image model and save as helm.png.
-->


---

# We all want the same thing

- A workflow where AI ships features end-to-end. **That goal is right.**
- The fully autonomous version — true 24/7, zero-HITL — is still maturing.
- The opportunity: **5–10× today** with a standardized workflow, and we phase in more autonomy as the tooling catches up.
- **Same destination. Real deliverable now. Earlier wins.**

---

# The path forward, today

**Standardize on Valkyrie.**

- Design-first workflow, enforced by a hook.
- AFK loops with budget caps for heads-down work — without breaking our company's budget.
- **5–10x more efficient. Today. Same workflow for everyone.**

---

# How it works

```
DESIGN → PRD → ISSUES → TDD
 grill   read   slice    red-green
```

**Once per feature**, say **"let's build X"** (or type **`/valk`**). The orchestrator routes you through all four stages — every follow-up prompt continues the active stage. A statusline shows where you are.

**Try to skip → the AI refuses.**

*(No sub-commands to memorize — the orchestrator handles them.)*

---

# What's "the hook"?

- A tiny script Claude Code runs **before every prompt you submit**.
- It reads what you typed. If it looks like build/fix/refactor language → it injects a non-negotiable directive: *"use the Valkyrie workflow."*
- Claude can't ignore it. No flag to memorize, no opt-in checkbox.
- **Installed once. Applies to every project, every prompt, every engineer.**

---

# Stage 1 — DESIGN

- AI asks one question at a time, **with its recommended answer**.
- You react: accept, push back, or "you decide."
- ~15 minutes. Front-loads the thinking that wastes hours later.
- **Output:** shared understanding of what to build.

---

# Stage 2 — PRD

- AI synthesizes the grill into a Markdown PRD.
- Saved to `docs/prd/<slug>.md` — reviewable, shareable, version-controlled.
- ~5 minutes for you to read. Edit anything wrong.
- **Output:** the spec. Code review now references it instead of the diff.

---

# Stage 3 — ISSUES

- AI breaks the PRD into **vertical slices** — each cuts through every layer (schema → API → UI → tests).
- Marked **AFK** (autonomous-safe) or **HITL** (needs a human).
- Dependency-ordered so the loop knows what's unblocked.
- **Output:** `issues/0001-*.md`, `0002-*.md`, … each independently shippable.

---

# Stage 4 — TDD

- Red-green-refactor, one issue at a time.
- AI writes a test → you confirm → AI implements → repeat.
- Tests target public behavior, not implementation details.
- **Output:** working code, tested, traceable to the PRD.

---

# Optional: AFK mode

**Walk away after stages 1–3. The loop runs Stage 4 autonomously.**

- **Prerequisites:** PRD written, issues queued, working tree clean.
- Run from your shell:
  ```
  afk 10                                    # defaults: 4h, $50
  afk 50 --max-hours 12 --max-cost-usd 200  # overnight
  ```
- Spawns a fresh CLI session per issue. No context drift.
- **Pre-flight gates refuse to launch** unless prerequisites are met.

---

# Day 1

```bash
git clone https://github.com/BunnyDAO/Valkyrie.git ~/valkyrie && cd $_ && ./install.sh
```

Then in any project, just say:

> "Let's add a billing dashboard."

---

# The ask

**Make this the team standard.**

- Pilot: 3–5 volunteers, week 1.
- Default: PRD-backed PRs by quarter end.
- Measure cycle time. Adjust or scale.
