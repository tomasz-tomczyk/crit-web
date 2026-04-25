defmodule Crit.Accounts do
  import Ecto.Query

  alias Crit.{Repo, User, UserApiToken}

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
      %User{} |> User.changeset(attrs) |> Repo.insert()
    else
      case Repo.get_by(User, provider: provider, provider_uid: provider_uid) do
        nil ->
          %User{}
          |> User.changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> User.changeset(attrs)
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
    |> Ecto.Changeset.change(keep_reviews: keep_reviews)
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
end
