defmodule Crit.Accounts.MarketingConsentEvent do
  use Crit.Schema

  schema "marketing_consent_events" do
    belongs_to :user, Crit.User

    field :action, Ecto.Enum, values: [:opted_in, :opted_out, :subscription_requested]

    field :method, Ecto.Enum,
      values: [
        :registration_checkbox,
        :settings_toggle,
        :dashboard_checkbox,
        :newsletter_form,
        :newsletter_confirmation,
        :newsletter_unsubscribe
      ]

    field :email, :string
    field :source, Ecto.Enum, values: [:homepage, :archive, :footer]
    field :source_path, :string
    field :confirmation_nonce, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:action, :method])
    |> validate_required([:action, :method])
    |> foreign_key_constraint(:user_id)
  end

  def newsletter_changeset(event, attrs) do
    event
    |> change(source: event.source || :archive)
    |> cast(attrs, [:email, :source, :source_path])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> put_change(:action, :subscription_requested)
    |> put_change(:method, :newsletter_form)
    |> validate_required([:email, :source])
    |> validate_length(:email, max: 160)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:source_path, max: 512)
    |> validate_format(:source_path, ~r{^/(?!/)[^?#\s]*$}, message: "must be a page path")
  end
end
