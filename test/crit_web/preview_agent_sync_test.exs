defmodule CritWeb.PreviewAgentSyncTest do
  @moduledoc """
  Drift guard for the vendored preview-agent scripts.

  The files under `priv/static/preview-agent/` are vendored verbatim from the
  sibling crit checkout's `frontend/` directory (see
  `scripts/sync-preview-agent.sh`). crit injects this exact set + order into
  preview iframes; crit-web must serve byte-identical copies so DOM anchoring
  stays compatible across both renderers.

  When the sibling crit checkout is present (local dev), this test asserts each
  vendored file matches its crit source by content hash and is LOUD on drift.
  When the sibling checkout is absent (CI), it skips gracefully.
  """
  use ExUnit.Case, async: true

  # Keep in sync with `agentScriptFiles` in crit/server.go + agent-marker.css.
  # This is also the list driven by scripts/sync-preview-agent.sh.
  @files [
    "agent-protocol.js",
    "agent-anchor-utils.js",
    "agent-marker-overlay.js",
    "agent-mutation-batcher.js",
    "agent-resolution.js",
    "agent-reanchor-state.js",
    "crit-agent.js",
    "agent-marker.css"
  ]

  @vendored_dir Path.join([File.cwd!(), "priv", "static", "preview-agent"])
  @crit_frontend Path.join([File.cwd!(), "..", "crit", "web"])

  defp sha256(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  test "vendored preview-agent files exist" do
    for f <- @files do
      vendored = Path.join(@vendored_dir, f)

      assert File.exists?(vendored),
             "missing vendored preview-agent file: #{vendored}. " <>
               "Run scripts/sync-preview-agent.sh to populate it."
    end
  end

  test "vendored preview-agent files match the crit/web sources by content hash" do
    if File.dir?(@crit_frontend) do
      for f <- @files do
        vendored = Path.join(@vendored_dir, f)
        source = Path.join(@crit_frontend, f)

        assert File.exists?(source),
               "expected crit source file at #{source}"

        assert sha256(vendored) == sha256(source),
               """
               DRIFT: #{f} differs between crit-web and crit.
                 vendored: #{vendored}
                 source:   #{source}
               Re-sync with: scripts/sync-preview-agent.sh
               and commit the result in both repos.
               """
      end
    else
      # Sibling crit checkout absent (e.g. CI) — nothing to compare against.
      assert true
    end
  end
end
