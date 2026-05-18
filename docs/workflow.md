# Valkyrie workflow — end-to-end

Two diagrams. The **interactive workflow** describes a single slice from prompt to PR. The **AFK wrapper** is the autonomous loop that runs the same machinery N times with budget caps. They share the entire stage pipeline — AFK just adds a driver around it.

## Interactive workflow (single slice, end-to-end)

```
┌─────────────────────────────────────────────────────────────────────┐
│ TRIGGER                                                              │
│  user: "let's build X" / "/valk" / "implement Y"                     │
│  → UserPromptSubmit hook (valk-guard.sh) injects VALK ENFORCEMENT    │
│  → agent invokes /valk skill                                         │
└─────────────────────────┬───────────────────────────────────────────┘
                          │  stage.py set design
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STAGE 1 ── DESIGN  ▶ DESIGN                                          │
│  /grill-with-docs                                                    │
│   • interview user one Q at a time                                   │
│   • cross-reference codebase + CONTEXT.md + docs/adr/                │
│   • update CONTEXT.md inline as terms resolve                        │
│   • write ADRs sparingly (hard-to-reverse + surprising)              │
│   • exit: "ready to turn this into a PRD?"                           │
└─────────────────────────┬───────────────────────────────────────────┘
                          │  stage.py set prd
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STAGE 2 ── PRD  ▶ PRD                                                │
│  /to-prd                                                             │
│   • synthesize grilling into a PRD (no re-interview)                 │
│   • problem · solution · user stories · impl · out-of-scope          │
│   • output → docs/prd/<slug>.md                                      │
└─────────────────────────┬───────────────────────────────────────────┘
                          │  stage.py set prd-review  (to-prd does this)
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ GATE ── PRD-REVIEW  ▶ REVIEW-PRD                                     │
│  (inside /to-prd — workflow STOPS here)                              │
│   • decisions reproduced INLINE (Impl Decisions, Out of Scope,       │
│     key User Stories) — no need to open the file                     │
│   • user must confirm a specific decision in their own words         │
│     OR redline one                                                   │
│   • bare "yes"/"lgtm"/silence → REJECTED, gate re-asks               │
│   • redline → revise PRD, re-run gate                                │
│   • only substantive approval advances                               │
└─────────────────────────┬───────────────────────────────────────────┘
                          │  stage.py set issues  (ONLY after approval)
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STAGE 3 ── ISSUES  ▶ ISSUES                                          │
│  /to-issues                                                          │
│   • break PRD into vertical slices (NOT horizontal layers)           │
│   • each slice: id, title, status, blocked_by, AC, work_item_id      │
│   • output → issues/000N-*.md (numbered in dependency order)         │
└─────────────────────────┬───────────────────────────────────────────┘
                          │  stage.py set tdd
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STAGE 4 ── TDD  ▶ TDD                                                │
│  /tdd                                                                │
│   1. Pick next unblocked issue → status: in_progress                 │
│   2. Plan: behaviors to test, interface shape                        │
│   3. RED:   write 1 test → fails for the right reason                │
│   4. GREEN: minimal code to pass                                     │
│        └─► reads valk-config.md `test_skill`:                        │
│             • set    → invoke /run-truetest (or whatever)            │
│             • unset  → infer test runner from context                │
│   5. Loop 3+4 for each behavior, one at a time                       │
│   6. REFACTOR (only while GREEN)                                     │
│   7. Commit on slice branch                                          │
└─────────────────────────┬───────────────────────────────────────────┘
                          │  read valk-config.md `pr_skill`
                ┌─────────┴────────────┐
                │                      │
        pr_skill unset           pr_skill: to-azure-pr
        (default)                (opt-in via .claude/valk-config.md)
                │                      │
                ▼                      ▼
        ┌──────────────┐   ┌──────────────────────────────────────────┐
        │  mark issue  │   │  /to-azure-pr                            │
        │  status:done │   │   1. git push -u origin <branch>         │
        │  (current)   │   │   2. az repos pr create                  │
        │              │   │       --source-branch <branch>           │
        │  DONE. Bye.  │   │       --target-branch master             │
        └──────────────┘   │       --work-items <work_item_id>        │
                           │       --description <issue body + AC>    │
                           │   3. Poll az pipelines runs list every   │
                           │      30s (cap: 30 min)                   │
                           │   4. Return JSON:                        │
                           │      { pr_id, pr_url, ci_status,         │
                           │        ready_for_review }                │
                           └──────────────────┬───────────────────────┘
                                              │
                                  ┌───────────┴─────────────┐
                                  │                         │
                          CI succeeded               CI failed/canceled/
                                                    timeout
                                  │                         │
                                  ▼                         ▼
                       ┌──────────────────────┐   ┌──────────────────────┐
                       │ status: done         │   │ status: open         │
                       │ pr_url: <url>        │   │ stuck_reason: <ci>   │
                       │                      │   │                      │
                       │ HUMAN REVIEWS PR     │   │ HUMAN INVESTIGATES   │
                       └──────────────────────┘   └──────────────────────┘
```

