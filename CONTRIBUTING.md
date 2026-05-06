# Contributing to Crit Web

Thanks for your interest in contributing! Here's how to get started.

## Before you start

For bug fixes and small improvements, feel free to open a PR directly. For larger changes — new features, significant refactors, or anything that touches core architecture — please **open an issue first** to discuss the approach.

Any changes to the review page UI must maintain **feature parity with the [crit CLI](https://github.com/tomasz-tomczyk/crit)** frontend. If you add a review feature to crit-web, it should also be ported to crit (and vice versa).

## Development setup

You need Elixir 1.19+, Erlang/OTP 28+, PostgreSQL 17+, and Node.js.

```bash
git clone https://github.com/tomasz-tomczyk/crit-web.git
cd crit-web
mix setup       # Install deps, create DB, run migrations, build assets
mix phx.server  # Start dev server on :4000
```

### Self-hosted mode

To develop features that are self-hosted-only (like the admin dashboard), start the server with:

```bash
SELFHOSTED=true mix phx.server
```

This enables the `/dashboard` and `/overview` routes and other self-hosted features. Create the first account at `http://localhost:4000/users/register`, or seed one from the shell with `mix crit.create_user EMAIL PASSWORD`.

## Running tests

```bash
mix test                              # All tests
mix test test/crit/reviews_test.exs   # Single file
mix test test/crit/reviews_test.exs:42  # Single test by line
```

## Before submitting a PR

Run the full CI check locally:

```bash
mix precommit
```

This runs: compile (warnings-as-errors), format check, sobelow security audit, dependency audit, and all tests.

## Code style

- Elixir code is formatted with `mix format`
- Review page CSS uses custom `--crit-*` variables and `.crit-*` classes (no Tailwind)
- All other pages use Tailwind utility classes in templates (no custom CSS)
- No inline `<script>` tags in templates

## Versioning

This project uses [Semantic Versioning](https://semver.org/). The current version is pre-1.0, so breaking changes may occur in minor versions.
