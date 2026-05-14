# `.claude/valk-config.md` — per-project config format

A per-repo file that opts the repo into host-specific behavior for Valkyrie skills and AFK runs. **Without this file, Valkyrie behaves exactly as it does today** — no PRs opened, no host-specific test runners invoked. Adding the file is a deliberate opt-in.

## Location

`<repo-root>/.claude/valk-config.md`

One file per repo. Not searched up the directory tree. Not read from `$HOME/.claude/`.

## Format

YAML frontmatter inside a markdown file. Body of the file is free-form notes (treated as documentation, never parsed).

```markdown
---
# Required-shape keys (any can be omitted; omitting = "default behavior")
pr_skill: to-azure-pr           # name of a skill the agent should invoke at end of /tdd
test_skill: run-truetest        # name of a skill to invoke as the GREEN signal in /tdd
work_item_id_field: work_item_id  # frontmatter key on issue files (default: work_item_id)

# Host-specific config blocks (only relevant if the matching pr_skill needs them)
azure_devops:
  org: https://dev.azure.com/<your-org>
  project: <your-project>
  repository: <repo-name>       # if absent, parsed from `git remote get-url origin`
  target_branch: master         # default if absent
---

# Optional free-form notes

Anything below the frontmatter is documentation for humans. Valkyrie ignores it.
```

## Key reference

### Top-level keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `pr_skill` | string \| `none` | absent = `none` | Skill name to invoke at end of TDD. If `none` or absent, no PR step. If set but skill not installed in env, `/tdd` and AFK STOP with a clear error. |
| `test_skill` | string \| `none` | absent = `none` | Skill name to invoke as the GREEN signal. If absent, `/tdd` falls back to inferring a test runner from context (current behavior). |
| `work_item_id_field` | string | `work_item_id` | Frontmatter key on issue files holding the tracker ID. Allows teams using different conventions to map cleanly. |

### `azure_devops:` block

Only consulted when `pr_skill: to-azure-pr`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `org` | URL | _no default_ — must be set | Azure DevOps organization URL, e.g. `https://dev.azure.com/<your-org>` |
| `project` | string | _no default_ — must be set | Project name inside the org |
| `repository` | string | parsed from `git remote get-url origin` | Repo name or ID inside the project |
| `target_branch` | string | `master` | Default PR target branch |

## Behavior matrix

| File present? | `pr_skill` value | `/tdd` final step | AFK "done" check |
|---|---|---|---|
| No | n/a | Mark issue done locally (current) | Frontmatter field flip (current) |
| Yes | absent or `none` | Mark issue done locally (current) | Frontmatter field flip (current) |
| Yes | `to-azure-pr` (and skill is installed) | Push branch, open Azure DevOps PR, wait for build, mark done only if green | Done = PR open + CI green; otherwise stuck |
| Yes | `to-azure-pr` (skill NOT installed) | STOP with error | STOP iteration with error |
| Yes | `to-gh-pr` or other unknown | Look for that skill in env; same fallback logic | Same |

## Enforcement of "no impact on repos that haven't opted in"

The default code path through `/tdd` and AFK is the current behavior. The config-gated path only runs when:

1. `.claude/valk-config.md` exists in the repo, AND
2. its frontmatter declares a `pr_skill` (or `test_skill`) value that is not `none`

A user pulling Valkyrie and running it in a repo without this file gets identical behavior to today. Adding this file is the explicit opt-in.

## Examples

### Minimal Azure DevOps opt-in

```markdown
---
pr_skill: to-azure-pr
test_skill: run-truetest
azure_devops:
  org: https://dev.azure.com/<your-org>
  project: <your-project>
  repository: <your-repo>
---
```

Defaults that still apply (when keys are omitted): `target_branch: master`, `work_item_id_field: work_item_id`.

### Override target branch and work item field

```markdown
---
pr_skill: to-azure-pr
test_skill: run-truetest
work_item_id_field: tracker_id
azure_devops:
  org: https://dev.azure.com/<your-org>
  project: <your-project>
  repository: <your-repo>
  target_branch: develop
---
```

Issue files in this repo are expected to have `tracker_id: 12345` in frontmatter; PRs target `develop`.

### Hypothetical GitHub variant (not built yet)

```markdown
---
pr_skill: to-gh-pr
test_skill: pytest
---
```

The user installs a `/to-gh-pr` skill from somewhere; Valkyrie invokes it the same way it invokes `/to-azure-pr`. No host coupling in Valkyrie core.

## Parsing

Consumers (the `/tdd` skill via agent reasoning, the `afk` script via shell) read this file by extracting the YAML frontmatter between the first pair of `---` lines and parsing it. A small awk/python helper lives in `scripts/read-valk-config.sh` to keep extraction consistent.

## Versioning

This format is at `v0`. Breaking changes will introduce a `version: 1` top-level key and a migration path. Until then, additive changes only.
