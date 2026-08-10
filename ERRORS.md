# Error Log

Running list of errors, bugs, and broken behavior found in this repository **and not fixed
at the time they were found** — discovered in passing, out of scope for the task at hand,
blocked, or deferred. An error fixed as part of the work that surfaced it does not belong
here; the fix and its commit are the record.

The test is whether something still needs attention, not whether a fix happened. Log it even
after fixing when any of these hold:

- The **symptom** was fixed but the **root cause** was not.
- The fix **could not be verified** — no coverage, or the original condition can't be reproduced.
- **One instance of a pattern** was fixed and the pattern plausibly exists elsewhere.

In those cases, state plainly in the entry what was fixed and what remains outstanding.

Each entry must carry enough context that a future session — or a different agent — can
pick it up cold and fix it without re-discovering anything.

**This file is append-and-update, never rewrite.** Add new entries at the top of Open
Issues. When an issue is fixed, move it to Resolved with the resolution filled in.

## Status values

| Status | Meaning |
|---|---|
| `identified` | Found and written up. Nobody is on it. |
| `working` | Actively being fixed right now. |
| `completed` | Fixed and verified. Moved to the Resolved section. |

## Entry template

Copy this block for every new error.

```markdown
### ERR-000 — Short title

- **Date discovered:** YYYY-MM-DD
- **Status:** identified
- **Severity:** critical | high | medium | low
- **Area:** e.g. light engine, analysis pipeline, playlist import, build

**Symptom**
What actually goes wrong, observed — error text, wrong output, crash, failing test name.

**Where**
`path/to/File.swift:123` — the specific call site(s) involved.

**Reproduction**
Exact steps or the exact command. Include the failing test filter if there is one.

**Root cause**
What is actually wrong, if known. Write "unknown — not yet investigated" rather than guessing.

**Already done** _(only if partly fixed when found)_
What was fixed at discovery time, and what is still outstanding — the unverified fix, the
untouched root cause, or the other instances of the pattern.

**Proposed fix**
The change that should resolve it, and anything it would touch.

**Risks / blockers**
Coupled behavior, missing decisions, or anything that makes this non-obvious.

**Resolution**
Filled in when status becomes `completed`: what was changed, and how it was verified.
```

---

## Open issues

_None recorded yet._

---

## Resolved

_None yet._
