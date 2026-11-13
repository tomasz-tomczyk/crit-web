---
slug: share-agent-plans-with-your-team
title: How to Share an Agent's Plan with Your Team and Get Comments on It
excerpt: Your agent wrote a plan. Before it writes code, get a second pair of eyes on it. Share the plan from Crit, collect line-level comments from your team, and feed them back to the agent.
category: Tutorial
published_at: [[DATE]]
read_time: 8 min read
hero_image: [[HERO IMAGE: the shared plan page with two reviewers' comments visible]]
author: [[AUTHOR]]
---

<!--
DRAFT NOTES FOR TOMASZ (delete before publishing)
- Everything marked [[...]] needs your real material: screenshots, example comments, author, date, hero image.
- Commands, flags, env vars and the 30-day inactivity cleanup were re-verified against the crit and crit-web repos on Nov 13, 2026. The self-host commands come from the crit-web README; worth one real run before publishing.
- This file sits in priv/articles/_drafts as a single .md, so the article loader (priv/articles/*/index.md) never picks it up. To publish: fill the placeholders, move it to priv/articles/share-agent-plans-with-your-team/index.md.
-->

An agent writes a plan, you read it, it looks fine, and you tell it to go ahead. An hour later a teammate looks at the result and says "we can't use that queue, we're on SQS". Nobody saw the problem because only one person read the plan.

Plans are cheap to fix and code is not. If someone else on your team is going to have an opinion, the plan is the time to hear it.

This tutorial shows how to share a plan from Crit, get comments from your teammates on specific lines, and bring those comments back to your agent. It takes about ten minutes the first time. You'll need Crit installed and an agent that has already written a plan as a markdown file. If you haven't set up Crit yet, the [getting started guide](/getting-started) covers it.

## Step 1: Review the plan yourself first

Share a plan after you've read it, not before. Your teammates' time is worth more than a first draft.

Open the plan in Crit:

```bash
crit plan.md
```

Read it, leave comments on anything you already know is wrong, and let the agent revise. Do a round or two until you'd be comfortable putting your name on it. Then it's ready for other people.

[[SCREENSHOT: plan.md open in Crit with one or two of your own comments]]

## Step 2: Share it

You can share from the browser UI or from the terminal.

In the browser, click Share in the review header. Crit uploads the plan with your comments and gives you a link.

From the terminal:

```bash
crit share plan.md
```

This prints the URL. If you're sitting next to someone, add `--qr` and Crit prints a QR code in the terminal as well:

```bash
crit share plan.md --qr
```

Send the link to your team in whatever channel you already use. Anyone who opens it sees the rendered plan and your comments in the browser. They don't need to install Crit or have an account to read it.

[[SCREENSHOT: the shared plan page as a teammate sees it]]

## Step 3: Let your team comment

Your teammates comment the same way you did: click a line number, or drag to select a range, and write the comment. Each reviewer's comments are colour-coded by author, so on a plan with four people on it you can still tell who said what.

This is where the plan earns its keep. A comment pinned to a line is easier to act on than a Slack thread about "the plan": the agent sees exactly which sentence someone means, and so do you.

[[REAL EXAMPLE: two or three comments from an actual shared plan, with the reviewer's permission. Don't invent these.]]

## Step 4: Pull the comments back and hand them to the agent

When your teammates are done, bring their comments into your local review. In the browser, open the share dialog and click Pull comments. Their comments land next to your own, in the same review file the agent already reads.

Click Finish Review and the agent gets the comments. It revises the plan, and Crit starts a new round with a diff of what changed.

If the revised plan needs another look from the team, share it again. The link stays the same, and the comments from the first round survive the re-upload.

## Step 5: Control who can see it

By default, a shared plan is reachable by anyone who has the link. Some plans shouldn't be. Three things help.

**Use an organization.** If you belong to a crit.md organization, share under it:

```bash
crit share plan.md --org acme
```

Visibility then defaults to `organization`, which means members only. You can set it explicitly with `--visibility`, which takes `organization`, `unlisted` or `public`:

```bash
crit share plan.md --org acme --visibility unlisted
```

In the browser UI, an org picker shows up when you're signed in and belong to one.

**Sign in.** You can share anonymously, or create a free crit.md account with GitHub OAuth. To authenticate from the CLI:

```bash
crit auth login
```

This opens your browser, you confirm, and the CLI stores a token in `~/.crit.config.json`. `crit auth status` lists the places you're signed in.

**Take it down when you're done:**

```bash
crit unpublish
```

Shared reviews are also cleaned up on their own after 30 days without activity.

## Step 6: Run it on your own server

Some teams can't put plans on a hosted service. Fair enough: the plan might describe an unreleased product, an internal system, or a security fix. crit-web, the server behind crit.md, is open source and you can host it yourself. You need PostgreSQL 17 or newer.

If you already have a Postgres instance:

```bash
docker run -d \
  -e DATABASE_URL=ecto://user:pass@your-db-host/crit_prod \
  -e SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n') \
  -e SELFHOSTED=true \
  -e PHX_HOST=localhost \
  -e PHX_SERVER=true \
  -p 4000:4000 \
  ghcr.io/tomasz-tomczyk/crit-web:latest
```

Migrations run on startup. If you'd rather have Postgres included, the repo ships a Docker Compose example (`contrib/docker-compose.example.yml`). Copy it and the `.env.example` file, set `SECRET_KEY_BASE`, and run `docker compose up -d`.

Two settings matter for a team:

- **Login.** Set `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` to require GitHub login, or use the `OAUTH_*` variables for Google, GitLab, Okta and other OIDC providers. With either one set, people have to sign in to open the dashboard and view reviews. If you're not using external login, set `LOCAL_REGISTRATION_ENABLED=false` once you've created the accounts you want, so strangers can't register.
- **Email.** Discussion digests are off by default. Set `SMTP_HOST` and `SMTP_FROM`, then turn notifications on under Admin, Settings, so people hear about replies without checking a tab.

Behind a reverse proxy like nginx, Caddy or Traefik, the app listens on plain HTTP and the proxy handles TLS. Set `PHX_HOST`, `PHX_SCHEME=https` and `PHX_URL_PORT=443` so the generated links are right.

Then point the CLI at your server:

```bash
crit auth login --share-url https://reviews.yourdomain.com --set-default
```

From now on `crit share` goes to your server. If your people use both, put several targets in `share_targets` in your config and Crit asks which one to use each time. A review stays bound to the destination it was first shared to.

```json
{"share_targets":[
  {"name":"Acme Crit","url":"https://crit.acme.com","default":true},
  {"name":"crit.md","url":"https://crit.md"}
]}
```

One caveat if your server sits behind an SSO proxy the terminal can't log in through: set `proxy_auth: true` on that target. Sharing from the browser UI then works, but `crit share` from the terminal doesn't.

## What to do with this

Share plans that someone else will have to live with: a new service, a schema change, a migration. Skip it for a one-file refactor. A plan that nobody comments on has still cost you very little, and a plan with one good comment from a teammate who knows the system has paid for itself.

If you find a rough edge in sharing, open an issue on [crit](https://github.com/tomasz-tomczyk/crit/issues) or [crit-web](https://github.com/tomasz-tomczyk/crit-web/issues).
