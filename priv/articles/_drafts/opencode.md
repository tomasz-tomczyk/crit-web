---
slug: review-opencode-plans-before-it-writes-code
title: Review OpenCode's plan before it writes code
excerpt: OpenCode's Plan agent can't change your code by default. Crit gives you a place to comment on what it came up with.
category: Guide
published_at: [[DATE]]
read_time: 4 min read
hero_image: [[HERO IMAGE]]
author: Tomasz Tomczyk
---

OpenCode has two built-in primary agents, Build and Plan. Switch between them with `Tab`. Plan is restricted: file edits and bash commands are set to `ask` by default, so it can analyze code and write plans without changing anything unless you say yes.

Source: [OpenCode agents](https://opencode.ai/docs/agents/).

## Adding Crit

```bash
crit install opencode
```

This creates `.opencode/commands/crit.md` and `.opencode/skills/crit/SKILL.md`. There is no plan-mode hook for OpenCode, so the review is something you ask for rather than something that interrupts the agent.

1. In the Plan agent, ask for a plan and have it write the plan to a file.
2. Run `/crit`. If a plan was written earlier in the conversation, the command opens it. You can also pass the file: `/crit plan.md`.
3. Comment in the browser. The agent waits for you to finish, reads the comments and revises.

[[SCREENSHOT: /crit running in OpenCode and the plan in the browser]]

## Honest limits

No hook means no forced pause. If you forget to run `/crit`, the plan goes unreviewed. [[CONFIRM: whether Tomasz plans an OpenCode hook]]

There is also a long OpenCode tutorial on this site, [How to Plan, Document and Review Code with Open Source Tools](/articles/how-to-plan-document-and-review), that goes through Superpowers, OpenCode and Crit end to end.
