# Crit Web — Development Guide

## Quick Start

```bash
dev up                    # Install deps, setup DB, start server on :4000
mix test                  # Run all tests
mix precommit             # Full CI check: compile, format, sobelow, audit, test
```

## Project Structure

```
crit-web/
├── lib/
│   ├── crit/                        # Domain logic
│   │   ├── application.ex           # OTP app supervision tree
│   │   ├── repo.ex                  # Ecto repo
│   │   ├── review.ex                # Review schema (token, document, delete_token)
│   │   ├── comment.ex               # Comment schema (review_id, start_line, end_line, body, parent_id, resolved)
│   │   ├── reviews.ex               # Context: create/get/delete reviews with comments
│   │   ├── output.ex                # Formats review data for API responses
│   │   ├── display_name.ex          # Author display name logic
│   │   ├── integrations.ex          # Integration metadata (editors, AI tools)
│   │   ├── changelog.ex             # GenServer: fetches and caches GitHub releases
│   │   ├── rate_limit.ex            # Hammer-based rate limiting
│   │   ├── release.ex               # Release migration helpers
│   │   ├── review_cleaner.ex        # Periodic cleanup of expired reviews
│   │   ├── review_file.ex           # Review file schema
│   │   └── schema.ex                # Base schema module
│   ├── crit_web/
│   │   ├── router.ex                # Routes: pages, /r/:token LiveView, /api/*
│   │   ├── endpoint.ex              # Phoenix endpoint
│   │   ├── controllers/
│   │   │   ├── api_controller.ex    # JSON API: POST /api/reviews, DELETE, export
│   │   │   ├── auth_controller.ex   # Admin login/logout
│   │   │   ├── health_controller.ex # Health check endpoint
│   │   │   ├── page_controller.ex   # Static pages: home, features, integrations, terms, privacy
│   │   │   ├── review_controller.ex # set-name action
│   │   │   └── page_html.ex         # Page view module
│   │   ├── live/
│   │   │   ├── review_live.ex       # LiveView for /r/:token — loads review, assigns data
│   │   │   └── review_live.html.heex # Review page template (uses crit-* CSS classes)
│   │   ├── components/
│   │   │   ├── core_components.ex   # Shared Phoenix components
│   │   │   └── layouts.ex           # Layout module
│   │   └── plugs/
│   │       ├── identity.ex          # Session-based visitor identity
│   │       ├── security_headers.ex  # CSP, HSTS, etc.
│   │       ├── localhost_cors.ex    # CORS for local crit CLI → crit-web API
│   │       └── canonical_host.ex    # Host redirect
│   └── mix/tasks/
│       └── crit.refresh_integrations.ex  # Mix task for integration data
├── assets/
│   ├── js/
│   │   ├── app.js                   # Phoenix JS setup + LiveView hooks
│   │   └── document-renderer.js     # Port of crit local's rendering logic
│   └── css/
│       └── app.css                  # Review page CSS (crit-* classes) + Tailwind
├── priv/repo/migrations/            # Ecto migrations
├── config/                          # Dev/test/prod/runtime config
├── test/                            # ExUnit tests
└── .github/workflows/ci.yml         # CI: format, compile, sobelow, audit, test
```

## Key Architecture

1. **Review page rendering** — the LiveView loads review data, then `document-renderer.js` (a Phoenix hook) renders the markdown client-side using markdown-it + highlight.js + mermaid. This mirrors how `crit` local renders.
2. **API for CLI uploads** — `POST /api/reviews` accepts `{document, comments, metadata}` from the CLI's Share button. Returns `{url, delete_token}`.
3. **Delete via token** — reviews are deleted by passing the `delete_token` (not auth). The CLI stores this in the review file.
4. **Rate limiting** — Hammer-based, applied to API create/delete endpoints.
5. **Identity** — session-based visitor ID via `Plugs.Identity`, used for display names on comments.
6. **Comment threading** — comments support nested replies (`parent_id` self-referential FK) and a `resolved` boolean. The review LiveView handles reply CRUD and resolve/unresolve via `push_event`.

## Routes

**Browser:**

- `/` — homepage
- `/features`, `/features/:slug` — feature pages
- `/integrations` — integrations page
- `/getting-started` — getting started guide
- `/self-hosting` — self-hosting documentation
- `/changelog` — auto-fetched GitHub release notes
- `/terms`, `/privacy` — legal pages
- `POST /auth/login`, `POST /auth/logout` — admin auth
- `/r/:token` — review LiveView (the core page)
- `POST /set-name` — set display name

**API (`/api`):**

- `POST /reviews` — create review (from CLI share)
- `DELETE /reviews` — delete review (requires delete_token)
- `GET /reviews/:token/document` — review document content
- `GET /reviews/:token/comments` — review comments
- `GET /export/:token/review` — export review data
- `GET /export/:token/comments` — export comments

## Styling Rules

**Review page** (`/r/:token`): Custom CSS only. All styles in `app.css` using `--crit-*` CSS variables and `.crit-*` / `.line-*` / `.comment-*` classes. No Tailwind utilities. Must match `crit` local's look.

**All other pages**: Tailwind utility classes in templates. No custom CSS classes in `app.css`.

See the monorepo CLAUDE.md (`../CLAUDE.md`) for the full parity contract between crit local and crit-web.

## Testing

```bash
mix test                              # All tests
mix test test/crit/reviews_test.exs   # One file
mix test test/crit/reviews_test.exs:42  # One test by line
```