## AFK wrapper (autonomous N slices)

The interactive flow runs once per user-driven slice. AFK wraps it in a loop that picks unblocked issues, spawns a fresh CLI session per slice, and applies budget caps.

```
afk N --max-hours H --max-cost-usd USD --cli claude|codex
   │
   ▼
┌────────────────────────────────────────────────────────────────┐
│ PRE-FLIGHT GATES (fail loud, refuse to start)                   │
│   ✓ issues/ exists                                              │
│   ✓ docs/prd/*.md exists       (override: --allow-no-prd)       │
│   ✓ working tree clean         (override: --allow-dirty)        │
│   ✓ path not dangerous         (override: --i-know-this...)     │
│   ✓ user confirms queue        (override: --no-confirm)         │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│ READ .claude/valk-config.md → PR_SKILL                          │
│   set    → done = PR open + CI green                            │
│   unset  → done = frontmatter field flip (current behavior)     │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         ▼
┌──────────────────── ITERATION LOOP ────────────────────────────┐
│                                                                 │
│   CHECK CAPS:  iter < N AND elapsed < H AND cost < USD          │
│        │  any cap hit → print_summary, exit                     │
│        ▼                                                        │
│   PICK next_issue:  status==open AND blocked_by all done        │
│        │  none unblocked → exit "no more issues"                │
│        ▼                                                        │
│   stage.py set afk     (statusline: ▶ AFK)                      │
│        │                                                        │
│        ▼                                                        │
│   SPAWN claude --print --dangerously-skip-permissions           │
│         (or codex exec --full-auto)                             │
│   PROMPT │ "you are in afk; next issue is <path>;               │
│          │  run /valk → /tdd → exit cleanly"                    │
│        │                                                        │
│        ▼                                                        │
│   AGENT runs the full interactive flow above (in practice       │
│   DESIGN/PRD/ISSUES happened upstream; AFK iters are TDD-only)  │
│        │                                                        │
│        ▼                                                        │
│   CLI EXITS                                                     │
│        │                                                        │
│        ▼                                                        │
│   PARSE log → cost-helper.py (reported $ or estimated)         │
│              → append CSV row (cost_source, pr_url)             │
│        │                                                        │
│        ▼                                                        │
│   DONE-CHECK (gated by PR_SKILL):                               │
│    PR_SKILL unset:                                              │
│      • status=done       → success → next iter                  │
│      • status≠done       → mark stuck                           │
│    PR_SKILL set:                                                │
│      • status=done + pr_url present → success → next iter       │
│      • status=done + pr_url absent  → FORCE stuck               │
│                                       ("agent skipped PR")      │
│      • status≠done                   → mark stuck               │
│        │                                                        │
│        └──────────────────► back to CHECK CAPS                  │
└─────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│ SUMMARY                                                         │
│   iterations done / N                                           │
│   elapsed / H                                                   │
│   spend $X / USD                                                │
│   issues done / stuck counts                                    │
│   logs: .claude/valk/afk-logs/                                  │
│   cost CSV: .claude/valk/afk-cost-history.csv                   │
└────────────────────────────────────────────────────────────────┘
```

## Parallel flows — multiple terminals on one project

Running several Valkyrie flows at once on one project is **supported — via
one git worktree per flow, not by sharing one checkout.**

**Why a shared checkout can't be made safe by code.** Two flows in the same
working tree share one index, one `HEAD`, one set of files. One flow's `git
add`→`git commit` window gets scooped by another's broad commit; a
half-written file reddens the other's test run; the stage marker is
clobbered. No amount of Valkyrie code removes that residue — same-file races
and shared red runs are *irreducible* without isolation. The cure is to stop
sharing the tree. (Rationale recorded in
[`docs/adr/0001-isolation-not-locking.md`](./adr/0001-isolation-not-locking.md).)

### The supported parallel lifecycle

```
create     valk-worktree <name>     # ../<repo>-<name> on branch valk/<name>
                                     # runs optional .valk-worktree-setup
