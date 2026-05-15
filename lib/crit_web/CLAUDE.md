# crit_web — Code-Local Conventions

Targeted rules for code under `lib/crit_web/`. The repo-level guide lives in `../../CLAUDE.md`; this file documents conventions specific to the web layer.

## SEO surface (sitemap + robots)

`/sitemap.xml` and `/robots.txt` are served dynamically by
`PageController` (`sitemap_xml/2`, `robots_txt/2`). The static
list of marketing URLs lives in the `@sitemap_paths` module
attribute on `PageController`.

**When you add, rename, or remove a public URL** (a new feature
page, integration page, marketing route), update `@sitemap_paths`
in the same change. URLs that aren't in the sitemap won't be
crawled, and stale entries cause 404s in Google Search Console.

`Disallow: /r/` is intentionally **not** in `robots.txt` — review
indexability is gated per-review by `<meta name="robots">` driven
from `Review.visibility` in `ReviewLive.mount/3`.

## Scope pattern

Auth and visitor identity flow through `Crit.Accounts.Scope` (Phoenix 1.8 scope pattern). Callers pass a single `%Scope{}` instead of raw `user_id` / `identity` / `display_name` triples.

### 1. Argument-order convention

`%Scope{}` is the **first** argument of every scope-aware function in `Crit.Reviews`.

```elixir
# Good
def create_comment(%Scope{} = scope, %Review{} = review, attrs, opts \\ [])
def create_reply(%Scope{} = scope, comment_id, attrs, review_id)
def resolve_comment(%Scope{} = scope, comment_id, resolved, review_id)
def list_user_reviews_with_counts(%Scope{user: %User{id: id}})
```

The body unpacks scope locally — never pass `scope.user.id` / `scope.identity` from the caller:

```elixir
def create_comment(%Scope{} = scope, %Review{id: review_id}, attrs, _opts) do
  user_id = Scope.user_id(scope)
  identity = scope.identity
  display_name = scope.display_name
  # ...
end
```

### 2. When a function takes scope vs. when it doesn't

| Takes scope (✅)                                        | Does not (❌)                                  |
| ------------------------------------------------------- | --------------------------------------------- |
| Attribution-bearing mutations (`create_comment/4`, `create_reply/4`) | Token-authed entry points (CLI device flow, share API) |
| Owner-checked mutations (`resolve_comment/4`, `update_review_name/3`) | Pure data transforms (`Output.format/1`, formatters) |
| Subject-driven reads (`list_user_reviews_with_counts/1`) | Internal/admin batch jobs (`ReviewCleaner`)   |
| LiveView mounts/handlers that act on behalf of the visitor | Lookups by external token (`get_by_token/1`)  |

If the function depends on **who is acting**, it takes scope. If it acts on a token, an admin job, or pure data, it doesn't.

### 3. The display_name rule

Public review pages are share-URL-readable. Emails must never appear there.

`Scope` builds `display_name` from `User.name` or the literal `"User"` — never the email. The fallback lives inside `Scope` (private `display_name_for/1`); call sites just read `scope.display_name`.

```heex
<%!-- ✅ public review page --%>
<span class="crit-user-name">{@current_scope.display_name}</span>

<%!-- ❌ never on the review page --%>
<span>{@current_scope.user.name || @current_scope.user.email}</span>
```

Layouts and the settings page (which serve authenticated users their own info behind auth) may show `@current_scope.user.email`. The review page may not.

### 4. Mutual exclusion invariant

`scope.user` and `scope.identity` are mutually exclusive. Never both set.

- `Scope.for_session/1` resolves `user_id` first; if a user is found, identity is dropped.
- `Scope.for_user/1` zeroes identity.
- `Scope.for_visitor/2` only sets identity.

Always construct scopes via these public constructors. Never `%Scope{user: ..., identity: ...}` directly — bypassing the constructors lets you build illegal states.

### 5. Authorising a mutation: `resolve_comment` as the worked example

A gated mutation looks up the row, then matches scope against the row's owner fields:

```elixir
defp check_resolve_permission(%Scope{} = scope, comment_id, review_id) do
  case Repo.one(query_for(comment_id, review_id)) do
    nil -> {:error, :not_found}
    %{parent_id: parent} when parent != nil -> {:error, :not_found}
    %{comment_user_id: cuid, comment_identity: cident, review_user_id: ruid} ->
      scope_uid = Scope.user_id(scope)

      cond do
        scope_uid != nil and scope_uid == ruid -> :ok            # review owner
        scope_uid != nil and scope_uid == cuid -> :ok            # comment author (auth)
        cuid == nil and scope.identity != nil and scope.identity == cident -> :ok  # comment author (anon)
        true -> {:error, :unauthorized}
      end
  end
end
```

New gated mutations follow the same shape: query the row, match the scope, return `{:error, :unauthorized}` on miss. The caller pattern-matches on `{:error, :unauthorized}` and renders 403.

### 6. Migration path for new code

Decision tree for a new context function:

> Does it depend on who is acting (auth or anon identity)? → scope-first.
> Otherwise → leave the signature alone.

```elixir
# New scope-aware function
def archive_review(%Scope{} = scope, review_id) do
  with :ok <- check_owner(scope, review_id) do
    # ...
  end
end

# Token-authed, no scope
def get_by_token(token), do: Repo.get_by(Review, token: token) |> Repo.preload(...)
```

In LiveViews and controllers, get scope from `socket.assigns.current_scope` or `conn.assigns.current_scope` — set by `CritWeb.UserAuth` plug / `on_mount` hook. Don't construct scopes ad-hoc in handlers.

### 7. Don't reintroduce

