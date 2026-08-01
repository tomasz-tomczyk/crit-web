defmodule Crit.Settings do
  @moduledoc """
  Context for the singleton instance settings row.

  Reads happen on every consumer call — single-row Postgres lookup is sub-ms.
  Caching is a future optimisation if profiles show contention.
  """

  alias Crit.{Repo, Setting}

  @singleton_id 1
  @default_comment_policy :open
  @default_visibility :unlisted
  @personal_visibilities [:unlisted, :public]

  @doc """
  Returns the singleton settings row. Raises if missing — the migration
  seeds id=1 so this should never fail in a normally-migrated DB.
  """
  def get do
    Repo.get!(Setting, @singleton_id)
  end

  @doc """
  Updates the singleton settings row.

  Returns `{:ok, setting}` or `{:error, changeset}`.
  """
  def update(attrs) do
    get()
    |> Setting.changeset(attrs)
    |> Repo.update()
  end

  @doc "Changeset for forms (no DB write)."
  def change(setting \\ get(), attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  @doc "Returns share policy allow-lists for clients that expose share options."
  def share_policy(setting \\ get()) do
    %{
      allowed_comment_policies: setting.allowed_comment_policies,
      allowed_review_visibilities: setting.allowed_review_visibilities
    }
  end

  def comment_policy_allowed?(policy, setting \\ get()) do
    policy = normalize_comment_policy(policy)
    not is_nil(policy) and policy in setting.allowed_comment_policies
  end

  def visibility_allowed?(visibility, setting \\ get()) do
    visibility = normalize_visibility(visibility)
    not is_nil(visibility) and visibility in setting.allowed_review_visibilities
  end

  def default_comment_policy(setting \\ get()) do
    if @default_comment_policy in setting.allowed_comment_policies do
      @default_comment_policy
    else
      List.first(setting.allowed_comment_policies)
    end
  end

  def default_visibility(setting \\ get()) do
    personal_allowed =
      Enum.filter(setting.allowed_review_visibilities, &(&1 in @personal_visibilities))

    if @default_visibility in personal_allowed do
      @default_visibility
    else
      List.first(personal_allowed)
    end
  end

  def normalize_comment_policy(policy) when policy in [:open, :logged_in_only, :disallowed],
    do: policy

  def normalize_comment_policy("open"), do: :open
  def normalize_comment_policy("logged_in_only"), do: :logged_in_only
  def normalize_comment_policy("disallowed"), do: :disallowed
  def normalize_comment_policy(_), do: nil

  def normalize_visibility(visibility) when visibility in [:unlisted, :public, :organization],
    do: visibility

  def normalize_visibility("unlisted"), do: :unlisted
  def normalize_visibility("public"), do: :public
  def normalize_visibility("organization"), do: :organization
  def normalize_visibility(_), do: nil

  @doc """
  Returns true when the mailer can deliver email for notifications.

  True for `Swoosh.Adapters.Local` (dev mailbox) and `Swoosh.Adapters.Test`,
  or for `Swoosh.Adapters.SMTP` when `SMTP_HOST` and `SMTP_FROM` are set.
  """
  def mailer_configured? do
    case Keyword.get(Application.get_env(:crit, Crit.Mailer, []), :adapter) do
      Swoosh.Adapters.Local -> true
      Swoosh.Adapters.Test -> true
      Swoosh.Adapters.SMTP -> smtp_env_configured?()
      _ -> false
    end
  end

  defp smtp_env_configured? do
    present_env?("SMTP_HOST") and present_env?("SMTP_FROM")
  end

  defp present_env?(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end
end
