defmodule Crit.User do
  use Crit.Schema

  schema "users" do
    field :provider, :string
    field :provider_uid, :string
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :keep_reviews, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:provider, :provider_uid, :email, :name, :avatar_url])
    |> validate_required([:provider, :provider_uid])
    |> unique_constraint([:provider, :provider_uid])
  end

  @doc "Changeset for user-controlled settings (e.g. keep_reviews)."
  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:keep_reviews])
  end

  @email_re ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @doc """
  Changeset for users created from a trusted SSO reverse-proxy header.
  Uses `provider="trusted_proxy"` and `provider_uid=email` (lowercased) so
  the existing `(provider, provider_uid)` unique index doubles as a uniqueness
  constraint on email for these users.
  """
  def trusted_proxy_changeset(user, %{email: email}) when is_binary(email) do
    name = default_name_from_email(email)

    user
    |> cast(%{email: email, name: name}, [:email, :name])
    |> put_change(:provider, "trusted_proxy")
    |> put_change(:provider_uid, email)
    |> validate_required([:email])
    |> validate_format(:email, @email_re)
    |> validate_length(:email, max: 320)
    |> unique_constraint([:provider, :provider_uid])
  end

  def trusted_proxy_changeset(user, _attrs) do
    user
    |> cast(%{}, [])
    |> add_error(:email, "can't be blank")
  end

  defp default_name_from_email(email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
  end
end
