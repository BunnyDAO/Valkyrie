# `test/` — afk shell test harness

Self-contained, network-free test suite for `scripts/afk`. Tests run real
`afk` against stubbed `claude`/`codex` binaries that emit deterministic
output. No frameworks — just bash.

## Run the suite

```bash
bash test/run-tests.sh                  # run all tests
bash test/run-tests.sh smoke            # filter: only test-*smoke*.sh
bash test/run-tests.sh max-hours csv    # filter: test names matching either
```

Exits 0 if all pass, non-zero with the count + names of failures.

## Add a new test

Drop a `test-<thing>.sh` file in this directory. The runner picks it up
automatically. Each test:

```bash
#!/usr/bin/env bash
set -u

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO_ROOT:-$(dirname "$TEST_DIR")}"
STUBS="$TEST_DIR/stubs"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/issues"
# ... copy fixtures, set up state ...

cd "$WORKDIR"
PATH="$STUBS:$PATH" "$REPO/scripts/afk" 2 >"$WORKDIR/run.out" 2>&1

# ... assert ...
```

Exit 0 = pass, anything else = fail.

## Stub binaries

`stubs/claude` and `stubs/codex` shadow the real CLIs when `$STUBS` is first on
`PATH`. They:

1. Read the prompt (claude: stdin; codex: last positional arg).
2. Pluck the issue path out of the prompt and mark its frontmatter
   `status: done` (skip with `STUB_NO_MARK=1`).
3. Emit canned stream-json (override with `STUB_FIXTURE=<file>`).
4. Exit `$STUB_EXIT_CODE` (default `0`).

Env knobs each test can twist:

| Env var          | Effect                                                            |
|------------------|-------------------------------------------------------------------|
| `STUB_FIXTURE`   | Emit this file's contents instead of the default canned output.   |
| `STUB_NO_MARK`   | Don't update the issue's frontmatter (simulates a stuck agent).   |
| `STUB_EXIT_CODE` | Exit with this code instead of 0 (simulates a CLI crash).         |

## Fixtures

`fixtures/<scenario>/` directories. Tests `cp` what they need into the
temp workdir; never run against fixtures in place.

## Why bash and not <X>

`afk` is bash. Tests stay in the same language so they can stub via
`PATH`-shadowing and assert on file system state without ceremony. No deps
beyond what `afk` itself needs (`bash`, `awk`, `grep`, `python3`).
