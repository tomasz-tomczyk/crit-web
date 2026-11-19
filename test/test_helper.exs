if System.get_env("E2E") == "true" do
  # The browser suite (test/e2e, playwright_ex): playwright.config.ts's
  # webServer is this VM's own endpoint, served with E2E=true PHX_SERVER=true
  # PORT=4003 (and PHX_HOST/PREVIEW_HOST/PORT=4004 for the security project).
  # E2E mode uses a real pool, not the sandbox, so only browser tests run.
  unless System.get_env("PHX_SERVER") && System.get_env("PORT") do
    raise "the browser suite needs E2E=true PHX_SERVER=true PORT=4003 (see test/test_helper.exs)"
  end

  project = if System.get_env("PREVIEW_HOST"), do: :security, else: :e2e
  ExUnit.start(exclude: [:test], include: [project], timeout: 45_000)
else
  ExUnit.start(exclude: [:e2e, :security])
  Ecto.Adapters.SQL.Sandbox.mode(Crit.Repo, :manual)
end
