defmodule Crit.Changelog do
  @moduledoc """
  Fetches and caches GitHub releases for display on /changelog.

  Refreshes every hour. Reads from an ETS table for fast access.
  """

  use GenServer

  require Logger

  @table :changelog_releases
  @refresh_interval :timer.hours(1)

  @repos [
    {:cli, "tomasz-tomczyk/crit"},
    {:web, "tomasz-tomczyk/crit-web"}
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns cached releases sorted by published_at descending."
  def list_releases do
    case :ets.lookup(@table, :releases) do
      [{:releases, releases}] -> releases
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  @doc "Parses a single GitHub release API response. Returns a map or :skip."
  def parse_release(%{"draft" => true}, _source), do: :skip
  def parse_release(%{"prerelease" => true}, _source), do: :skip

  @excluded_contributors ["tomasz-tomczyk"]

  def parse_release(release, source) do
    {:ok, published_at, _} = DateTime.from_iso8601(release["published_at"])
    raw_body = release["body"] || ""
    contributors = extract_contributors(raw_body)
    cleaned_body = strip_contributors_section(raw_body)

    body_html =
      case Earmark.as_html(cleaned_body) do
        {:ok, html, _} -> sanitize_html(html)
        {:error, _, _} -> "<p>#{cleaned_body}</p>"
      end

    %{
      version: release["tag_name"],
      name: release["name"] || release["tag_name"],
      body_html: body_html,
      contributors: contributors,
      published_at: published_at,
      url: release["html_url"],
      source: source
    }
  end

  @doc "Formats a DateTime as a human-readable date string."
  def format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %-d, %Y")
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :protected, read_concurrency: true])
    releases = fetch_all_releases()
    :ets.insert(table, {:releases, releases})
    schedule_refresh()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    releases = fetch_all_releases()
    :ets.insert(@table, {:releases, releases})
    schedule_refresh()
    {:noreply, state}
  end

  defp fetch_all_releases do
    @repos
    |> Enum.flat_map(fn {source, repo} -> fetch_releases(repo, source) end)
    |> Enum.sort_by(& &1.published_at, {:desc, DateTime})
  end

  defp fetch_releases(repo, source) do
    url = "https://api.github.com/repos/#{repo}/releases"

    case Req.get(url, headers: [{"accept", "application/vnd.github+json"}]) do
      {:ok, %{status: 200, body: body}} ->
        body
        |> Enum.map(&parse_release(&1, source))
        |> Enum.reject(&(&1 == :skip))

      {:ok, %{status: status}} ->
        Logger.warning("[Changelog] GitHub API returned #{status} for #{repo}")
        []

      {:error, reason} ->
        Logger.warning("[Changelog] Failed to fetch releases for #{repo}: #{inspect(reason)}")
        []
    end
  end

  @doc false
  def extract_contributors(body) do
    Regex.scan(~r/@([a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38})/, body)
    |> Enum.map(fn [_, username] -> username end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in @excluded_contributors))
    |> Enum.sort_by(&String.downcase/1)
  end

  defp strip_contributors_section(body) do
    # Remove "## New Contributors" section and everything after it
    body
    |> String.split(~r/\n##\s+New Contributors/i, parts: 2)
    |> List.first()
    |> String.trim_trailing()
  end

  defp sanitize_html(html) do
    html
    |> strip_images()
    |> shorten_pr_links()
    |> linkify_usernames()
  end

  defp strip_images(html) do
    Regex.replace(~r/<img[^>]*>/, html, "")
  end

  defp shorten_pr_links(html) do
    Regex.replace(
      ~r{<a href="(https://github\.com/[^"]+/pull/(\d+))"[^>]*>https://github\.com/[^<]+</a>},
      html,
      fn _, url, num -> ~s(<a href="#{url}">##{num}</a>) end
    )
  end

  defp linkify_usernames(html) do
    # Match @username that isn't already inside an href or anchor tag
    Regex.replace(
      ~r/(?<!["\/\w])@([a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38})/,
      html,
      fn _, username -> ~s(<a href="https://github.com/#{username}">@#{username}</a>) end
    )
  end

  defp schedule_refresh do
    interval = Application.get_env(:crit, :changelog_refresh_interval_ms, @refresh_interval)
    Process.send_after(self(), :refresh, interval)
  end
end
