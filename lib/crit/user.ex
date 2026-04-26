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
end
