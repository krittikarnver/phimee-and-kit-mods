---
name: scrutinize-loop
description: Review a spec or plan with the scrutinizer subagent, apply the feedback, and repeat. At least 3 rounds, then one round at a time until no blocker or major remains. Use after writing or updating a spec or plan, or when the user types /scrutinize-loop.
argument-hint: [path to spec or plan]
---

# Scrutinize loop

Target: $ARGUMENTS
If empty, use the spec or plan just written or edited in this conversation.
If that is unclear, ask the user which file.

Run this loop in the main conversation. You edit the file; the subagent only reviews.

## Each round

1. Spawn a NEW `scrutinizer` subagent (it may be listed as `kit-scrutinize:scrutinizer`)
   with the target path. Use a fresh subagent every round so the reviewer has no memory
   of earlier reviews.
   - Round 1: full review.
   - Round 2 and later: add "skip simpler-alternative pass" to the task.
2. If the verdict is `rework` or `reject`: stop the loop. Show the user the main reason
   and ask how to proceed. Do not redesign the plan on your own.
3. Otherwise apply the feedback to the file yourself, right away:
   fix every blocker and major, fix nits when cheap.
   If a finding is wrong, don't apply it; note why.
4. Note round N: blocker / major / nit counts, verdict, what changed, what was rejected.

## When to stop

- Always run 3 rounds.
- After round 3: if the latest round reported any blocker or major, run one more round.
  Repeat until a round reports zero blockers and zero majors.
  (A fix made in the last round must itself be reviewed, so a round that fixed a
  major is never the final one.)
- Safety cap: if round 8 still has blockers, stop and report to the user.
  This usually means the spec has an open decision only the user can make.

## Finish

Short table, one row per round: blocker / major / nit, verdict, main fixes.
Then list remaining non-blocker findings and any rejected findings with reasons.
