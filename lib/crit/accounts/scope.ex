defmodule Crit.Accounts.Scope do
  alias Crit.User
  alias Crit.Organizations.{Organization, OrganizationMembership}

  defstruct user: nil,
            identity: nil,
            display_name: nil,
            role: nil,
            organization: nil,
            membership: nil

  @type role :: :admin | :user | nil

  @type t :: %__MODULE__{
          user: User.t() | nil,
          identity: String.t() | nil,
          display_name: String.t() | nil,
          role: role(),
          organization: Organization.t() | nil,
          membership: OrganizationMembership.t() | nil
        }

  @doc """
  Build scope from a session map.

  Authenticated → `%Scope{user: %User{}, identity: nil, ...}`.
  Anonymous → `%Scope{user: nil, identity: <session uuid>, ...}`.
  Mutually exclusive — never both set.

  Organization is not hydrated here — it comes from the URL slug via
  `on_mount(:ensure_org)` in LiveView routes.
  """
  def for_session(session) when is_map(session) do
    user =
      case Map.get(session, "user_id") do
        nil ->
          nil

        user_id ->
          case Crit.Accounts.get_user(user_id) do
            {:ok, user} -> user
            {:error, :not_found} -> nil
          end
      end

    case user do
      %User{} = user ->
        for_user(user)

      nil ->
        %__MODULE__{
          user: nil,
          identity: Map.get(session, "identity"),
          display_name: Map.get(session, "display_name")
        }
    end
  end

  @doc "Build scope for an unauthenticated visitor (e.g. tests)."
  def for_visitor(identity, display_name \\ nil) when is_binary(identity) do
    %__MODULE__{user: nil, identity: identity, display_name: display_name}
  end

  @doc "Build scope for an authenticated user."
  def for_user(%User{} = user) do
    %__MODULE__{
      user: user,
      identity: nil,
      display_name: display_name_for(user),
      role: user.role
    }
  end

  def for_user(nil), do: %__MODULE__{}

  @doc "Replace the user (used by SettingsLive after profile update)."
  def put_user(%__MODULE__{} = scope, %User{} = user) do
    %{scope | user: user, display_name: display_name_for(user), role: user.role}
  end

  @doc "Replace the display name (used by anonymous visitors via /set-name)."
  def put_display_name(%__MODULE__{} = scope, name) when is_binary(name) or is_nil(name) do
    %{scope | display_name: name}
  end

  @doc "Attach an organization + membership to the scope."
  def put_organization(
        %__MODULE__{} = scope,
        %Organization{} = org,
        %OrganizationMembership{} = membership
      ) do
    %{scope | organization: org, membership: membership}
  end

  @doc "Returns the user_id, or nil if anonymous."
  def user_id(%__MODULE__{user: nil}), do: nil
  def user_id(%__MODULE__{user: %User{id: id}}), do: id

  @doc "True if the scope has the instance admin role."
  def admin?(%__MODULE__{role: :admin}), do: true
  def admin?(_), do: false

  @doc "True if the current scope is admin of its current organization."
  def org_admin?(%__MODULE__{membership: %OrganizationMembership{role: :admin}}), do: true
  def org_admin?(_), do: false

  @doc "Current organization id, or nil if none is selected."
  def org_id(%__MODULE__{organization: nil}), do: nil
  def org_id(%__MODULE__{organization: %Organization{id: id}}), do: id

  @doc "True if a scope has a currently selected organization."
  def in_org?(%__MODULE__{organization: %Organization{}}), do: true
  def in_org?(_), do: false

  # Public display name. Never falls back to email — comment authors are
  # visible to anyone with the share URL, so leaking an email here would
  # expose private contact info.
  defp display_name_for(%User{name: name}) when is_binary(name) and name != "", do: name
  defp display_name_for(%User{}), do: "User"
end
