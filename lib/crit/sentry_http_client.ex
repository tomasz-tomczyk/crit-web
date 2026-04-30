defmodule Crit.SentryHTTPClient do
  @moduledoc false
  @behaviour Sentry.HTTPClient

  @impl true
  def post(url, headers, body) do
    case Req.post(url, headers: headers, body: body, decode_body: false) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        # Req returns headers as %{"name" => ["v1", "v2"]}; Sentry expects
        # a flat list of {name, value} string tuples.
        flat =
          Enum.flat_map(resp_headers, fn {k, vs} ->
            Enum.map(List.wrap(vs), &{k, to_string(&1)})
          end)

        {:ok, status, flat, resp_body}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
