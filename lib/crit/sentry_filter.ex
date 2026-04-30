defmodule Crit.SentryFilter do
  @moduledoc """
  Privacy backstop for outgoing Sentry events.

  `Sentry.PlugContext` already drops request bodies and cookies. This filter
  is defense-in-depth for any code path that might attach review/comment
  content via `Sentry.Context.set_extra_context/1` or similar — strips keys
  that are likely to contain user-authored content, and scrubs query params
  that look like delete tokens.
  """

  # Sentry.Context stores extras as atom-keyed maps; cover both atoms and
  # strings so a manual `Sentry.capture_*` with a string-keyed map is also scrubbed.
  @sensitive_keys ~w(document body comment comments markdown content)a ++
                    ~w(document body comment comments markdown content)
  @sensitive_query_params ~w(delete_token token api_key)

  def before_send(%Sentry.Event{} = event) do
    event
    |> scrub_extra()
    |> scrub_query_params()
  end

  defp scrub_extra(%{extra: extra} = event) when is_map(extra) do
    %{event | extra: Map.drop(extra, @sensitive_keys)}
  end

  defp scrub_extra(event), do: event

  defp scrub_query_params(%{request: %Sentry.Interfaces.Request{query_string: qs} = req} = event)
       when is_binary(qs) do
    scrubbed =
      qs
      |> URI.decode_query()
      |> Enum.map(fn {k, v} -> if k in @sensitive_query_params, do: {k, "[Filtered]"}, else: {k, v} end)
      |> URI.encode_query()

    %{event | request: %{req | query_string: scrubbed}}
  end

  defp scrub_query_params(event), do: event
end