work       cd ../<repo>-<name>      # this terminal is now isolated
                                     # run /valk … /tdd here as normal
integrate  merge or PR  valk/<name> → main branch   (MANUAL — see below)
cleanup    valk-worktree --remove <name>            # drops the merged branch
```

- **One worktree per terminal/flow.** Each flow gets its own
  `valk/<name>` branch and its own checkout; concurrent flows can no longer
  corrupt each other.
- **Integrate-back is manual for now.** When a flow's slice is done, land
  its `valk/<name>` branch on the main branch yourself via merge or PR —
  the same review you'd do for any branch. Automating this (a `valk-land`
  companion: auto-rebase vs PR, CI gating, conflict policy) is a **separate,
  deliberately deferred PRD** — tracked as issue #0018, not built yet and
  not implied to exist. Until it is designed, this manual merge/PR path is
  the supported integrate-back.
- **Cleanup.** `valk-worktree --remove <name>` removes the worktree and
  drops the `valk/<name>` branch *only if it is merged* (an unmerged branch
  is kept so no work is lost).
- **The guard will remind you.** If you start working in the shared main
  checkout, the UserPromptSubmit guard appends one nudge pointing at
  `valk-worktree`. It goes **silent automatically** once you are inside a
  linked worktree — it never nags the isolated (intended) workflow.

The optional `.valk-worktree-setup` hook (deps install, free-port pick, …)
is per-repo and language-agnostic; full contract +
sample: [`valk-worktree-setup-format.md`](./valk-worktree-setup-format.md).
`valk-worktree` works fully without it (pure git is the cure).

## Config gates at a glance

| Gate | Where it reads | Behavior when set | Behavior when unset |
|---|---|---|---|
| `test_skill` | inside `/tdd` GREEN step | invoke that skill; GREEN = skill success | infer test runner from context |
| `pr_skill` (in `/tdd`) | end of `/tdd` after commit | invoke PR skill; done = ready_for_review | mark frontmatter `status: done` |
| `pr_skill` (in `afk`) | done-check after each iter | done iff `pr_url:` present in frontmatter | done iff `status: done` |
| `pr_skill` named but **not installed** | both `/tdd` and `afk` | STOP with explicit error | n/a |

Repos with **no** `.claude/valk-config.md` hit every "unset" path → exactly today's behavior, zero change.

Full config spec: [`valk-config-format.md`](./valk-config-format.md).

## Mermaid (for embedding in docs)

```mermaid
flowchart TD
    U[User: 'let's build X' / /valk] --> H[UserPromptSubmit hook<br/>valk-guard.sh]
    H -->|trivial| Bypass[Skip Valkyrie]
    H -->|build request| V[/valk orchestrator]

    V --> S1["▶ DESIGN<br/>/grill-with-docs"]
    S1 -.writes.-> Ctx[CONTEXT.md<br/>docs/adr/*]
    S1 --> S2["▶ PRD<br/>/to-prd"]
    S2 --> PRD[docs/prd/&lt;slug&gt;.md]
    PRD --> GATE{"▶ REVIEW-PRD<br/>decisions shown inline<br/>substantive approval?"}
    GATE -->|bare yes / silence| GATE
    GATE -->|redline| S2
    GATE -->|approves a specific decision| S3["▶ ISSUES<br/>/to-issues"]
    S3 --> Iss[issues/000N-*.md<br/>+ work_item_id<br/>+ blocked_by]
    Iss --> S4["▶ TDD<br/>/tdd"]

    S4 --> RGR[RED → GREEN → REFACTOR]
    RGR --> C1{valk-config.md<br/>test_skill?}
    C1 -->|set| TT[/run-truetest]
    C1 -->|unset| Local[infer runner]
    TT --> Commit[Commit on branch]
    Local --> Commit

    Commit --> C2{valk-config.md<br/>pr_skill?}
    C2 -->|unset| Local2[status: done<br/>frontmatter flip]
    C2 -->|to-azure-pr| AZ[/to-azure-pr]

    AZ --> Push[git push -u origin]
    Push --> Cre[az repos pr create<br/>--work-items WID]
    Cre --> Poll[Poll az pipelines runs list]
    Poll --> CI{result?}
    CI -->|succeeded| Ready[pr_url: written<br/>status: done]
    CI -->|failed/canceled/timeout| Stuck[status: stuck<br/>stuck_reason: ci]

    Ready --> Review[Human reviews PR]
    Stuck --> Fix[Human investigates]
    Local2 --> Next[Pick next unblocked]
    Review --> Next
```