- `assign(:current_user, ...)` in LiveView — use `:current_scope` (the user-auth on_mount sets it).
- `get_session(conn, "identity")` outside `CritWeb.UserAuth` — read `conn.assigns.current_scope.identity`.
- `user.name || user.email` in any template served by the public review surface.
- Raw `Reviews.<func>(id, body, identity, display_name, ...)` threading — pass `scope` instead.
- Direct `%Scope{user: ..., identity: ...}` construction — use `for_user/1`, `for_session/1`, `for_visitor/2`.
- `Crit.Repo.*` calls in LiveViews or controllers — always go through a context function.
- `raise "not authorized"` in context functions — return `{:error, :unauthorized}` instead.
- `throw/catch` for access control in `mount/3` — use an `on_mount` hook in the router.
- `GET` routes that write to session — session-mutating endpoints must be `POST`-only (CSRF risk).
- `redirect` for same-app LiveView navigation — use `push_navigate` unless the destination is a controller action that writes session.

## Organizations & multi-tenancy

These patterns apply anywhere code is org-scoped (i.e., depends on `scope.organization`).

### Authorization in context functions

Every function that requires org-admin access uses a private `check_org_admin/1` and returns `{:error, :unauthorized}` — never `raise`:

```elixir
defp check_org_admin(scope) do
  if Scope.org_admin?(scope), do: :ok, else: {:error, :unauthorized}
end

def update_something(%Scope{} = scope, resource, attrs) do
  with :ok <- check_org_admin(scope),
       :ok <- check_belongs_to_org(scope, resource) do
    # ...
  end
end
```

### Cross-tenant guard

Every context function that accepts a resource by id must verify `resource.organization_id == Scope.org_id(scope)` before acting. Skipping this lets an admin of org A manipulate resources belonging to org B.

```elixir
defp check_belongs_to_org(scope, resource) do
  if resource.organization_id == Scope.org_id(scope), do: :ok, else: {:error, :unauthorized}
end
```

### Scope helpers

Use these helpers — never pattern-match on `scope.membership.role` or `scope.organization` directly:

| Helper | Returns |
|--------|---------|
| `Scope.org_admin?(scope)` | `true` when membership role is `"admin"` |
| `Scope.in_org?(scope)` | `true` when `scope.organization` is set |
| `Scope.org_id(scope)` | org id string or `nil` |

### Access control via `on_mount`, not `mount`

Use dedicated `on_mount` hooks for route-level guards. Don't `throw/catch` inside `mount/3`.

```elixir
# In user_auth.ex — define once
def on_mount(:require_org_admin, _params, _session, socket) do
  if Crit.Accounts.Scope.org_admin?(socket.assigns.current_scope) do
    {:cont, socket}
  else
    slug = socket.assigns.current_scope.organization.slug
    {:halt, socket |> put_flash(:error, "Admin access required.") |> redirect(to: "/orgs/#{slug}/members")}
  end
end

# In router.ex — compose on_mounts
live_session :org_admin,
  on_mount: [
    {CritWeb.UserAuth, :require_authenticated_user},
    {CritWeb.UserAuth, :ensure_org},
    {CritWeb.UserAuth, :require_org_admin}
  ], ... do
  live "/orgs/:org_slug/invites", OrgInvitesLive, :index
end
```

### Review visibility matrix

Reviews may optionally belong to an organization (`organization_id`). Visibility controls who can access:

| `organization_id` | `visibility` | Shown in org views | Who can access |
|---|---|---|---|
| set | `:organization` | yes | org members only |
| set | `:unlisted` | no | org members only (direct link) |
| set | `:public` | yes | anyone |
| nil | `:unlisted` | N/A | anyone with the link |
| nil | `:public` | N/A | anyone |
| nil | `:organization` | N/A | **nobody** (orphaned — org was deleted) |

The `organization_id` acts as an access boundary. When set, both `:organization` and `:unlisted` require org membership. The difference is discoverability (whether it appears in org review listings).

**Orphaned reviews**: when an org is deleted, `on_delete: :nilify_all` sets `organization_id` to nil but `visibility` stays `:organization`. These become inaccessible — `Reviews.check_org_access/2` rejects them.

### Review org access checks — all paths

Org membership for reviews must be checked on **every access path**, not just the LiveView mount:

| Path | Where the check lives |
|---|---|
| LiveView `/r/:token` | `ReviewLive.mount_review/4` via `Reviews.check_org_access/2` |
| Unauthenticated gate | `UserAuth.check_org_visibility_gate/1` (redirects to login) |
| API `GET /api/reviews/:token/*` | `ApiController` — `Reviews.check_org_access/2` in each action |
| Raw `GET /r/:token/raw/*` | `RawController.show/2` — `Reviews.check_org_access/2` |

When adding a new endpoint that reads review content by token, it **must** call `Reviews.check_org_access(review, scope)` before returning data.

### Review lifecycle on user deletion

When a user deletes their account:
- **Personal reviews** (no `organization_id`): cascade-deleted with the user.
- **Org-scoped reviews**: `user_id` is nilified before deletion so the review survives under the org. The org retains the content; authorship attribution is lost.

This is handled in `Accounts.delete_user/1`. Don't change the `ON DELETE CASCADE` FK — the nilification happens in application code before the delete.

### Session writes must be POST-only

Any route that calls `put_session` must be `POST` (or `DELETE`). A `GET` route that writes session is CSRF-exploitable via `<img src>` or a plain link. Templates that trigger session-writing actions use `<.form method="post">` with CSRF token, not plain `<.link href>`.

### `push_navigate` vs `redirect` in LiveView handlers

| Destination | Use |
|---|---|
| Another LiveView route | `push_navigate(socket, to: ~p"/...")` |
| Controller action that writes session | `redirect(socket, to: ~p"/...")` |

`redirect` does a full-page reload; `push_navigate` keeps the LiveView socket alive.
