defmodule Crit.Accounts.MarketingConsentEvent do
  use Crit.Schema

  schema "marketing_consent_events" do
    belongs_to :user, Crit.User

    field :action, :string
    field :method, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @valid_actions ~w(opted_in opted_out)
  @valid_methods ~w(registration_checkbox settings_toggle dashboard_checkbox)

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:action, :method])
    |> validate_required([:action, :method])
    |> validate_inclusion(:action, @valid_actions)
    |> validate_inclusion(:method, @valid_methods)
    |> foreign_key_constraint(:user_id)
  end
end
