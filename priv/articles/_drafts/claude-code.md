---
slug: review-claude-code-plans-before-it-writes-code
title: Review Claude Code's plan before it writes code
excerpt: Claude Code's plan mode stops the agent from editing files. Crit turns the end of plan mode into a proper review: inline comments, revisions, and an explicit approval.
category: Guide
published_at: [[DATE]]
read_time: 4 min read
hero_image: [[HERO IMAGE]]
author: Tomasz Tomczyk
---

Plan mode is the cheapest review step you have. The agent reads the codebase, writes a plan, and nothing changes on disk until you say so. The catch is the review itself. The plan shows up in the terminal, you skim it, and "yes" is the easiest key to press.

This page covers how plan mode works today and how to add a real review step to it with Crit.

## How plan mode works

Press `Shift+Tab` to cycle permission modes (default, acceptEdits, plan). You can also start a prompt with `/plan` or launch with `claude --permission-mode plan`. The status bar shows `⏸ plan mode on`. In plan mode Claude reads files and proposes changes but does not edit your source.

When the plan is ready, Claude shows an approval dialog. You can approve and start in auto mode, approve and accept edits, approve and review each edit manually, or keep planning with feedback. `Ctrl+G` opens the plan in your text editor if you want to edit it directly.

Source: [permission modes](https://code.claude.com/docs/en/permission-modes) and [common workflows](https://code.claude.com/docs/en/common-workflows).

## Adding Crit

Install the plugin:

```bash
claude plugin marketplace add tomasz-tomczyk/crit
claude plugin install crit@crit
```

The plugin ships a hook on `ExitPlanMode`. When Claude finishes a plan, the hook sends it to Crit instead of straight to the approval dialog. Your browser opens with the plan rendered as a document. Click a line or select a range and leave a comment. When you finish the round, Claude reads the comments, revises the plan, and sends it back. Plan mode does not exit until you approve.

To turn the hook off: `export CRIT_PLAN_REVIEW=off`.

The plugin also adds a `/crit` command for reviewing code changes and files, and the crit-cli skill so the agent knows how to use `crit comment` and friends.

[[SCREENSHOT: a plan in Crit with two or three inline comments]]

## What about Ultraplan?

Anthropic has its own browser-based plan review, [Ultraplan](https://code.claude.com/docs/en/ultraplan). Run `/ultraplan` and the plan opens in Claude Code on the web, with inline comments, emoji reactions and an outline sidebar. It needs Claude Code on the web, a GitHub repository and Anthropic's cloud, and it is not available on Bedrock, Vertex or Foundry.

If that fits how you work, use it. Crit is the option when you want the review to stay on your machine, when you use more than one agent, or when you want the comments saved as a file next to your code. [[CONFIRM: Tomasz's own take on when he reaches for which]]

## Share it with the team

A plan you reviewed alone is still one person's opinion. Crit can share the plan with a link so teammates comment on it too, and you pull their comments back into the session. [[CONFIRM: exact share command or button wording]]
