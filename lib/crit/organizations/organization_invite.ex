defmodule Crit.Organizations.OrganizationInvite do
  use Crit.Schema

  alias Crit.Organizations.Organization
  alias Crit.User

  @invite_ttl_days 7

  schema "organization_invites" do
    belongs_to :organization, Organization
    field :email, :string
    field :token, :binary
    belongs_to :invited_by, User, foreign_key: :invited_by_id
    field :role, Ecto.Enum, values: [:admin, :member], default: :member

    timestamps(type: :utc_datetime)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:organization_id, :email, :role, :invited_by_id])
    |> validate_required([:organization_id, :email, :role, :invited_by_id])
    |> downcase_email()
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint([:organization_id, :email],
      name: :organization_invites_org_email_unique,
      message: "has already been invited"
    )
  end

  def build(org_id, email, invited_by_id, role \\ :member) do
    raw_token = :crypto.strong_rand_bytes(32)
    token_hash = :crypto.hash(:sha256, raw_token)

    {Base.url_encode64(raw_token, padding: false),
     %__MODULE__{
       organization_id: org_id,
       email: String.downcase(email),
       token: token_hash,
       invited_by_id: invited_by_id,
       role: role
     }}
  end

  def verify_token(raw_token) when is_binary(raw_token) do
    case Base.url_decode64(raw_token, padding: false) do
      {:ok, decoded} -> {:ok, :crypto.hash(:sha256, decoded)}
      :error -> :error
    end
  end

  def expired?(%__MODULE__{inserted_at: inserted_at}) do
    expiry = DateTime.add(inserted_at, @invite_ttl_days * 24 * 60 * 60, :second)
    DateTime.compare(DateTime.utc_now(), expiry) == :gt
  end

  def ttl_days, do: @invite_ttl_days

  defp downcase_email(changeset) do
    update_change(changeset, :email, fn
      nil -> nil
      e -> String.downcase(e)
    end)
  end
end
