defmodule Crit.DeviceCode do
  use Crit.Schema

  schema "device_codes" do
    field :device_code, :string
    field :session_code, :string
    field :status, Ecto.Enum, values: [:pending, :authorized, :redeemed], default: :pending
    field :access_token, :string
    field :last_polled_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :user, Crit.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(device_code, attrs) do
    device_code
    |> cast(attrs, [:device_code, :session_code, :status, :expires_at])
    |> validate_required([:device_code, :session_code, :status, :expires_at])
    |> unique_constraint(:device_code)
    |> unique_constraint(:session_code, name: :device_codes_session_code_pending_index)
  end
end
