#!/usr/bin/env python3
"""valk-issues — ready-work query + dependency-graph lint over issues/*.md.

A git-native, dependency-free take on beads' `bd ready` and graph validation,
for Valkyrie's local markdown issue tracker. Pure over the files in ./issues —
no database, no daemon, nothing to sync. It mirrors afk's resolution semantics
exactly, so `lint` catches precisely the graph faults afk would otherwise
mis-route on or silently treat as a permanent block.

Subcommands:
  valk-issues ready [--dir DIR] [--json]   list unblocked open issues + a status roll-up
  valk-issues lint  [--dir DIR] [--json]   validate the dependency graph; exit 2 on errors

afk runs `lint` at pre-flight and refuses to start on a broken graph
(override: VALK_SKIP_ISSUE_LINT=1).

Resolution semantics (kept identical to scripts/afk):
  - an issue's id is the `id:` frontmatter value; its file is named `<id>-<slug>.md`
  - a `blocked_by:` token T resolves by the filename glob `T-*.md` (first match wins
    in afk via `find -print -quit`) — so a token must match exactly one file
  - an issue is "ready" iff status==open and every blocked_by token resolves to a
    single issue whose status==done
"""

import argparse
import glob
import json
import os
import re
import sys

STATUSES = {"open", "in_progress", "done", "stuck", "obsolete"}


