defmodule CritWeb.RawController do
  use CritWeb, :controller

  alias Crit.Review
  alias Crit.Reviews

  def show(conn, %{"token" => token, "file_path" => path_segments})
      when is_list(path_segments) do
    file_path = Enum.join(path_segments, "/")

    with %Review{} = review <- Reviews.get_by_token(token),
         %{content: content} = file <-
           Enum.find(review.files, fn f -> f.file_path == file_path end),
         basename when basename != :unsafe <- safe_basename(file.file_path) do
      conn
      |> put_resp_content_type("text/plain", "utf-8")
      |> put_resp_header("content-disposition", ~s(inline; filename="#{basename}"))
      |> send_resp(200, content)
    else
      _ -> conn |> put_status(404) |> text("not found")
    end
  end

  # RFC 6266 requires the `filename=` parameter to be ASCII. Reject anything
  # outside printable ASCII (0x20–0x7e), plus the quote and backslash that
  # would break the quoted-string in the content-disposition header.
  # We deliberately do NOT emit a `filename*=UTF-8''…` fallback here —
  # callers with non-ASCII basenames get a 404, which is acceptable.
  defp safe_basename(path) do
    base = Path.basename(path)

    if String.match?(base, ~r/[^\x20-\x7e]|["\\]/), do: :unsafe, else: base
  end
end
