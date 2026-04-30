# crit_web — Code-Local Conventions

Targeted rules for code under `lib/crit_web/`. The repo-level guide lives in `../../CLAUDE.md`; this file documents conventions specific to the web layer.

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
