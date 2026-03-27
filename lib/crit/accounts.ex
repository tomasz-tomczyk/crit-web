defmodule Crit.Accounts do
  alias Crit.{Repo, User}

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
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end
end
