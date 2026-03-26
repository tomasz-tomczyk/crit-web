defmodule CritWeb.ApiController do
  use CritWeb, :controller

  alias Crit.Reviews
  alias Crit.Output

  # 30 write requests per minute per IP
  plug :rate_limit_write when action in [:create, :update]

  @max_comments 500

  def create(conn, %{"files" => files} = params) when is_list(files) and files != [] do
    review_round = params["review_round"]
    comments = params["comments"] || []
    review_comments = params["review_comments"] || []

    cond do
      length(comments) + length(review_comments) > @max_comments ->
        conn |> put_status(422) |> json(%{error: "Too many comments (max #{@max_comments})"})

      length(files) > 200 ->
        conn |> put_status(422) |> json(%{error: "Too many files (max 200)"})

      true ->
        case Reviews.create_review(files, review_round, comments, review_comments) do
          {:ok, review} ->
            url = CritWeb.Endpoint.url() <> ~p"/r/#{review.token}"
            conn |> put_status(201) |> json(%{url: url, delete_token: review.delete_token})

          {:error, :total_size_exceeded} ->
            conn |> put_status(422) |> json(%{error: "Total file size exceeds 10 MB limit"})

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            conn |> put_status(422) |> json(%{error: "Validation failed", details: errors})
        end
    end
  end

  def create(conn, %{"content" => content} = params) do
    filename = params["filename"]
    review_round = params["review_round"]
    comments = params["comments"] || []
    review_comments = params["review_comments"] || []

    file_path = filename || "document"
    files = [%{"path" => file_path, "content" => content}]
    comments_with_file = Enum.map(comments, &Map.put_new(&1, "file", file_path))

    cond do
      length(comments) + length(review_comments) > @max_comments ->
        conn
        |> put_status(422)
        |> json(%{error: "Too many comments (max #{@max_comments})"})

      true ->
        case Reviews.create_review(files, review_round, comments_with_file, review_comments) do
          {:ok, review} ->
            url = CritWeb.Endpoint.url() <> ~p"/r/#{review.token}"
            conn |> put_status(201) |> json(%{url: url, delete_token: review.delete_token})

          {:error, :total_size_exceeded} ->
            conn |> put_status(422) |> json(%{error: "Total file size exceeds 10 MB limit"})

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            conn |> put_status(422) |> json(%{error: "Validation failed", details: errors})
        end
    end
  end

  def create(conn, _params) do
    conn |> put_status(422) |> json(%{error: "content is required"})
  end

  def document(conn, %{"token" => token}) do
    case Reviews.get_by_token(token) do
      nil ->
        not_found(conn)

      review ->
        files = Enum.map(review.files, fn f -> %{path: f.file_path, content: f.content} end)
        json(conn, %{files: files})
    end
  end

  def comments_list(conn, %{"token" => token}) do
    case Reviews.get_by_token(token) do
      nil -> not_found(conn)
      review -> json(conn, Enum.map(visible_comments(review), &Reviews.serialize_comment/1))
    end
  end

  def export_review(conn, %{"token" => token}) do
    case Reviews.get_by_token(token) do
      nil ->
        not_found(conn)

      review ->
        comments = visible_comments(review)
        files = Enum.map(review.files, fn f -> %{path: f.file_path, content: f.content} end)
        md = Output.generate_multi_file_review_md(files, comments)

        conn
        |> put_resp_content_type("text/markdown")
        |> put_resp_header("content-disposition", ~s(attachment; filename="review.md"))
        |> send_resp(200, md)
    end
  end

  def export_comments(conn, %{"token" => token}) do
    case Reviews.get_by_token(token) do
      nil ->
        not_found(conn)

      review ->
        comments = visible_comments(review)
        files = Enum.map(review.files, fn f -> %{path: f.file_path} end)
        base_url = CritWeb.Endpoint.url()
        json(conn, Output.multi_file_comments_json(review, files, comments, base_url))
    end
  end

  defp visible_comments(review) do
    demo_token = Application.get_env(:crit, :demo_review_token)

    if review.token == demo_token do
      review.comments
      |> Enum.filter(&(&1.author_identity == "imported"))
      |> Enum.map(fn c ->
        filtered_replies =
          case c.replies do
            %Ecto.Association.NotLoaded{} -> %Ecto.Association.NotLoaded{}
            replies -> Enum.filter(replies, &(&1.author_identity == "imported"))
          end

        %{c | replies: filtered_replies}
      end)
    else
      review.comments
    end
  end

  def update(conn, %{"token" => token} = params) do
    delete_token = params["delete_token"]
    payload = Map.take(params, ["files", "comments", "review_round"])

    case Reviews.upsert_review(token, delete_token, payload) do
      {:ok, :updated, review} ->
        url = CritWeb.Endpoint.url() <> ~p"/r/#{review.token}"
        json(conn, %{url: url, review_round: review.review_round, changed: true})

      {:ok, :no_changes, review} ->
        url = CritWeb.Endpoint.url() <> ~p"/r/#{review.token}"
        json(conn, %{url: url, review_round: review.review_round, changed: false})

      {:error, :not_found} ->
        not_found(conn)

      {:error, :unauthorized} ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end

  def delete_review(conn, %{"delete_token" => delete_token})
      when is_binary(delete_token) and delete_token != "" do
    case Reviews.delete_by_delete_token(delete_token) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        not_found(conn)

      {:error, :delete_failed} ->
        conn |> put_status(500) |> json(%{error: "Failed to delete review"})
    end
  end

  def delete_review(conn, _params) do
    conn |> put_status(400) |> json(%{error: "delete_token is required"})
  end

  if Mix.env() == :test do
    def seed_comment(conn, %{"token" => token} = params) do
      case Reviews.get_by_token(token) do
        nil ->
          not_found(conn)

        review ->
          attrs = %{
            "start_line" => params["start_line"] || 1,
            "end_line" => params["end_line"] || 1,
            "body" => params["body"] || "web reviewer comment",
            "file_path" => params["file"] || hd(review.files).file_path,
            "scope" => "line"
          }

          {:ok, comment} =
            Reviews.create_comment(review, attrs, "integration-test", "WebReviewer")

          json(conn, Reviews.serialize_comment(comment))
      end
    end
  end

  # Handled by LocalhostCors plug — this action is never reached.
  def options(conn, _params), do: send_resp(conn, 204, "")

  # Rate-limit POST /api/reviews: 30 per minute per IP.
  defp rate_limit_write(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Crit.RateLimit.hit("write:#{ip}", :timer.minutes(1), 30) do
      {:allow, _} ->
        conn

      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(retry_after, 1000)))
        |> put_status(429)
        |> json(%{error: "Too many requests"})
        |> halt()
    end
  end

  # Track invalid token lookups: 10 per 5 minutes per IP, then return 429.
  defp not_found(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Crit.RateLimit.hit("invalid_token:#{ip}", :timer.minutes(5), 10) do
      {:allow, _} -> conn |> put_status(404) |> json(%{error: "Not found"})
      {:deny, _} -> conn |> put_status(429) |> json(%{error: "Too many requests"})
    end
  end
end