Tests use `DataCase` (database) or `ConnCase` (HTTP). The test database is `crit_test`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on push to main and PRs:

1. `mix format --check-formatted`
2. `mix compile --warnings-as-errors`
3. `mix sobelow --skip`
4. `mix deps.audit`
5. `mix test`

Elixir 1.19 / OTP 28 / PostgreSQL 17.

## Frontend JS Dependencies

`document-renderer.js` uses markdown-it, highlight.js, and mermaid — must stay version-aligned with `../crit/package.json`. See monorepo CLAUDE.md for details.

## What NOT to Do

- Don't use Tailwind utilities on the review page — custom CSS only
- Don't add component libraries for the review surface
- Don't create a separate build pipeline for review JS — it's a single hook file
- Don't add `.home-*` or `.legal-*` CSS classes to `app.css` — use Tailwind in templates

---

## Crit local context

**crit-web** is the hosted share target for [Crit](https://github.com/tomasz-tomczyk/crit) — a local-first Go CLI for reviewing code changes and markdown files with inline comments. When users click Share in local Crit, it POSTs document + comments to `POST /api/reviews`, gets back `{url, delete_token}`, and shows the share link.

**Comment shape** (same in both): `id`, `start_line`, `end_line`, `body`, `author`, `resolved`, `replies` (nested comments with `parent_id`), `created_at`, `updated_at` (ISO8601).

**Security/limits**: HTTPS only, `noindex` meta, 5 MB document, 50 KB per comment body, 500 comments per review. Rate-limit write endpoints and 404s per IP.

**Reviews expire** after 30 days of inactivity (`last_activity_at`).

---

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use `:req` (`Req`) for HTTP requests — **avoid** `:httpoison`, `:tesla`, `:httpc`
- **Never** use `@apply` when writing raw CSS
- Only `app.js` and `app.css` bundles are supported — import vendor deps, don't reference external scripts in layouts
- **Never** write inline `<script>` tags in templates
- Tailwindcss v4 uses `@import "tailwindcss" source(none);` syntax in `app.css` — no `tailwind.config.js`

### Phoenix v1.8

- Begin LiveView templates with `<Layouts.app flash={@flash} ...>` — `Layouts` is already aliased in `crit_web.ex`
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>` for icons — never use `Heroicons` modules
- Use `<.input>` from `core_components.ex` for form inputs. Overriding `class=` replaces all default classes
- `<.flash_group>` lives in `layouts.ex` only — never call it elsewhere

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->

## Elixir gotchas

- Lists don't support index access (`mylist[i]`) — use `Enum.at/2`
- Block expressions (`if`, `case`, `cond`) must bind the result: `socket = if ... do ... end`
- Don't use map access (`changeset[:field]`) on structs — use `my_struct.field` or `Ecto.Changeset.get_field/2`
- Don't use `String.to_atom/1` on user input (memory leak)
- One module per file
- Predicate functions end in `?` — reserve `is_` prefix for guards
- Use `start_supervised!/1` in tests, avoid `Process.sleep/1`
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->

## Phoenix guidelines

- Router `scope` blocks auto-prefix the module alias — don't add your own `alias`
- `Phoenix.View` is removed — don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->

## Ecto guidelines

- Preload associations in queries when accessed in templates
- `Ecto.Schema` uses `:string` type even for `:text` columns
- Use `Ecto.Changeset.get_field/2` to access changeset fields
- Don't list programmatic fields (e.g. `user_id`) in `cast` — set them explicitly
- Use `mix ecto.gen.migration` to generate migration files
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->

## HEEx guidelines

- Use `~H` or `.html.heex` — never `~E`
- Use `to_form/2` + `<.form for={@form}>` + `<.input field={@form[:field]}>` — never pass changesets to templates
- Add unique DOM IDs to forms and key elements
- No `if/elsif` in Elixir — use `cond` or `case`
- Use `phx-no-curly-interpolation` on tags containing literal `{`/`}`
- Class lists must use `[...]` syntax: `class={["px-2", @flag && "py-5"]}`
- Use `{...}` for attribute interpolation, `<%= ... %>` for block constructs (`if`, `for`, `cond`) in tag bodies
- Use `<%!-- comment --%>` for HEEx comments
- Use `:for` comprehensions, not `Enum.each`
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->

## LiveView guidelines

- Use `<.link navigate={href}>` / `<.link patch={href}>` — never `live_redirect`/`live_patch`
- Avoid LiveComponents unless specifically needed
- Name LiveViews with `Live` suffix (e.g. `CritWeb.ReviewLive`)

### Streams

- Use streams for collections — never assign raw lists
- Template: `phx-update="stream"` on parent, `:for={{id, item} <- @streams.name}` with `id={id}`
- Streams are not enumerable — to filter/refresh, refetch and `stream(..., reset: true)`
- Track counts via separate assigns, not stream length
- Never use deprecated `phx-update="append"` or `"prepend"`

### JS hooks

- `phx-hook="MyHook"` requires a unique `id` and `phx-update="ignore"` if the hook manages its own DOM
- Never write raw `<script>` tags — use colocated hooks (`:type={Phoenix.LiveView.ColocatedHook}`, name starts with `.`) or external hooks in `assets/js/`
- Use `push_event/3` server→client, `this.pushEvent` client→server

### LiveView tests

- Use `Phoenix.LiveViewTest` + `LazyHTML` for assertions
- Test with `element/2`, `has_element/2` — never match raw HTML
- Test outcomes, not implementation details
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
