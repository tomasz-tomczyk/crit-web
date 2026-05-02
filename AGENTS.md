# Crit Web — Development Guide

Hosted Phoenix LiveView app that receives shared reviews from the [Crit](https://github.com/tomasz-tomczyk/crit) local CLI and renders them at `/r/:token`. Same review surface as the local tool — see `../CLAUDE.md` for the parity contract.

## Project map

```
crit-web/
├── lib/
│   ├── crit/                        # Domain logic
│   │   ├── application.ex           # OTP app supervision tree
│   │   ├── repo.ex                  # Ecto repo
│   │   ├── schema.ex                # Base schema module
│   │   ├── review.ex                # Review schema (token, delete_token, last_activity_at, review_round, cli_args)
│   │   ├── comment.ex               # Comment schema (review_id, parent_id, start_line, end_line, body, scope, resolved, author_identity, author_display_name, file_path, quote, external_id)
│   │   ├── review_round_snapshot.ex # Per-round snapshot of review files
│   │   ├── reviews.ex               # Context: create/get/delete reviews with comments (10 MB total limit)
│   │   ├── review_cleaner.ex        # Periodic cleanup of inactive reviews (30 days)
│   │   ├── output.ex                # Formats review data for API responses
│   │   ├── display_name.ex          # Author display name logic (40-char max)
│   │   ├── integrations.ex          # Integration metadata (editors, AI tools)
│   │   ├── changelog.ex             # GenServer: fetches and caches GitHub releases
│   │   ├── rate_limit.ex            # Hammer-based rate limiting
│   │   ├── release.ex               # Release migration helpers
│   │   ├── config.ex                # Runtime config helpers
│   │   ├── statistics.ex / statistic.ex   # Usage statistics
│   │   ├── accounts.ex + accounts/scope.ex # Phoenix 1.8 scope-based auth
│   │   ├── user.ex / user_api_token.ex     # Authenticated user + CLI bearer tokens
│   │   ├── device_codes.ex / device_code.ex / device_code_cleaner.ex # OAuth device flow
│   │   ├── sentry_filter.ex / sentry_http_client.ex # Sentry plumbing
│   ├── crit_web/
│   │   ├── router.ex                # Routes: marketing, /r/:token, /dashboard, /settings, /overview, /api/*, /api/device/*, /api/auth/*, /auth/cli/*
│   │   ├── endpoint.ex              # Phoenix endpoint
│   │   ├── user_auth.ex             # Auth plug + on_mount hooks; sets current_scope
│   │   ├── controllers/             # page, review, api, auth, oauth, health, device, device_api, auth_api
│   │   ├── live/
│   │   │   ├── review_live.ex       # LiveView for /r/:token
│   │   │   ├── review_live.html.heex # Review page template (uses crit-* CSS classes)
│   │   │   ├── dashboard_live.ex    # User dashboard
│   │   │   ├── settings_live.ex     # User settings
│   │   │   ├── overview_live.ex     # Selfhost admin overview
│   │   │   └── tokens_live.ex       # CLI token management
│   │   ├── components/              # core_components.ex, layouts.ex
│   │   └── plugs/                   # security_headers, rate_limit, api_auth, require_bearer_auth, localhost_cors, canonical_host
│   └── mix/tasks/
│       └── crit.refresh_integrations.ex
├── assets/
│   ├── js/
│   │   ├── app.js                   # Phoenix JS setup + LiveView hooks
│   │   └── document-renderer.js     # Port of crit local's rendering logic
│   └── css/
│       └── app.css                  # Review page CSS (crit-* classes) + Tailwind
├── priv/repo/migrations/
├── config/                          # Dev/test/prod/runtime config
├── test/                            # ExUnit tests
└── .github/workflows/ci.yml         # CI: format, compile, sobelow, audit, test
```

## Key architecture

1. **Review page rendering** — the LiveView loads review data, then `document-renderer.js` (a Phoenix hook) renders the markdown client-side using markdown-it + highlight.js + mermaid. Mirrors `crit` local's rendering.
2. **API for CLI uploads** — `POST /api/reviews` accepts review files + comments + metadata from the CLI's Share button. `PUT /api/reviews/:token` upserts updates and bumps `review_round`. Returns `{url, delete_token}`.
3. **Delete via token** — reviews are deleted by passing the `delete_token` (not auth). The CLI stores this in the review file.
4. **Rate limiting** — Hammer-based via `CritWeb.Plugs.RateLimit`, applied across browser + API pipelines.
5. **Auth + identity** — Phoenix 1.8 scope pattern: `Crit.Accounts.Scope` carries either an authenticated `user` (OAuth or selfhost password) or an anonymous `identity` (session-bound visitor ID), plus a `display_name`. `CritWeb.UserAuth` plug + `on_mount` hooks set `conn.assigns.current_scope` / `socket.assigns.current_scope`. `user` and `identity` are mutually exclusive — see `lib/crit_web/CLAUDE.md` for the full scope contract.
6. **CLI auth** — OAuth device flow (`/api/device/*`, `/auth/cli/*`) issues bearer tokens (`UserApiToken`) used by the CLI. `Plugs.RequireBearerAuth` gates `/api/auth/*`.
7. **Comment threading** — comments support nested replies (`parent_id` self-referential FK) and `resolved` boolean. Comments have `scope` (`"line"` / `"file"` / `"review"`) and an optional `file_path` / `quote`. The review LiveView handles reply CRUD and resolve/unresolve.
8. **Limits**: HTTPS only, `noindex` meta on review/auth pages, **10 MB** total review payload (`@max_total_size` in `reviews.ex`), 50 KB per comment body (`51_200`), 40-char display name, 500-char file path, 64 CLI args x 256 bytes. Reviews expire after 30 days of inactivity (`last_activity_at`). Rate-limit write endpoints per IP.
9. **Stack**: Elixir 1.19.5 / OTP 28.1 / PostgreSQL 17 / Phoenix 1.8.5 / LiveView 1.1. Tailwind v4 (via `@import "tailwindcss" source(none);` in `app.css` — no `tailwind.config.js`). Bandit HTTP server.

<important if="you need to run, build, test, or pre-commit-check crit-web">

```bash
mise run up               # Install deps, setup DB, start server on :4000
mix test                  # Run all tests
mix test path/to/test.exs:42  # One test by line
mix precommit             # compile --warnings-as-errors, deps.unlock --unused, format, sobelow --skip, deps.audit, test
```

Tests use `DataCase` (database) or `ConnCase` (HTTP). Test database: `crit_test`. Local Postgres listens on **5433** (host) → 5432 (container) — pass `DB_PORT=5433` for `mix test` / `mix precommit` (see `../CLAUDE.md`). Always run `mix precommit` when done with a change.

CI runs the same sequence in `.github/workflows/ci.yml` (Postgres 17 service, Elixir 1.19 / OTP 28), with `mix coveralls.json` instead of plain `mix test` for Codecov upload.
</important>

<important if="you need to know the route surface or are adding/modifying a route">

**Marketing / public (browser, indexable):**

- `/` — homepage
- `/features`, `/features/:slug` — feature pages
- `/integrations`, `/integrations/:tool` — integrations
- `/getting-started`, `/self-hosting`, `/changelog` — docs / release notes
- `/terms`, `/privacy` — legal
- `GET /health` — healthcheck (no pipeline)

**Auth (browser):**

- `GET /auth/login` — OAuth provider redirect
- `GET /auth/login/callback` — OAuth callback
- `POST /auth/login` — selfhost password login (legacy)
- `POST /auth/logout`, `DELETE /auth/logout`
- `POST /set-name` — set anonymous display name
- `/auth/cli`, `/auth/cli/authorize` (`GET`/`POST`), `/auth/cli/cancel`, `/auth/cli/success` — CLI OAuth device-flow browser pages (noindex)

**LiveViews (browser, noindex):**

- `/r/:token` — review surface (`live_session :review`)
- `/dashboard`, `/settings` — `live_session :user`, requires authenticated user
- `/overview` — `live_session :admin`, selfhost admin only

**API (`/api`, all noindex):**

- `POST /reviews` — create review (from CLI share)
- `PUT /reviews/:token` — upsert review (bumps `review_round`)
- `DELETE /reviews` — delete review (requires `delete_token`)
- `OPTIONS /reviews` — CORS preflight
- `GET /reviews/:token/document` — review document content
- `GET /reviews/:token/comments` — review comments
- `GET /export/:token/review`, `GET /export/:token/comments` — export

**Device-flow API (`/api/device`, no ApiAuth):**

- `POST /code`, `POST /token` — OAuth device-flow endpoints

**Bearer-auth API (`/api/auth`):**

- `GET /whoami` — current user info
- `DELETE /token` — revoke current bearer token

**Test/dev seeding (`/api/...`, compiled out of prod):** `seed-comment`, `seed-reply`, `seed-user`.
</important>

<important if="you are modifying CSS in app.css or working on a page's styling">

**Review page** (`/r/:token`): Custom CSS only. All styles in `app.css` using `--crit-*` CSS variables and `.crit-*` / `.line-*` / `.comment-*` classes. No Tailwind utilities. Must match `crit` local's look.

**All other pages**: Tailwind utility classes in templates. No custom CSS classes in `app.css`.

Don't:
- Use Tailwind utilities on the review page
- Add component libraries for the review surface
- Add `.home-*` or `.legal-*` CSS classes to `app.css` — use Tailwind in templates
- Use `@apply` when writing raw CSS

See `../CLAUDE.md` for the full parity contract between crit local and crit-web.
</important>

<important if="you are adding or modifying frontend JS in assets/js/">

- `document-renderer.js` uses markdown-it, highlight.js, mermaid — must stay version-aligned with `../crit/package.json`. See `../CLAUDE.md`.
- Only `app.js` and `app.css` bundles are supported — import vendor deps, don't reference external scripts in layouts.
- **Never** write inline `<script>` tags in templates. Use colocated hooks (`:type={Phoenix.LiveView.ColocatedHook}`, name starts with `.`) or external hooks in `assets/js/`.
- **Never** attach listeners via `document.getElementById("x").addEventListener(...)` in `app.js` for elements rendered inside LiveView templates — they break across client-side patches (`<.link navigate={...}>`) because the new DOM node isn't the one you bound to. Use `JS` commands, a hook, or document-level event delegation.
</important>

<important if="you are making HTTP requests from Elixir code">

Use `:req` (`Req`) for HTTP requests. **Avoid** `:httpoison`, `:tesla`, `:httpc`.
</important>

<important if="you are writing or modifying LiveView templates (.heex) or HEEx fragments">

### Phoenix v1.8

- Begin LiveView templates with `<Layouts.app flash={@flash} ...>` — `Layouts` is already aliased in `crit_web.ex`
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>` for icons — never use `Heroicons` modules
- Use `<.input>` from `core_components.ex` for form inputs. Overriding `class=` replaces all default classes
- `<.flash_group>` lives in `layouts.ex` only — never call it elsewhere

### HEEx

- Use `~H` or `.html.heex` — never `~E`
- Use `to_form/2` + `<.form for={@form}>` + `<.input field={@form[:field]}>` — never pass changesets to templates
- Add unique DOM IDs to forms and key elements
- No `if/elsif` in Elixir — use `cond` or `case`
- Use `phx-no-curly-interpolation` on tags containing literal `{`/`}`
- Class lists must use `[...]` syntax: `class={["px-2", @flag && "py-5"]}`
- Use `{...}` for attribute interpolation, `<%= ... %>` for block constructs (`if`, `for`, `cond`) in tag bodies
- Use `<%!-- comment --%>` for HEEx comments
- Use `:for` comprehensions, not `Enum.each`
</important>

<important if="you are writing or modifying LiveView modules (Live*.ex) or LiveView hooks">

- Use `<.link navigate={href}>` / `<.link patch={href}>` — never `live_redirect` / `live_patch`
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
- Use `push_event/3` server→client, `this.pushEvent` client→server
- For UI toggles (popovers, dropdowns, mobile drawers, tabs), prefer `Phoenix.LiveView.JS` commands declaratively in the template — `JS.toggle_attribute({"hidden", "hidden"}, to: "#el")`, `JS.toggle_attribute({"aria-expanded", "true", "false"})`, `JS.toggle/1`. Pipe them together for multi-step toggles
- For behaviors `JS` can't express (click-outside, Escape close, focus traps), use a colocated hook scoped to the element. Hooks have lifecycle (`mounted`/`destroyed`) so listeners clean up on unmount

### LiveView tests

- Use `Phoenix.LiveViewTest` + `LazyHTML` for assertions
- Test with `element/2`, `has_element/2` — never match raw HTML
- Test outcomes, not implementation details
</important>

<important if="you are writing or modifying Ecto queries, schemas, changesets, or migrations">

- Preload associations in queries when accessed in templates
- `Ecto.Schema` uses `:string` type even for `:text` columns
- Use `Ecto.Changeset.get_field/2` to access changeset fields — don't use map access (`changeset[:field]`) on structs
- Don't list programmatic fields (e.g. `user_id`) in `cast` — set them explicitly
- Use `mix ecto.gen.migration` to generate migration files
</important>

<important if="you are writing or modifying any Elixir code in this project">

- Lists don't support index access (`mylist[i]`) — use `Enum.at/2`
- Block expressions (`if`, `case`, `cond`) must bind the result: `socket = if ... do ... end`
- Don't use `String.to_atom/1` on user input (memory leak)
- Use `start_supervised!/1` in tests, avoid `Process.sleep/1`
- Router `scope` blocks auto-prefix the module alias — don't add your own `alias`
- `Phoenix.View` is removed — don't use it
</important>
