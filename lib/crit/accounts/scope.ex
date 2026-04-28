defmodule Crit.Accounts.Scope do
  alias Crit.User

  defstruct user: nil, identity: nil, display_name: nil

  @type t :: %__MODULE__{
          user: User.t() | nil,
          identity: String.t() | nil,
          display_name: String.t() | nil
        }

  @doc """
  Build scope from a session map.

  Authenticated → `%Scope{user: %User{}, identity: nil, ...}`.
  Anonymous → `%Scope{user: nil, identity: <session uuid>, ...}`.
  Mutually exclusive — never both set.
  """
  def for_session(session) when is_map(session) do
    case load_user(Map.get(session, "user_id")) do
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
    %__MODULE__{user: user, identity: nil, display_name: display_name_for(user)}
  end

  def for_user(nil), do: %__MODULE__{}

  @doc "Replace the user (used by SettingsLive after profile update)."
  def put_user(%__MODULE__{} = scope, %User{} = user) do
    %{scope | user: user, display_name: display_name_for(user)}
  end

  @doc "Replace the display name (used by anonymous visitors via /set-name)."
  def put_display_name(%__MODULE__{} = scope, name) when is_binary(name) or is_nil(name) do
    %{scope | display_name: name}
  end

  @doc "Returns the user_id, or nil if anonymous."
  def user_id(%__MODULE__{user: nil}), do: nil
  def user_id(%__MODULE__{user: %User{id: id}}), do: id

  # Public display name. Never falls back to email — comment authors are
  # visible to anyone with the share URL, so leaking an email here would
  # expose private contact info.
  defp display_name_for(%User{name: name}) when is_binary(name) and name != "", do: name
  defp display_name_for(%User{}), do: "User"

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Crit.Accounts.get_user(user_id) do
      {:ok, user} -> user
      {:error, :not_found} -> nil
    end
  end
end
