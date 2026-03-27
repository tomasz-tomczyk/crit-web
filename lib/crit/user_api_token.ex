defmodule Crit.UserApiToken do
  use Crit.Schema

  schema "user_api_tokens" do
    field :name, :string
    field :token_hash, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, Crit.User

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash])
    |> validate_required([:name, :token_hash])
  end
end