def parse_issue(path):
    """Parse one issue file's frontmatter. Returns a dict (with a 'problems'
    list for malformed fields) or None if there is no frontmatter block."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()

    lines = text.splitlines()
    # Frontmatter is the block between the first '---' and the next '---'.
    if not lines or lines[0].strip() != "---":
        return {"file": path, "base": os.path.basename(path), "id": "",
                "status": "", "blocked_by": [], "title": "",
                "problems": [("error", "no YAML frontmatter (missing leading '---')")]}
    fm = []
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        fm.append(ln)

    def first(key):
        pat = re.compile(r"^%s:(.*)$" % re.escape(key))
        for ln in fm:
            m = pat.match(ln)
            if m:
                return m.group(1).strip().strip("\"'").strip()
        return None

    problems = []
    iid = first("id") or ""
    status = (first("status") or "").strip()

    raw_blocked = first("blocked_by")
    blocked = []
    if raw_blocked:
        if "[" in raw_blocked and "]" not in raw_blocked:
            problems.append(("error", "multi-line blocked_by list is not supported by afk "
                             "(use the inline form: blocked_by: [a, b])"))
        cleaned = raw_blocked.strip("[]")
        for tok in re.split(r"[,\s]+", cleaned):
            tok = tok.strip().strip("\"'")
            if tok:
                blocked.append(tok)

    if not iid:
        problems.append(("error", "missing or empty `id:`"))
    if not status:
        problems.append(("error", "missing or empty `status:`"))
    elif status not in STATUSES:
        # A non-standard status (e.g. paused, todo) isn't a graph fault — afk
        # just won't pick it, which is usually the intent. Warn, don't block.
        problems.append(("warn", "non-standard status %r (afk only picks 'open'; "
                         "expected one of: %s)" % (status, ", ".join(sorted(STATUSES)))))

    return {"file": path, "base": os.path.basename(path), "id": iid,
            "status": status, "blocked_by": blocked,
            "title": first("title") or "", "problems": problems}


def load(issues_dir):
    paths = sorted(glob.glob(os.path.join(issues_dir, "*.md")))
    # CHANGES.md / README.md etc. carry no `id:` — parse_issue flags them, but
    # we only treat *.md with an id-or-frontmatter as issues. Skip obvious
    # non-issues (no frontmatter at all) silently.
    issues = []
    for p in paths:
        base = os.path.basename(p)
        if base in ("CHANGES.md", "README.md"):
            continue
        iss = parse_issue(p)
        if iss is None:
            continue
        # A file with no frontmatter and no id is not an issue — skip quietly.
        if not iss["id"] and any("no YAML frontmatter" in m for _, m in iss["problems"]):
            continue
        issues.append(iss)
    return issues


def resolve_token(token, issues):
    """Mirror afk: files whose basename matches the glob `<token>-*.md`."""
    return [i for i in issues if i["base"].startswith(token + "-")]


def epic_of(iid):
    """Strip a trailing -<NN> sequence number to get the epic prefix."""
    m = re.match(r"^(.*)-\d+$", iid)
    return m.group(1) if m else "(ungrouped)"


# --------------------------------------------------------------------------- lint

def find_problems(issues):
    """Return a list of (severity, code, key, detail) tuples.
    severity is 'error' (graph-breaking — blocks afk) or 'warn' (informational)."""
    out = []

    # Per-file malformed frontmatter (severity comes from the parser).
    for i in issues:
        for sev, msg in i["problems"]:
            out.append((sev, "BAD_FRONTMATTER", i["base"], msg))

    # Duplicate ids, and id/filename mismatch.
    by_id = {}
    for i in issues:
        if i["id"]:
            by_id.setdefault(i["id"], []).append(i)
            if not i["base"].startswith(i["id"] + "-"):
                out.append(("error", "ID_FILENAME_MISMATCH", i["id"],
                            "file %s does not start with the id prefix %r"
                            % (i["base"], i["id"] + "-")))
    for iid, group in sorted(by_id.items()):
        if len(group) > 1:
            out.append(("error", "DUPLICATE_ID", iid,
                        "shared by " + ", ".join(g["base"] for g in group)))

    # Dependency edges: dangling, ambiguous, self.
    for i in issues:
        for tok in i["blocked_by"]:
            if tok == i["id"]:
                out.append(("error", "SELF_DEP", i["id"], "issue lists itself in blocked_by"))
                continue
            matches = resolve_token(tok, issues)
            if not matches:
                out.append(("error", "DANGLING_DEP", i["id"],
                            "blocked_by %r matches no issue (it can never become ready)" % tok))
            elif len(matches) > 1:
                out.append(("error", "AMBIGUOUS_DEP", i["id"],
                            "blocked_by %r matches %d files (%s) — afk picks one arbitrarily"
                            % (tok, len(matches), ", ".join(m["base"] for m in matches))))

    # Cycle detection over resolved edges.
    graph = {}
    for i in issues:
        deps = []
        for tok in i["blocked_by"]:
            matches = resolve_token(tok, issues)
            if len(matches) == 1 and matches[0]["id"] and matches[0]["id"] != i["id"]:
                deps.append(matches[0]["id"])
        graph[i["id"]] = deps

    WHITE, GREY, BLACK = 0, 1, 2
    color = {iid: WHITE for iid in graph}
    seen_cycles = set()

    def visit(node, stack):
        color[node] = GREY
        for nxt in graph.get(node, []):
            if nxt not in color:
                continue
            if color[nxt] == GREY:
                cyc = stack[stack.index(nxt):] + [nxt]
                key = tuple(sorted(set(cyc)))
                if key not in seen_cycles:
                    seen_cycles.add(key)
                    out.append(("error", "CYCLE", cyc[0], " -> ".join(cyc)))
            elif color[nxt] == WHITE:
                visit(nxt, stack + [nxt])
        color[node] = BLACK

    for iid in graph:
        if color.get(iid) == WHITE:
            visit(iid, [iid])

    return out


def cmd_lint(issues, as_json):
    rows = find_problems(issues)
    errors = [r for r in rows if r[0] == "error"]
    warns = [r for r in rows if r[0] == "warn"]
    if as_json:
        print(json.dumps({
            "ok": not errors,
            "count": len(issues),
            "errors": [{"code": c, "key": k, "detail": d} for _, c, k, d in errors],
            "warnings": [{"code": c, "key": k, "detail": d} for _, c, k, d in warns],
        }, indent=2))
    elif not errors and not warns:
        print("✓ %d issues, dependency graph OK" % len(issues))
    else:
        if errors:
            print("✗ %d error(s) in the issue graph:" % len(errors))
            for _, code, key, detail in errors:
                print("  %-22s %-14s %s" % (code, key, detail))
        if warns:
            print("⚠ %d warning(s):" % len(warns))
            for _, code, key, detail in warns:
                print("  %-22s %-14s %s" % (code, key, detail))
        if not errors:
            print("graph OK (warnings only — afk will run).")
    return 2 if errors else 0


# -------------------------------------------------------------------------- ready

def compute_ready(issues):
    by_status = {}
    for i in issues:
        by_status.setdefault(i["status"] or "?", []).append(i)

    ready, blocked = [], []
    for i in issues:
        if i["status"] != "open":
            continue
        unmet = []
        for tok in i["blocked_by"]:
            matches = resolve_token(tok, issues)
            if len(matches) != 1 or matches[0]["status"] != "done":
                unmet.append(tok)
        if unmet:
            blocked.append((i, unmet))
        else:
            ready.append(i)
    return by_status, ready, blocked


def cmd_ready(issues, as_json):
    by_status, ready, blocked = compute_ready(issues)
    if as_json:
        print(json.dumps({
            "total": len(issues),
            "by_status": {k: len(v) for k, v in sorted(by_status.items())},
            "ready": [{"id": i["id"], "title": i["title"], "epic": epic_of(i["id"])}
                      for i in ready],
            "blocked": [{"id": i["id"], "needs": unmet} for i, unmet in blocked],
        }, indent=2))
        return 0

    roll = ", ".join("%d %s" % (len(v), k) for k, v in sorted(by_status.items()))
    print("issues/ — %d total: %s" % (len(issues), roll or "(none)"))
    print()
    if ready:
        print("Ready (%d) — unblocked, status:open:" % len(ready))
        for i in sorted(ready, key=lambda x: x["id"]):
            print("  %-16s %s" % (i["id"], i["title"]))
    else:
        print("Ready (0) — nothing is currently actionable.")
    if blocked:
        print()
        print("Blocked (%d):" % len(blocked))
        for i, unmet in sorted(blocked, key=lambda x: x[0]["id"]):
            print("  %-16s needs: %s" % (i["id"], ", ".join(unmet)))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="valk-issues", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd")
    for name in ("ready", "lint"):
        sp = sub.add_parser(name)
        sp.add_argument("--dir", default="issues", help="issues directory (default: ./issues)")
        sp.add_argument("--json", action="store_true", help="machine-readable output")
    args = p.parse_args(argv)

    if not args.cmd:
        p.print_help(sys.stderr)
        return 1
    if not os.path.isdir(args.dir):
        print("error: no issues directory at %s" % args.dir, file=sys.stderr)
        return 1

    issues = load(args.dir)
    if args.cmd == "lint":
        return cmd_lint(issues, args.json)
    return cmd_ready(issues, args.json)


if __name__ == "__main__":
    sys.exit(main())
