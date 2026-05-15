---
pr_skill: none
test_skill: none
---

# Fixture config: trivial-slice

No PR step, no test skill — keeps the integration scenario host-independent and free of Azure/TrueTest dependencies. The agent uses local tests if it writes any, and marks the issue done via the frontmatter field flip (current default behavior).
