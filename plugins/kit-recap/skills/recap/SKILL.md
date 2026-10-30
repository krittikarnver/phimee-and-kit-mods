---
name: recap
description: Use when the user has lost track of the current conversation and asks where it left off or what the last few turns were about, or types /kit-recap:recap.
---

# Recap the conversation

Answer from the conversation itself. Read only: call no tools and change nothing.

A turn is one message the user typed and everything Claude did in reply, up to the user's next
message. Cover the 5 turns before this request; this request is not one of them. These are not
the user's turns: slash-command output, hook context lines, task or system notifications, and
messages a plugin sent in the user's place (a kit-checkpoint handoff, a kit-update restart
request). Fold them into the turn they arrived in.

If fewer than 5 turns are visible because the conversation started from a handoff or was
compacted, cover what is there, and say in one line that anything earlier is known only from
that summary.

## Reply

Three parts, in this order, in the user's language (headings below are Thai; translate them if
the user writes in another language). The whole reply fits one screen, about 20 lines.

**ตอนนี้อยู่ตรงไหน**
One or two sentences: where things stand now, and what is waiting on the user (a question
Claude asked, an approval, a step only they can do). If nothing is waiting, say so.

**ย้อนหลัง N turn**
Newest first, one bullet per turn: what the user asked or decided, then what Claude did and how
it ended. Name files, PRs, and commits as they appeared. A decision is the user's only when
their own message makes it; what Claude chose on its own, say Claude chose.

**ค้างอยู่**
Open items from these turns that are not done, at most 4. If none, one line saying so.

Nothing else.
