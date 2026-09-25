defmodule CritWeb.ReviewsApiController do
  use CritWeb, :controller

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  @doc """
  GET /api/reviews — cursor-paginated list of the caller's reviews, or of an
  organization's reviews with `?org=<slug>`. Always requires a Bearer token.

  Query params: `limit` (1..500, default 50), `after` (cursor from the
  previous page's `next_cursor`), `org` (organization slug).
  """
  def index(conn, params) do
    scope = Scope.for_user(conn.assigns.current_user)
    opts = [org: params["org"], limit: params["limit"], after: params["after"]]

    case Reviews.list_reviews_page(scope, opts) do
      {:ok, page} ->
        json(conn, %{
          reviews: Enum.map(page.reviews, &review_json/1),
          has_more: page.has_more,
          next_cursor: page.next_cursor
        })

      {:error, :org_not_found} ->
        conn |> put_status(404) |> json(%{error: "Organization not found"})

      {:error, :not_a_member} ->
        conn |> put_status(403) |> json(%{error: "You are not a member of this organization"})

      {:error, {:invalid_params, message}} ->
        conn |> put_status(400) |> json(%{error: message})
    end
  end

  # Explicit allowlist: the summary rows also carry author email, user and
  # internal ids, which must not leave the server.
  defp review_json(review) do
    %{
      token: review.token,
      url: CritWeb.Endpoint.url() <> ~p"/r/#{review.token}",
      title: review.title,
      review_type: review.review_type,
      visibility: review.visibility,
      org: org_json(review),
      comment_count: review.comment_count,
      file_count: review.file_count,
      first_file_path: review.first_file_path,
      inserted_at: review.inserted_at,
      last_activity_at: review.last_activity_at
    }
  end

  defp org_json(%{org_slug: nil}), do: nil
  defp org_json(%{org_slug: slug, org_name: name}), do: %{slug: slug, name: name}
end
