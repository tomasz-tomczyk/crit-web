defmodule Crit.SentryFilterTest do
  use ExUnit.Case, async: true

  alias Crit.SentryFilter

  defp event(overrides) do
    Map.merge(
      %Sentry.Event{
        event_id: "a" <> String.duplicate("0", 31),
        timestamp: 1_700_000_000
      },
      Map.new(overrides)
    )
  end

  describe "before_send/1" do
    test "drops Bandit header-too-long scanner noise" do
      event =
        event(%{
          exception: [
            %{
              type: "Bandit.HTTPError",
              value: "Header too long"
            }
          ]
        })

      assert :ignore = SentryFilter.before_send(event)
    end

    test "passes through unrelated exceptions" do
      event =
        event(%{
          exception: [%{type: "RuntimeError", value: "boom"}],
          extra: %{document: "secret", safe: "ok"}
        })

      assert %Sentry.Event{extra: %{safe: "ok"}} = SentryFilter.before_send(event)
    end
  end
end
