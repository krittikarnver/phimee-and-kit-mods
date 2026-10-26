---
name: explain
description: Use when the user finds a spec or plan too long to read, asks for a summary or explanation of one, asks whether it matches what they decided, or types /kit-scrutinize:explain. Also used by /scrutinize-loop when it finishes.
argument-hint: [path to spec or plan]
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/user-said.sh *)
---

# Explain a spec or plan

Target: $ARGUMENTS
If empty, use the spec or plan just written, edited, or reviewed in this conversation.
If that is unclear, ask the user which file.

Read only. Do not edit, create, or move any file.

## 1. Gather

1. Read the target in full.
2. Run this once with the Bash tool, exactly as written (no quotes around the script path):
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/user-said.sh <target path>`
   It prints one of:
   - `=== transcript` blocks: every prompt the user typed (`USER:`) in each conversation that
     mentions the file, after the end of Claude's message it answers (`CLAUDE: …`).
   - `=== handoff` blocks: kit-checkpoint handoffs. Claude wrote these, not the user.
   - `NONE`: nothing found.
3. If the target is a plan that names its spec (e.g. a `**Spec:**` line), read the spec too and
   run the script on it as well: the design decisions were made in the spec's conversation.

## 2. Find the user's decisions

A decision is the user's only when a `USER:` line makes it, and it is about what gets built
or how it behaves. A short answer counts for the question it answers: "รอว่าง" after
"รอจนว่าง หรือข้ามไป" decides "wait". "ได้ครับ" after a proposal approves only what that
`CLAUDE:` text shows. Skip `USER:` lines about other work, and go-aheads to run, push, or
merge.

What the target, a handoff, or Claude says the user chose is not evidence: that is Claude
checking its own notes. If there are only handoffs, compare against them and say so in
part 2. If `NONE`, replace part 2 with one line saying nothing was found.

## 3. Reply

Four parts, in this order, in the user's language (headings below are Thai; translate them
if the user writes in another language). The whole reply fits one screen, about 25 lines.

**plan นี้ทำอะไร**
Three short lines: what the user gets, why it is needed, and what happens in order as the
user sees it (for a plan, its tasks in order in one line). Not how it works inside.

**ที่คุณตัดสินใจไว้ เทียบกับไฟล์**
One bullet per decision: a label (ตรง / ตรงแต่มีเงื่อนไข / ไม่ตรง / ไม่มีในไฟล์), the
decision in a few words, and for any label but ตรง, what the file says instead.

**ที่ Claude เลือกเอง**
Things the file decides that no `USER:` line decided. For a plan, also what it adds that its
spec does not say. Show at most 4: the ones that change what the user will see, do, or live
with, most surprising first. Then one line: "อีก N ข้อเป็นเรื่องเทคนิคข้างใน ถ้าอยากดูบอกได้".
If the user asks, list the rest in the same form.

**ไฟล์เต็ม**
The path and its line count.

Nothing else: no rules, limits, status, or reading advice.
