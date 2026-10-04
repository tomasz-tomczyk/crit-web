---
slug: review-cursor-plans-before-it-writes-code
title: Review Cursor's plan before it writes code
excerpt: Cursor's Plan Mode produces an editable plan. Crit adds line-level comments you can share and send back to the agent.
category: Guide
published_at: [[DATE]]
read_time: 4 min read
hero_image: [[HERO IMAGE]]
author: Tomasz Tomczyk
---

Cursor's Plan Mode researches your codebase, asks clarifying questions and generates a plan you can edit before building. Press `Shift+Tab` in the chat input to rotate into it. Cursor sometimes suggests it on its own when your prompt looks complex.

Plans are saved in your home directory by default. "Save to workspace" moves one into the project so it can be shared and kept. That matters here, because Crit reviews a file.

Source: [Cursor Plan Mode](https://cursor.com/docs/agent/planning).

## Adding Crit

```bash
crit install cursor
```

This installs the Crit skills into `.cursor/skills/`. There is no hook. The skill only runs when you explicitly invoke `/crit` or ask for Crit by name. A generic "review this plan" will not trigger it.

1. Build the plan in Plan Mode and click "Save to workspace".
2. In chat, run `/crit <path to the plan>`.
3. Comment in the browser, finish the review, and the agent picks the comments up and revises.

[[SCREENSHOT: Cursor plan open in Crit]]

## Honest limits

Cursor's own plan editing works through chat and Markdown files, which is fine for one person. Crit is for when you want comments anchored to lines, saved as a file, or shared with someone else. No hook means no forced pause before the build.
