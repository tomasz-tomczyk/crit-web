---
slug: review-copilot-plans-before-it-writes-code
title: Review GitHub Copilot's plan before it writes code
excerpt: Copilot CLI and VS Code both have a plan step. Here is how to review that plan with Crit.
category: Guide
published_at: [[DATE]]
read_time: 4 min read
hero_image: [[HERO IMAGE]]
author: Tomasz Tomczyk
---

Copilot has a plan step in two places.

**Copilot CLI.** Press `Shift+Tab` to cycle into plan mode, or use `/plan` in normal mode (`/plan Add OAuth2 authentication`). Copilot asks clarifying questions, builds a structured plan with checkboxes and saves it as `plan.md` in your session folder. `Ctrl+y` opens it in your default Markdown editor. Source: [CLI best practices](https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-best-practices) and the [plan mode changelog](https://github.blog/changelog/2026-01-21-github-copilot-cli-plan-before-you-build-steer-as-you-go/).

**VS Code.** Pick the built-in Plan agent from the agents dropdown in Chat, or type `/plan` followed by your task. When the plan is done you choose Start Implementation and an implementation agent, or open the plan in the editor. Source: [Planning with agents in VS Code](https://code.visualstudio.com/docs/copilot/agents/planning).

## Adding Crit

```bash
crit install github-copilot
```

This installs the Crit skills into `.github/skills/` (or `~/.copilot/skills/` for a global install). There is no hook, so you ask for the review. Point Crit at the plan file: [[CONFIRM: exact way to invoke the skill in Copilot CLI and in VS Code]]

For the CLI, the plan is already a Markdown file in the session folder, so `crit <path to plan.md>` works from a second terminal. [[CONFIRM: path of the session folder]]

[[SCREENSHOT: Copilot plan.md open in Crit]]

## Honest limits

No hook, so no automatic pause before implementation. The review happens when you start it.
