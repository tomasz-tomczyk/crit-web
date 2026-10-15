---
slug: review-agent-memory
title: Your coding agent remembers things that stopped being true
excerpt: Claude Code saves memories as it works. Months later, a lot of them are wrong. Open them all in Crit, comment on each one, and let the agent clean up.
category: Tutorial
published_at: 2026-10-15
read_time: 5 min read
hero_image: https://assets.crit.md/articles/review-agent-memory/hero.jpg
author: Tomasz Tomczyk
---

Your coding agent saves memories as it works. Notes about your project, your preferences, bugs it ran into. They load into every new session, so the agent doesn't ask the same questions twice.

That's great for a week. Then the project moves on and the memories don't. The checkout rollout that was "in progress, don't remove the old flow yet" shipped in July. The rule says "use npm" and you switched to pnpm in August. There's a page of notes from one debugging session in June that nobody will ever need again. The agent still reads all of it, every session, and treats it as true.

Here's the whole fix in under two minutes:

![Reviewing Claude Code memory files in Crit](https://assets.crit.md/articles/review-agent-memory/review-agent-memory.mp4 "https://assets.crit.md/articles/review-agent-memory/poster.jpg")

## Where the memories live

Claude Code keeps memory per project, as plain markdown files:

```
~/.claude/projects/<project>/memory/
  MEMORY.md
  feedback_use_npm.md
  project_checkout_v2_rollout.md
  ticket_shop_412_stripe_webhook_debug.md
  ...
```

Each file has a little frontmatter (`name`, `description`, a `type`) and a few lines of text. `MEMORY.md` is the index: it lists them all with a one-line summary and loads into every session.

You probably never open these. Most people don't know how many there are. In the demo it's 23 memories across 4 projects, which is about what I had after a few months.

## Open them all in Crit

You don't need to find the files yourself. Install Crit and its Claude Code plugin:

```bash
brew install crit
claude plugin marketplace add tomasz-tomczyk/crit
claude plugin install crit@crit
```

Then ask:

```
find all my memory files and /crit them
```

Claude looks in `~/.claude/projects`, finds the memory folders, and runs:

```bash
crit ~/.claude/projects/*/memory/*.md
```

Crit opens in your browser with every memory in one file tree, markdown rendered, frontmatter shown as a code block.

## Comment on each one

Go through them like any other review. Each memory ends up in one of four places:

- **Still right.** Mark it viewed and move on. "Never use `--no-verify`" doesn't go stale.
- **Out of date.** Delete it. The checkout rollout shipped, so the status note goes. Drag across the gutter to comment on the four status lines at once.
- **Wrong in one detail.** Update it. Select just the word "npm", press `c`, and write "we switched to pnpm in aug". The comment keeps the quote, so the agent knows exactly what to change.
- **Useful to everyone, not just the agent.** Move it to the repo. The note that Playwright's `BASE_URL` must be `localhost`, not `127.0.0.1`, belongs in `docs/testing.md` where your team can find it.

Write comments like you'd talk to a colleague. "this shipped in july, old flow is gone. delete" is plenty.

You don't have to comment on every file either. One review-level comment covers the rest: "also delete any ticket notes older than a month. if you're not sure about one ask me."

## Let the agent clean up

Press Finish Review. Claude reads every comment and does the work: deletes the stale files, adds the gotcha to `docs/testing.md`, rewrites the npm rule, and updates each project's `MEMORY.md` so the index matches.

Then it replies to each comment in Crit. When it isn't sure, it asks. In the demo it deleted four old ticket notes but kept one, because that ticket is still open: "Want me to delete it anyway?" You answer in the thread, resolve the ones that are done, and finish the round.

The next session starts with memory you can actually trust.

## Codex and Gemini too

Claude Code isn't the only agent that remembers things. Codex keeps memories in `~/.codex/memories`, and Gemini CLI saves them to `~/.gemini/GEMINI.md`. Point your agent at those paths instead and the review works the same way.

## How often

Every month or two is enough. Memories pile up slowly, and most of them stay right. The ones that go wrong are notes about work in progress, one-off debugging, and tooling that changed. Those are easy to spot once they're all in one place.

Think of it as spring cleaning. Ten minutes, and your agent stops working from last quarter's facts.
