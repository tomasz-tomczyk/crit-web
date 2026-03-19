defmodule Crit.Integrations do
  @moduledoc """
  Fetches and caches integration snippets from GitHub for display on /integrations.

  Refreshes every hour. Reads from an ETS table for fast access.
  """

  use GenServer

  require Logger

  @table :integration_snippets
  @refresh_interval :timer.hours(1)

  @github_base "https://raw.githubusercontent.com/tomasz-tomczyk/crit/main/integrations/"

  @meta [
    %{
      id: "claude-code",
      name: "Claude Code",
      file_path: ".claude/commands/crit.md",
      source: "claude-code/commands/crit.md",
      description:
        "Add the /crit slash command. It launches Crit, reads your comments, and revises the output automatically.",
      secondary_label: "Skill (recommended)",
      secondary_file_path: ".claude/skills/crit-cli/SKILL.md",
      secondary_source: "claude-code/skills/crit-cli/SKILL.md"
    },
    %{
      id: "cursor",
      name: "Cursor",
      file_path: ".cursor/commands/crit.md",
      source: "cursor/commands/crit.md",
      description:
        "Add the /crit slash command. It launches Crit, reads your comments, and revises the output automatically.",
      secondary_label: "Skill (recommended)",
      secondary_file_path: ".cursor/skills/crit-cli/SKILL.md",
      secondary_source: "cursor/skills/crit-cli/SKILL.md"
    },
    %{
      id: "github-copilot",
      name: "GitHub Copilot",
      file_path: ".github/prompts/crit.prompt.md",
      source: "github-copilot/commands/crit.prompt.md",
      description:
        "Add the /crit slash command. It launches Crit, reads your comments, and revises the output automatically.",
      secondary_label: "Skill (recommended)",
      secondary_file_path: ".github/skills/crit-cli/SKILL.md",
      secondary_source: "github-copilot/skills/crit-cli/SKILL.md"
    },
    %{
      id: "opencode",
      name: "OpenCode",
      file_path: ".opencode/agents/crit.md",
      source: "opencode/crit.md",
      description:
        "Add a Crit agent. It launches Crit, reads your comments, and revises the output automatically.",
      secondary_label: "Skill (recommended)",
      secondary_file_path: ".opencode/skills/crit-cli/SKILL.md",
      secondary_source: "opencode/SKILL.md"
    },
    %{
      id: "windsurf",
      name: "Windsurf",
      file_path: ".windsurf/rules/crit.md",
      source: "windsurf/crit.md",
      description:
        "Add a Windsurf rule that teaches the agent to use Crit for reviewing plans and code changes."
    },
    %{
      id: "aider",
      name: "Aider",
      file_path: "CONVENTIONS.md",
      source: "aider/CONVENTIONS.md",
      description:
        "Append to your Aider conventions file to teach the agent to use Crit for reviewing plans and code changes."
    },
    %{
      id: "cline",
      name: "Cline",
      file_path: ".clinerules/crit.md",
      source: "cline/crit.md",
      description:
        "Add a Cline rule that teaches the agent to use Crit for reviewing plans and code changes."
    }
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns cached integrations with their snippets."
  def list do
    case :ets.lookup(@table, :integrations) do
      [{:integrations, integrations}] -> integrations
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :protected, read_concurrency: true])
    integrations = fetch_all()
    :ets.insert(table, {:integrations, integrations})
    schedule_refresh()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    integrations = fetch_all()
    :ets.insert(@table, {:integrations, integrations})
    schedule_refresh()
    {:noreply, state}
  end

  defp fetch_all do
    Enum.map(@meta, fn meta ->
      snippet = fetch_snippet(meta.source)

      meta
      |> Map.put(:snippet, snippet)
      |> maybe_add_secondary()
    end)
  end

  defp maybe_add_secondary(%{secondary_source: source} = meta) do
    Map.put(meta, :secondary_snippet, fetch_snippet(source))
  end

  defp maybe_add_secondary(meta), do: meta

  defp fetch_snippet(source_path) do
    url = @github_base <> source_path

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        body

      {:ok, %{status: status}} ->
        Logger.warning("[Integrations] GitHub returned #{status} for #{source_path}")
        ""

      {:error, reason} ->
        Logger.warning("[Integrations] Failed to fetch #{source_path}: #{inspect(reason)}")
        ""
    end
  end

  defp schedule_refresh do
    interval = Application.get_env(:crit, :integrations_refresh_interval_ms, @refresh_interval)
    Process.send_after(self(), :refresh, interval)
  end
end
