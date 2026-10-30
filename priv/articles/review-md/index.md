---
slug: review-md
title: "REVIEW.md: a simple file for reviewing what your agent changed"
excerpt: Ask your agent to write up what it changed in a REVIEW.md, open it in Crit, and comment on the lines you disagree with. A small convention that keeps reviews out of the chat scroll.
category: Tutorial
published_at: 2026-10-30
read_time: 3 min read
hero_image: https://crit.md/images/og.png
author: Tomasz Tomczyk
---

Your agent finished the task and posted a summary in chat. "Refactored the auth module, added rate limiting, fixed the token refresh bug." Three bullets for a 400-line diff. If you want to push back on one of them, you quote it, type a reply, and hope the agent connects it to the right lines.

There is a simpler version of this: make the summary a file.

## The convention

When the agent finishes, ask it to write REVIEW.md at the root of the repo: what changed, why, and anything it is unsure about. One file, plain markdown. Keep it out of git with a .gitignore entry, or commit it and let it evolve. Either works.

Then open it in Crit:

```
crit REVIEW.md
```

It renders in the browser like a pull request. You read the summary, click and drag on the lines you disagree with, and leave comments. "This rate limit is per user, not per IP." "The migration needs to be reversible." When you finish the review, the agent gets your comments with line numbers attached and rewrites both the file and the code.

## Why a file beats the chat

Chat is a stream. The summary scrolls away, the next prompt buries it, and three sessions later nobody remembers what was agreed. A file is addressable: comments attach to exact lines, they stay attached across rounds, and the round diff shows what the agent changed in response. When the summary says one thing and the code does another, that gap is exactly what you are reviewing for.

## Make it a habit

Add one line to your agent instructions: "After completing a task, write REVIEW.md with a summary of the changes and any open questions." Any agent that can write a file can do this, so the convention works the same with Claude Code, Codex, OpenCode or anything else. Crit has no special REVIEW.md handling; it just renders markdown files well, which is all the convention needs.
