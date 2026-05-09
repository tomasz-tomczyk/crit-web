defmodule Crit.Accounts do
  @moduledoc """
  Accounts context.

  Note: the admin-role plan will later add a call to `apply_role_for_email/1`
  inside `register_user/1` to assign roles based on email at registration time.
  """

  import Ecto.Query

  alias Crit.{Repo, User, UserApiToken}
  alias Crit.Accounts.UserToken

  @doc """
  Registers a user with email + password.

  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for tracking user registration changes (e.g. for LiveView forms).

  The password is not hashed here.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Gets a user by email (case-insensitive). Returns the user or nil.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.one(from u in User, where: fragment("lower(?)", u.email) == ^String.downcase(email))
  end

  @doc """
  Gets a user by email and password.

  Returns the user if the password is valid, otherwise nil.

  Calls `User.valid_password?/2` even when no user is found, to keep timing
  approximately constant against email-enumeration attacks.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user || %User{}, password), do: user
  end

  @doc """
  Finds an existing user by provider + provider_uid, or creates one.

  On first insert, the user's `:name` is taken from the OAuth profile.
  On subsequent logins (existing user matched by provider+UID, or by email
  for the email-link branch), only `:email`, `:avatar_url`, `:provider`,
  and `:provider_uid` are updated — `:name` is preserved so user edits in
  settings aren't clobbered.

  `oauth_params` is the normalized user map from assent:
    "sub" => provider UID, "name", "email", "picture"
  """
  def find_or_create_from_oauth(provider, oauth_params) do
    provider_uid = oauth_params["sub"]

    insert_attrs = %{
      provider: provider,
      provider_uid: provider_uid,
      name: oauth_params["name"],
      email: oauth_params["email"],
      avatar_url: oauth_params["picture"]
    }

    update_attrs = Map.delete(insert_attrs, :name)

    cond do
      is_nil(provider_uid) ->
        %User{} |> User.oauth_changeset(insert_attrs) |> Repo.insert()

      existing = Repo.get_by(User, provider: provider, provider_uid: provider_uid) ->
        existing |> User.oauth_update_changeset(update_attrs) |> Repo.update()

      existing = insert_attrs.email && get_user_by_email(insert_attrs.email) ->
        existing |> User.oauth_update_changeset(update_attrs) |> Repo.update()

      true ->
        %User{} |> User.oauth_changeset(insert_attrs) |> Repo.insert()
    end
  end

  @doc """
  Fetches a user from a plaintext remember-me cookie token.

  Hashes the plaintext, joins `users_tokens` to `users`, filters by the
  `"remember_me"` context and 60-day TTL. Returns `{:ok, user}` on hit,
  `{:error, :not_found}` otherwise (including malformed tokens).
  """
  def get_user_by_remember_me_token(plaintext) when is_binary(plaintext) do
    case UserToken.verify_token_query(plaintext, "remember_me") do
      {:ok, query} ->
        case Repo.one(query) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "Fetches a user by primary key. Returns {:ok, user} or {:error, :not_found}."
  def get_user(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      case Repo.get(User, uuid) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Creates a new API token for the given user with the given name.
  Returns `{:ok, {plaintext_token, token_record}}` or `{:error, changeset}`.
  """
  def create_token(user, name) do
    plaintext = "crit_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    token_hash = Base.url_encode64(:crypto.hash(:sha256, plaintext), padding: false)

    changeset =
      %UserApiToken{}
      |> UserApiToken.changeset(%{name: name, token_hash: token_hash})
      |> Ecto.Changeset.put_assoc(:user, user)

    case Repo.insert(changeset) do
      {:ok, token} -> {:ok, {plaintext, token}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Verifies a plaintext token. If valid, updates last_used_at and returns `{:ok, user}`.
  Returns `{:error, :invalid}` if not found.
  """
  def verify_token(plaintext) do
    token_hash = Base.url_encode64(:crypto.hash(:sha256, plaintext), padding: false)

    case Repo.get_by(UserApiToken, token_hash: token_hash) |> Repo.preload(:user) do
      nil ->
        {:error, :invalid}

      token ->
        token
        |> Ecto.Changeset.change(last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
        |> Repo.update!()

        {:ok, token.user}
    end
  end

  @doc """
  Revokes a token by id, only if it belongs to the given user.
  Returns `:ok` or `{:error, :not_found}`.
  """
  def revoke_token(token_id, user_id) do
    case Repo.get_by(UserApiToken, id: token_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      token ->
        case Repo.delete(token) do
          {:ok, _token} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Revokes a token by its plaintext value.
  Returns `:ok` regardless of whether the token existed (idempotent).
  """
  def revoke_token_by_plaintext(plaintext) do
    token_hash = Base.url_encode64(:crypto.hash(:sha256, plaintext), padding: false)

    case Repo.get_by(UserApiToken, token_hash: token_hash) do
      nil -> :ok
      record -> Repo.delete(record)
    end

    :ok
  end

  @doc """
  Returns all API tokens for the given user, ordered by inserted_at desc.
  """
  def list_tokens(user_id) do
    Repo.all(
      from t in UserApiToken,
        where: t.user_id == ^user_id,
        order_by: [desc: t.inserted_at]
    )
  end

  @doc """
  Updates the keep_reviews setting for a user.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def update_keep_reviews(%User{} = user, keep_reviews) when is_boolean(keep_reviews) do
    user
    |> User.settings_changeset(%{keep_reviews: keep_reviews})
    |> Repo.update()
  end

  @doc """
  Deletes a user account. PostgreSQL cascade handles:
  - API tokens (deleted)
  - Device codes (deleted)
  - Reviews (user_id set to nil, reviews preserved)

  Returns `:ok` or `{:error, :not_found}`.
  """
  def delete_account(%User{id: id}) do
    case Repo.get(User, id) do
      nil ->
        {:error, :not_found}

      user ->
        case Repo.delete(user) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :delete_failed}
        end
    end
  end

  @doc "Changeset for change-password form (validates current_password)."
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Validates current password and applies the change-password update. Deletes
  all `remember_me` tokens for the user (forces re-login on other devices).
  """
  def update_user_password(%User{} = user, current_password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(current_password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["remember_me"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: u}} -> {:ok, u}
      {:error, :user, cs, _} -> {:error, cs}
    end
  end

  @doc "Changeset for the combined profile form (display name + email)."
  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates a user's profile (display name and optionally email) atomically.

  Email is only cast/validated when the `"email"` key is present in `attrs`,
  so the form may submit name-only when the email field is hidden (OAuth users).

  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end
end
