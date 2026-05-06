defmodule Crit.Accounts do
  @moduledoc """
  Accounts context.

  Note: the admin-role plan will later add a call to `apply_role_for_email/1`
  inside `register_user/1` to assign roles based on email at registration time.
  """

  import Ecto.Query

  alias Crit.{Repo, User, UserApiToken}
  alias Crit.Accounts.{UserToken, UserNotifier}

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
  Updates name, email, and avatar_url on each login.

  `oauth_params` is the normalized user map from assent:
    "sub" => provider UID, "name", "email", "picture"
  """
  def find_or_create_from_oauth(provider, oauth_params) do
    provider_uid = oauth_params["sub"]

    attrs = %{
      provider: provider,
      provider_uid: provider_uid,
      name: oauth_params["name"],
      email: oauth_params["email"],
      avatar_url: oauth_params["picture"]
    }

    if is_nil(provider_uid) do
      %User{} |> User.oauth_changeset(attrs) |> Repo.insert()
    else
      case Repo.get_by(User, provider: provider, provider_uid: provider_uid) do
        nil ->
          %User{}
          |> User.oauth_changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> User.oauth_changeset(attrs)
          |> Repo.update()
      end
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

  @doc """
  Generates a reset token and emails it. `url_fun` is a 1-arity function from
  plaintext token → URL string (the LiveView/controller knows how to build
  the URL from the endpoint).
  """
  def deliver_user_reset_password_instructions(%User{} = user, url_fun) when is_function(url_fun, 1) do
    {plaintext, struct} = UserToken.build_hashed_token(user, "reset_password", user.email)
    Repo.insert!(struct)
    UserNotifier.deliver_reset_password_instructions(user, url_fun.(plaintext))
  end

  @doc "Looks up a user by reset token. Returns user or nil."
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user's password and deletes all of their reset / remember-me
  tokens. Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def reset_user_password(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["reset_password", "remember_me"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Changeset for change-email form."
  def change_user_email(%User{} = user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
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

  @doc "Sends a change-email confirmation link to the proposed new address."
  def deliver_update_email_instructions(%User{} = user, new_email, url_fun) when is_function(url_fun, 1) do
    {plaintext, struct} = UserToken.build_hashed_token(user, "change_email", new_email)
    Repo.insert!(struct)
    UserNotifier.deliver_update_email_instructions(%{user | email: new_email}, url_fun.(plaintext))
  end

  @doc """
  Applies a previously-issued change-email token. Looks up the token row
  directly (we need both `user_id` and `sent_to` — `verify_token_query/2`
  returns only the user). Validates that the token's user matches the
  caller's user, then swaps email and burns all `change_email` tokens for
  this user.
  """
  def update_user_email(%User{} = user, token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         hashed = :crypto.hash(:sha256, decoded),
         %UserToken{user_id: uid, sent_to: new_email} <-
           Repo.one(
             from t in UserToken,
               where:
                 t.token == ^hashed and t.context == "change_email" and
                   t.inserted_at > ago(7, "day")
           ),
         true <- uid == user.id do
      Ecto.Multi.new()
      |> Ecto.Multi.update(:user, User.email_changeset(user, %{email: new_email}))
      |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["change_email"]))
      |> Repo.transaction()
      |> case do
        {:ok, %{user: u}} -> {:ok, u}
        {:error, :user, cs, _} -> {:error, cs}
      end
    else
      _ -> :error
    end
  end
end
