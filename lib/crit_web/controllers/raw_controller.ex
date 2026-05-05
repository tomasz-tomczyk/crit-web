defmodule CritWeb.RawController do
  use CritWeb, :controller

  alias Crit.Reviews

  def show(conn, %{"token" => token, "file_path" => path_segments})
      when is_list(path_segments) do
    file_path = Enum.join(path_segments, "/")

    with %{} = review <- Reviews.get_by_token(token),
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

  # Reject any basename containing characters that would break the
  # content-disposition header (quote, CR, LF) or are control chars.
  # In practice the CLI never produces these — this is belt-and-braces.
  defp safe_basename(path) do
    base = Path.basename(path)

    if String.match?(base, ~r/[\x00-\x1f"\\]/), do: :unsafe, else: base
  end
end
