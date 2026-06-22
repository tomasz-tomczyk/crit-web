defmodule Crit.GithubStars do
  @moduledoc """
  Fetches and caches the GitHub star count for the Crit CLI repo.

  Refreshes every hour. Reads from an ETS table for fast access.
  """

  use GenServer

  require Logger

  @table :github_stars
  @refresh_interval :timer.hours(1)
  @repo "tomasz-tomczyk/crit"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the cached star count, or nil if unavailable."
  def count do
    case :ets.lookup(@table, :count) do
      [{:count, count}] -> count
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Formats a star count for display in the UI."
  def format_count(count) when is_integer(count) and count >= 0 do
    count
    |> Integer.to_string()
    |> add_thousands_separator()
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :protected, read_concurrency: true])
    count = fetch_star_count()
    :ets.insert(table, {:count, count})
    schedule_refresh()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    count = fetch_star_count()
    :ets.insert(@table, {:count, count})
    schedule_refresh()
    {:noreply, state}
  end

  defp fetch_star_count do
    url = "https://api.github.com/repos/#{@repo}"

    case Req.get(url, headers: [{"accept", "application/vnd.github+json"}]) do
      {:ok, %{status: 200, body: %{"stargazers_count" => count}}} when is_integer(count) ->
        count

      {:ok, %{status: status}} ->
        Logger.warning("[GithubStars] GitHub API returned #{status} for #{@repo}")
        nil

      {:error, reason} ->
        Logger.warning("[GithubStars] Failed to fetch stars for #{@repo}: #{inspect(reason)}")
        nil
    end
  end

  defp add_thousands_separator(digits) do
    digits
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.join(",")
  end

  defp schedule_refresh do
    interval = Application.get_env(:crit, :github_stars_refresh_interval_ms, @refresh_interval)
    Process.send_after(self(), :refresh, interval)
  end
end
