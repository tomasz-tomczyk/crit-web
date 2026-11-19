defmodule CritWeb.E2ECase do
  @moduledoc """
  Case template of the browser suite (test/e2e), ported from the Playwright
  specs in e2e/. `Playwright.Case` gives each test a `context` and `page`;
  this adds Playwright Test's `request` fixture and the e2e/helpers.ts port.

  Tagged `:e2e` (or `tag: :security` for the security project), run with
  `E2E=true PHX_SERVER=true PORT=4003 mix test test/e2e`.
  """
  use ExUnit.CaseTemplate

  using opts do
    {tag, opts} = Keyword.pop(opts, :tag, :e2e)

    quote do
      use Playwright.Case, unquote(opts)

      import CritWeb.E2E.Helpers

      alias Playwright.{
        APIRequest,
        APIRequestContext,
        APIResponse,
        Dialog,
        ElementHandle,
        FrameLocator,
        JSHandle
      }

      @moduletag unquote(tag)

      setup %{browser: browser} do
        request =
          APIRequest.new_context!(
            Playwright.request(Playwright.Test.BrowserPool.playwright(browser))
          )

        %{request: request}
      end
    end
  end
end
