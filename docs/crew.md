# Crew (HiveOp) — where `valk-config.md` comes from

Valkyrie's per-repo `.claude/valk-config.md` and the `crew-shim` it drives originate from
**HiveOp** ([crew.hiveop.io](https://crew.hiveop.io)) — a system for assembling and running
coordinated **multi-agent** Claude Code workflows. This page explains the relationship so the
config and the shim aren't unexplained machinery. Using HiveOp is entirely optional; Valkyrie
runs standalone without it.

## What HiveOp / crew is

A builder where you compose a **crew** of specialized agent *classes* (e.g. CTO, Reviewer,
Implementer, Tester) instead of hand-writing prompts. The discipline is **templates, not
copy-paste**: an agent fills the variable holes of a *reviewed* class but can't restructure
it — so a crew is reproducible and auditable as a single diff, which is how it resists the
prompt drift that plagues hand-rolled multi-agent setups. (Same "templates as the discipline
layer" idea as [sc-compose](https://github.com/BunnyDAO/sc-compose), used for the domain/intent
templates.)

Crews run on a **file blackboard**: agents communicate through scoped files rather than shared
memory, and each run is isolated to a `tasks/<id>/` directory, so multiple agents can work
concurrently without collisions.

## How a crew is produced and run

1. In the builder, use **`/crew-pick`** and **`/crew-author`** to assemble and customize the
   agent classes.
2. **Forge** generates a `.claude/` bundle — agent definitions, orchestrator logic, and a
   `PROTOCOL.md`.
3. Copy the bundle into any repository and invoke **`run-crew`**.

## How it binds to Valkyrie

The binding is the optional **`<repo>/.claude/valk-config.md`** file. When present and valid
(`version: 1` with a non-empty agent list for a stage), Valkyrie's **crew shim** dispatches
the bound crew agents for that stage *instead of* the stock sub-skill — while keeping
Valkyrie's stage order and the `prd-review` gate fully enforced. When absent (or not
`version: 1`, or an empty list), behavior is **byte-identical to vanilla Valkyrie**.

The shim is consulted deterministically, never by eyeballing the file:

```bash
crew-shim decide <repo-root> <STAGE>     # prints: vanilla   OR   crew <id> <id> …
```

This is the single, central place crews plug in — the four stage sub-skills
(`grill-with-docs`, `to-prd`, `to-issues`, `tdd`) are left untouched. See the "Crew shim"
section of `skills/valk/SKILL.md` for the runtime contract, and
[`valk-config-format.md`](./valk-config-format.md) for the file format.

> **Scope note.** This page documents the *relationship* and where the pieces come from. The
> HiveOp builder, the agent classes, Forge, and `run-crew` live in HiveOp itself, not in this
> repo. Valkyrie ships only the consumption side: the `valk-config.md` contract and the
> `crew-shim`.
