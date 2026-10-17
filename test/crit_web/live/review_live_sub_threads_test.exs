defmodule CritWeb.ReviewLiveSubThreadsTest do
  @moduledoc "The `add_sub_thread` event of the review page."
  use CritWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  alias Crit.Comment
  alias Crit.Repo
  alias Crit.Reviews

  setup do
    Application.put_env(:crit, :selfhosted, false)
    on_exit(fn -> Application.delete_env(:crit, :selfhosted) end)
    %{review: review_fixture()}
  end

  defp hook(view, event, params) do
    view |> element("#document-renderer") |> render_hook(event, params)
  end

  test "comments on a passage of a comment: pushed and broadcast as comment_added", %{
    conn: conn,
    review: review
  } do
    parent = comment_fixture(review, %{"body" => "Option A is faster."})
    Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")
    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

    hook(view, "add_sub_thread", %{
      "anchor_id" => parent.id,
      "body" => "Why is A faster?",
      "quote" => "Option A",
      "quote_offset" => 0
    })

    assert_reply(view, %{ok: true})
    assert_push_event view, "comment_added", %{comment: sub}
    assert sub.anchor_comment_id == parent.id
    assert sub.quote == "Option A"
    assert sub.quote_offset == 0
    assert sub.start_line == nil
    assert sub.scope == parent.scope

    assert_receive {:comment_added, %{comment: %{id: id}}}, 500
    assert id == sub.id
    assert %Comment{anchor_comment_id: anchor_id} = Repo.get!(Comment, sub.id)
    assert anchor_id == parent.id
  end

  test "an unknown or foreign message is refused and nothing is created", %{
    conn: conn,
    review: review
  } do
    foreign = comment_fixture(review_fixture())
    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

    for anchor_id <- [Ecto.UUID.generate(), foreign.id, "not-a-uuid"] do
      hook(view, "add_sub_thread", %{"anchor_id" => anchor_id, "body" => "Lost", "quote" => "x"})

      assert_reply(view, %{
        ok: false,
        error: "The commented message no longer exists.",
        reason: "not_found"
      })
    end

    assert Reviews.list_comments(review.id) == []
  end
end
