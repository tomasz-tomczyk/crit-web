---
slug: review-codex-plans-before-it-writes-code
title: Review Codex's plan before it writes code
excerpt: Codex Plan mode often keeps the plan in chat. Crit's Codex plugin pulls it out, opens it for review, and holds the turn until you approve.
category: Guide
published_at: [[DATE]]
read_time: 4 min read
hero_image: [[HERO IMAGE]]
author: Tomasz Tomczyk
---

Codex has a Plan mode. It gathers context, asks clarifying questions and builds a plan before implementation starts. Toggle it with `/plan` or `Shift+Tab`. `/plan` also takes a prompt, for example `/plan Propose a migration plan for this service`. It is unavailable while a task is already running.

Source: [Codex slash commands](https://developers.openai.com/codex/cli/slash-commands) and the [Codex manual](https://developers.openai.com/codex/codex-manual.md).

## The problem with in-chat plans

In Plan mode the agent often keeps the plan in the conversation, wrapped in `<proposed_plan>`, instead of writing a file. A file-based review tool has nothing to open. A bare `$crit` needs a path, so on its own it can't review that plan.

## Install the plugin

```bash
cd ~ && crit install codex-plugin
```

That is the global install. Run it inside a project instead and it installs for that project. It registers Crit in the plugin marketplace file, enables `crit@local` in `~/.codex/config.toml`, and turns on `features.plugins`, `features.hooks` and `features.plugin_hooks`. Safe to re-run.

The plugin adds a `Stop` hook. When Codex tries to finish a turn with a proposed plan, the hook reads the plan from the transcript, writes it to a temp file and runs `crit plan-hook --mode codex`. Your browser opens with the plan. Leave inline comments, Codex revises, and the turn does not complete until you approve.

Turn it off with `export CRIT_PLAN_REVIEW=off`.

[[SCREENSHOT: Codex proposed plan open in Crit with comments]]

## Skills only

If you don't want hooks, `crit install codex` installs just the skills into `.agents/skills/`. Then `$crit` reviews current git changes, a file, a PR or a commit range. It will not catch in-chat plans.

## Share it with the team

[[CONFIRM: same share flow as the Claude Code page, wording]]
