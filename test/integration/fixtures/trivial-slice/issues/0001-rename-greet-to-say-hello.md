---
id: 0001
title: Rename greet to say_hello in src/greet.py
type: AFK
status: open
blocked_by: []
parent: docs/prd/greet-rename.md
---

## What to build

Rename the function `greet` in `src/greet.py` to `say_hello`. Update every internal caller in the same file. The CLI entry point under `if __name__ == "__main__":` must continue to print the expected output.

## Acceptance criteria

- [ ] `src/greet.py` defines `say_hello`, not `greet`
- [ ] `greet_loudly` calls `say_hello` (not `greet`)
- [ ] `python3 src/greet.py` prints `Hello, world!` and `HELLO, WORLD!`
- [ ] No remaining references to the old name `greet` exist in `src/greet.py`

## Blocked by

None — can start immediately
