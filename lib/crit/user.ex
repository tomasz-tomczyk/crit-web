defmodule Crit.User do
  use Crit.Schema

  schema "users" do
    field :provider, :string
    field :provider_uid, :string
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :role, Ecto.Enum, values: [:admin, :user], default: :user
    field :keep_reviews, :boolean, default: false
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :current_password, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for users created via OAuth (`provider` + `provider_uid` required). Includes `:name` for first-insert."
  def oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:provider, :provider_uid, :email, :name, :avatar_url])
    |> validate_required([:provider, :provider_uid])
    |> validate_length(:name, max: 80)
    |> downcase_email()
    |> unique_constraint([:provider, :provider_uid])
    |> unique_constraint(:email, name: :users_email_lower_idx)
  end

  @doc """
  Changeset for users updated via OAuth on subsequent logins.

  Excludes `:name` so a user-edited display name is not clobbered by the
  OAuth profile on every login.
  """
  def oauth_update_changeset(user, attrs) do
    user
    |> cast(attrs, [:provider, :provider_uid, :email, :avatar_url])
    |> validate_required([:provider, :provider_uid])
    |> downcase_email()
    |> unique_constraint([:provider, :provider_uid])
    |> unique_constraint(:email, name: :users_email_lower_idx)
  end

  @doc "Changeset for local-auth registration (email + password, optional display name)."
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :name])
    |> validate_email()
    |> validate_password(opts)
    |> validate_length(:name, max: 80)
    |> unique_constraint(:email, name: :users_email_lower_idx)
  end

  @doc """
  Changeset for the combined Profile form (display name + email).

  - `:name` — optional, max 80 chars.
  - `:email` — only validated when present in `attrs` (so a name-only form
    submission is allowed when the email field is hidden, e.g. for OAuth users).
  """
  def profile_changeset(user, attrs) do
    changeset =
      user
      |> cast(attrs, [:name, :email])
      |> validate_length(:name, max: 80)

    if Map.has_key?(attrs, "email") or Map.has_key?(attrs, :email) do
      changeset
      |> validate_email()
      |> unique_constraint(:email, name: :users_email_lower_idx)
    else
      changeset
    end
  end

  @doc "Changeset for changing a user's password."
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc "Changeset for user-controlled settings (e.g. `keep_reviews`)."
  def settings_changeset(user, attrs) do
    user |> cast(attrs, [:keep_reviews])
  end

  @doc """
  Programmatic role-assignment changeset. Used only by
  `Crit.Accounts.apply_role_for_email/1` — `:role` is never user-supplied.
  """
  def role_changeset(user, attrs) do
    user |> cast(attrs, [:role])
  end

  @doc "Verifies a plaintext password against the stored hash."
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc "Validates the current password by adding an error to the changeset if invalid."
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> downcase_email()
  end

  defp downcase_email(changeset) do
    update_change(changeset, :email, fn
      nil -> nil
      e -> String.downcase(e)
    end)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72, count: :bytes)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
