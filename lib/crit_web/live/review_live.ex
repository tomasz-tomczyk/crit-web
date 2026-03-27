defmodule CritWeb.ReviewLive do
  use CritWeb, :live_view

  alias Crit.{Accounts, Reviews}

  @pubsub Crit.PubSub

  @impl true
  def mount(%{"token" => token}, session, socket) do
    current_user =
      case Map.get(session, "user_id") do
        nil ->
          nil

        user_id ->
          case Accounts.get_user(user_id) do
            {:ok, user} -> user
            {:error, :not_found} -> nil
          end
      end

    {identity, display_name} =
      if current_user do
        {current_user.id, current_user.name || current_user.email}
      else
        {Map.get(session, "identity", Ecto.UUID.generate()), Map.get(session, "display_name")}
      end

    case Reviews.get_by_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Review not found.")
         |> redirect(to: ~p"/"), layout: {CritWeb.Layouts, :review}}

      review ->
        demo? = review.token == Application.get_env(:crit, :demo_review_token)

        files_data =
          Enum.map(review.files, fn f ->
            %{path: f.file_path, content: f.content, position: f.position}
          end)

        socket =
          if connected?(socket) do
            Phoenix.PubSub.subscribe(@pubsub, "review:#{token}")
            Reviews.touch_last_activity(review)

            comments = review.comments |> filter_demo_comments(demo?, identity)

            push_event(socket, "init", %{
              comments: serialize_comments(comments),
              display_name: display_name,
              files: files_data
            })
          else
            socket
          end

        comments_url = CritWeb.Endpoint.url() <> ~p"/api/export/#{review.token}/comments"

        file_paths = review.files |> Enum.map(& &1.file_path) |> Enum.join(" ")

        local_prompt_text =
          "Please fetch #{comments_url} — these are review comments from crit. " <>
            "Comments are grouped per file with start_line/end_line referencing the source. " <>
            "Read each comment, address it in the relevant file and location, " <>
            "then run `crit share #{file_paths}` to sync the updated files back and signal the review is ready for the next round."

        export_url = CritWeb.Endpoint.url() <> ~p"/api/export/#{review.token}/review"

        full_export_prompt_text =
          "Please fetch #{export_url} — this contains the full plan with review comments " <>
            "interjected inline. Implement the plan while addressing each review comment."

        {:ok,
         socket
         |> assign(:review, review)
         |> assign(:current_user, current_user)
         |> assign(:identity, identity)
         |> assign(:display_name, display_name)
         |> assign(:demo?, demo?)
         |> assign(:local_prompt_text, local_prompt_text)
         |> assign(:full_export_prompt_text, full_export_prompt_text)
         |> assign(:prompt_mode, "local")
         |> assign(:show_round_diff, false)
         |> assign(:prev_round_snapshots, %{})
         |> assign(:diff_mode, "split")
         |> assign(:page_title, display_filename(review))
         |> assign(
           :meta_description,
           "Shared review of #{display_filename(review)} on Crit. View inline comments and add your own feedback."
         )
         |> assign(:noindex, true)
         |> assign(:og_type, "article")
         |> assign(:canonical_url, CritWeb.Endpoint.url() <> ~p"/r/#{review.token}"),
         layout: {CritWeb.Layouts, :review}}
    end
  end

  def handle_event("set_prompt_mode", %{"mode" => mode}, socket)
      when mode in ["local", "full_export"] do
    {:noreply, assign(socket, :prompt_mode, mode)}
  end

  def handle_event("toggle_round_diff", _params, socket) do
    review = socket.assigns.review

    if socket.assigns.show_round_diff do
      {:noreply,
       socket
       |> assign(show_round_diff: false, prev_round_snapshots: %{})
       |> push_event("round_diff_updated", %{enabled: false, snapshots: %{}})}
    else
      snapshots = Reviews.get_round_snapshots(review.id, review.review_round - 1)

      {:noreply,
       socket
       |> assign(show_round_diff: true, prev_round_snapshots: snapshots)
       |> push_event("round_diff_updated", %{enabled: true, snapshots: snapshots})}
    end
  end

  def handle_event("set_diff_mode", %{"mode" => mode}, socket)
      when mode in ["split", "unified"] do
    {:noreply,
     socket
     |> assign(:diff_mode, mode)
     |> push_event("diff_mode_updated", %{mode: mode})}
  end

  @impl true
  def handle_event(
        "add_comment",
        %{"body" => body} = params,
        socket
      ) do
    %{review: review, identity: identity} = socket.assigns
    file_path = params["file_path"]
    scope = params["scope"] || "line"

    attrs =
      %{
        "start_line" => params["start_line"] || 0,
        "end_line" => params["end_line"] || 0,
        "body" => body,
        "scope" => scope
      }
      |> then(fn a ->
        if q = params["quote"], do: Map.put(a, "quote", q), else: a
      end)

    case Reviews.create_comment(review, attrs, identity, socket.assigns.display_name, file_path) do
      {:ok, _comment} ->
        broadcast_comments(review)
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save comment.")}
    end
  end

  @impl true
  def handle_event("edit_comment", %{"id" => id, "body" => body}, socket) do
    %{review: review, identity: identity} = socket.assigns

    case Reviews.update_comment(id, body, identity) do
      {:ok, _comment} ->
        broadcast_comments(review)
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only edit your own comments.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update comment.")}
    end
  end

  @impl true
  def handle_event("delete_comment", %{"id" => id}, socket) do
    %{review: review, identity: identity} = socket.assigns

    case Reviews.delete_comment(id, identity) do
      {:ok, _} ->
        broadcast_comments(review)
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only delete your own comments.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete comment.")}
    end
  end

  @impl true
  def handle_event("set_display_name", %{"name" => name}, socket) do
    # Updates the in-memory assign only. The DB update and cross-review
    # broadcast happen in the controller's POST /set-name handler (the JS
    # hook fires both this event and the POST). We broadcast the current
    # review here for immediate feedback to other viewers on this page.
    case Crit.DisplayName.normalize(name) do
      nil ->
        {:noreply, socket}

      name ->
        broadcast_comments(socket.assigns.review)

        {:noreply,
         socket
         |> assign(:display_name, name)
         |> push_event("display_name_updated", %{display_name: name})}
    end
  end

  @impl true
  def handle_event("noop_refresh", _params, socket) do
    broadcast_comments(socket.assigns.review)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_reply", %{"comment_id" => comment_id, "body" => body}, socket) do
    %{review: review, identity: identity, display_name: display_name} = socket.assigns

    case Reviews.create_reply(comment_id, %{"body" => body}, identity, display_name, review.id) do
      {:ok, _reply} ->
        broadcast_comments(review)
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add reply.")}
    end
  end

  @impl true
  def handle_event("edit_reply", %{"id" => id, "body" => body}, socket) do
    %{review: review, identity: identity} = socket.assigns

    case Reviews.update_reply(id, body, identity) do
      {:ok, _} ->
        broadcast_comments(review)
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only edit your own replies.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update reply.")}
    end
  end

  @impl true
  def handle_event("delete_reply", %{"id" => id}, socket) do
    %{review: review, identity: identity} = socket.assigns

    case Reviews.delete_reply(id, identity) do
      {:ok, _} ->
        broadcast_comments(review)
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only delete your own replies.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete reply.")}
    end
  end

  @impl true
  def handle_event("resolve_comment", %{"id" => id, "resolved" => resolved}, socket) do
    %{review: review} = socket.assigns

    case Reviews.resolve_comment(id, resolved, review.id) do
      {:ok, _} ->
        broadcast_comments(review)
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update comment.")}
    end
  end

  @impl true
  def handle_info({:comments_updated, comments}, socket) do
    %{demo?: demo?, identity: identity} = socket.assigns
    filtered = filter_demo_comments(comments, demo?, identity)
    {:noreply, push_event(socket, "comments_updated", %{comments: serialize_comments(filtered)})}
  end

  defp broadcast_comments(%{token: token} = review) do
    comments = Reviews.list_comments(review)
    Phoenix.PubSub.broadcast(@pubsub, "review:#{token}", {:comments_updated, comments})
  end

  defp serialize_comments(comments) do
    Enum.map(comments, &Reviews.serialize_comment/1)
  end

  defp filter_demo_comments(comments, false, _identity), do: comments

  defp filter_demo_comments(comments, true, identity) do
    comments
    |> Enum.filter(fn c -> c.author_identity in ["imported", identity] end)
    |> Enum.map(fn c ->
      filtered_replies =
        case c.replies do
          %Ecto.Association.NotLoaded{} -> %Ecto.Association.NotLoaded{}
          replies -> Enum.filter(replies, &(&1.author_identity in ["imported", identity]))
        end

      %{c | replies: filtered_replies}
    end)
  end

  @doc false
  def session_opts(conn) do
    %{"user_id" => Plug.Conn.get_session(conn, :user_id)}
  end

  defp display_filename(%{files: [first | _]}), do: first.file_path
  defp display_filename(_), do: "Review"
end
