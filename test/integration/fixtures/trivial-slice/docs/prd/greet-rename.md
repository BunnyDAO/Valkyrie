# Rename `greet` → `say_hello`

## Problem Statement

The function `greet` in `src/greet.py` reads ambiguously — "greet" could mean a notification, a handshake, a UI flow. The codebase is small enough that a rename to `say_hello` makes the intent explicit at every call site.

## Solution

Rename the function and every reference to it.

## User Stories

1. As a maintainer, I want the function name to describe what it returns (a greeting string), so I don't have to read the body to understand the call site.

## Implementation Decisions

- Rename `greet` to `say_hello` in `src/greet.py`
- Update every internal caller in `src/greet.py` (e.g., `greet_loudly` uses it)
- Update the `__main__` block

## Testing Decisions

- A single test verifies the new name produces the expected output string.
- No tests exist yet; the slice creates the first.

## Out of Scope

- Renaming `greet_loudly`
- Changing the return type
- Documentation other than the function itself
