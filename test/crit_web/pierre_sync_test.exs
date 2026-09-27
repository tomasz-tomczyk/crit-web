defmodule CritWeb.PierreSyncTest do
  @moduledoc """
  Drift guard for the vendored code renderer.

  crit-web highlights and themes code with crit's @pierre/diffs build and
  crit's renderer modules, copied verbatim by `scripts/sync-pierre.sh`:

    * `priv/static/pierre/` — the Pierre + Shiki bundle and theme palettes
    * `assets/vendor/crit/` — modules bundled into the review page

  When the sibling crit checkout is present (local dev), each vendored file
  must match its crit source by content hash and the Pierre directory must hold
  exactly crit's file set. When it is absent (CI), only presence is checked.
  """
  use ExUnit.Case, async: true

  # Keep in sync with BUNDLED in scripts/sync-pierre.sh.
  @bundled_modules [
    "crit-code-highlight.js",
    "crit-pierre-adapter.js",
    "crit-pierre-dom.js",
    "crit-pierre-runtime.js",
    "crit-theme-boost.js",
    "crit-palette.css"
  ]
  @pierre_entries ["pierre-diffs.js.gz", "pierre-worker.js.gz", "palettes.js.gz"]

  @root File.cwd!()
  @pierre_dir Path.join([@root, "priv", "static", "pierre"])
  @bundled_dir Path.join([@root, "assets", "vendor", "crit"])
  @crit_web Path.join([@root, "..", "crit", "web"])

  defp sha256(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp vendored_pairs do
    Enum.map(@bundled_modules, &{Path.join(@bundled_dir, &1), Path.join(@crit_web, &1)})
  end

  test "vendored renderer files exist" do
    for {vendored, _source} <- vendored_pairs() do
      assert File.exists?(vendored),
             "missing vendored file: #{vendored}. Run scripts/sync-pierre.sh."
    end

    for entry <- @pierre_entries do
      assert File.exists?(Path.join(@pierre_dir, entry)),
             "missing #{entry} in #{@pierre_dir}. Run scripts/sync-pierre.sh."
    end
  end

  test "vendored renderer files match crit by content hash" do
    if File.dir?(@crit_web) do
      for {vendored, source} <- vendored_pairs() do
        assert File.exists?(source), "expected crit source file at #{source}"

        assert sha256(vendored) == sha256(source), """
        DRIFT: #{Path.basename(vendored)} differs between crit-web and crit.
          vendored: #{vendored}
          source:   #{source}
        Re-sync with: scripts/sync-pierre.sh
        """
      end
    end
  end

  test "the Pierre bundle matches crit file for file" do
    source_dir = Path.join(@crit_web, "pierre")

    if File.dir?(source_dir) do
      source_files = source_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".js.gz"))
      vendored_files = File.ls!(@pierre_dir)

      assert Enum.sort(vendored_files) == Enum.sort(source_files), """
      DRIFT: priv/static/pierre does not hold crit's file set.
        only in crit-web: #{inspect(vendored_files -- source_files)}
        only in crit:     #{inspect(source_files -- vendored_files)}
      Re-sync with: scripts/sync-pierre.sh
      """

      for f <- source_files do
        assert sha256(Path.join(@pierre_dir, f)) == sha256(Path.join(source_dir, f)),
               "DRIFT: pierre/#{f} differs from crit. Re-sync with: scripts/sync-pierre.sh"
      end
    end
  end
end
