defmodule CritWeb.ReviewLive do
  use CritWeb, :live_view

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  # Auth is gated by the router's :require_review_scope on_mount hook
  # (CritWeb.UserAuth), which also assigns :current_scope. On selfhosted+OAuth,
  # unauthenticated visitors are redirected before mount/3 runs.

  @pubsub Crit.PubSub

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    scope = socket.assigns.current_scope
    auth_required = Crit.Config.selfhosted_oauth?()

    mount_review(token, socket, scope, auth_required)
  end

  defp mount_review(token, socket, %Scope{} = scope, auth_required) do
    case Reviews.get_by_token(token) do
      nil ->
        raise CritWeb.NotFoundError

      review ->
        demo? = review.token == Application.get_env(:crit, :demo_review_token)
        identity = scope.identity
        display_name = scope.display_name
        user_id = Scope.user_id(scope)

        public? = review.visibility == :public
        owner? = user_id != nil and user_id == review.user_id

        canonical_url =
          if public?, do: CritWeb.Endpoint.url() <> "/r/#{review.token}", else: nil

        files_data =
          Enum.map(review.files, fn f ->
            %{path: f.file_path, content: f.content, position: f.position, status: f.status}
          end)

        socket =
          if connected?(socket) do
            Phoenix.PubSub.subscribe(@pubsub, "review:#{token}")
            Reviews.touch_last_activity(review)

            comments =
              review.comments
              |> filter_demo_comments(demo?, identity, user_id)

            push_event(socket, "init", %{
              comments: serialize_comments(comments),
              display_name: display_name,
              files: files_data
            })
          else
            socket
          end

        file_paths = review.files |> Enum.map(& &1.file_path) |> Enum.join(" ")

        auth_note =
          if auth_required do
            " The server requires authentication — include the header `Authorization: Bearer <token>` in all fetch requests, where <token> is your API token from the dashboard. You can also set CRIT_AUTH_TOKEN in your environment or add `\"auth_token\": \"<token>\"` to ~/.crit.config.json — `crit share` reads this automatically."
          else
            ""
          end

        cli_args = review.cli_args || []

        local_prompt_text =
          "Run `crit fetch` to pull the latest review comments (it prints the review file path and each comment). " <>
            "If you need the full comment text, read the review file — run `crit status` to find its path. " <>
            "Address each unresolved comment in the relevant file at the referenced location, " <>
            "then reply with `crit comment --reply-to <id> --author 'Claude Code' '<what you did>'`. " <>
            "When all comments are addressed, run `crit share #{file_paths}` to post the updated files and replies back." <>
            if(cli_args != [],
              do:
                " Then run `crit #{Enum.join(cli_args, " ")}` to refresh the local review session with your changes.",
              else: ""
            )

        export_url = CritWeb.Endpoint.url() <> ~p"/api/export/#{review.token}/review"

        full_export_prompt_text =
          "Please fetch #{export_url} — this contains the full plan with review comments " <>
            "interjected inline.#{auth_note} Implement the plan while addressing each review comment."

        {:ok,
         socket
         |> assign(:review, review)
         |> assign(:oauth_configured, Crit.Config.oauth_configured?())
         |> assign(:auth_required, auth_required)
         |> assign(:demo?, demo?)
         |> assign(:local_prompt_text, local_prompt_text)
         |> assign(:full_export_prompt_text, full_export_prompt_text)
         |> assign(:prompt_mode, "local")
         |> assign(
           :has_previous_round,
           review.review_round > 1 &&
             Reviews.has_round_snapshots?(review.id, review.review_round - 1)
         )
         |> assign(:show_round_diff, false)
         |> assign(:prev_round_snapshots, %{})
         |> assign(:diff_mode, "split")
         |> assign(:page_title, display_filename(review))
         |> assign(
           :meta_description,
           "Shared review of #{display_filename(review)} on Crit. View inline comments and add your own feedback."
         )
         |> assign(:noindex, not public?)
         |> assign(:og_type, "article")
         |> assign(:canonical_url, canonical_url)
         |> assign(:owner?, owner?), layout: {CritWeb.Layouts, :review}}
    end
  end

  def handle_event("make_public", _params, socket) do
    scope = socket.assigns.current_scope
    review = socket.assigns.review

    case Reviews.make_public(scope, review.id) do
      {:ok, updated} ->
        canonical_url = CritWeb.Endpoint.url() <> "/r/#{updated.token}"
        merged = Map.merge(review, Map.take(updated, [:visibility]))

        {:noreply,
         socket
         |> assign(:review, merged)
         |> assign(:noindex, false)
         |> assign(:canonical_url, canonical_url)
         |> put_flash(:info, "Review is now public. Search engines may index it.")}

      {:error, :already_public} ->
        {:noreply, put_flash(socket, :info, "Review is already public.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not allowed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not make the review public.")}
    end
  end

  def handle_event("delete_review", _params, socket) do
    %{review: review, current_scope: scope} = socket.assigns

    case Reviews.delete_review(scope, review.id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Review deleted.")
         |> redirect(to: ~p"/dashboard")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only delete your own reviews.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete review.")}
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
    %{review: review, current_scope: scope} = socket.assigns
    file_path = params["file_path"]
    comment_scope = params["scope"] || "line"

    attrs =
      %{
        "start_line" => params["start_line"] || 0,
        "end_line" => params["end_line"] || 0,
        "body" => body,
        "scope" => comment_scope
      }
      |> then(fn a ->
        if q = params["quote"], do: Map.put(a, "quote", q), else: a
      end)

    case Reviews.create_comment(scope, review, attrs, file_path: file_path) do
      {:ok, comment} ->
        payload = %{comment: Reviews.serialize_comment(comment)}
        socket = push_event(socket, "comment_added", payload)
        broadcast_from_review(socket, {:comment_added, payload})
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save comment.")}
    end
  end

  @impl true
  def handle_event("edit_comment", %{"id" => id, "body" => body}, socket) do
    %{current_scope: scope} = socket.assigns

    case Reviews.update_comment(scope, id, body) do
      {:ok, comment} ->
        payload = %{
          id: comment.id,
          body: comment.body,
          updated_at: DateTime.to_iso8601(comment.updated_at)
        }

        socket = push_event(socket, "comment_updated", payload)
        broadcast_from_review(socket, {:comment_updated, payload})
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only edit your own comments.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update comment.")}
    end
  end

  @impl true
  def handle_event("delete_comment", %{"id" => id}, socket) do
    %{current_scope: scope} = socket.assigns

    case Reviews.delete_comment(scope, id) do
      {:ok, _} ->
        payload = %{id: id}
        socket = push_event(socket, "comment_deleted", payload)
        broadcast_from_review(socket, {:comment_deleted, payload})
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
    # hook fires both this event and the POST).
    case Crit.DisplayName.normalize(name) do
      nil ->
        {:noreply, socket}

      name ->
        %{current_scope: scope} = socket.assigns
        scope = Scope.put_display_name(scope, name)

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> push_event("display_name_updated", %{display_name: name})}
    end
  end

  @impl true
  def handle_event("noop_refresh", _params, socket) do
    broadcast_full_sync(socket.assigns.review)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_reply", %{"comment_id" => comment_id, "body" => body}, socket) do
    %{review: review, current_scope: scope} = socket.assigns

    case Reviews.create_reply(scope, comment_id, %{"body" => body}, review.id) do
      {:ok, reply} ->
        payload = %{parent_id: comment_id, reply: Reviews.serialize_reply(reply)}
        socket = push_event(socket, "reply_added", payload)
        broadcast_from_review(socket, {:reply_added, payload})
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add reply.")}
    end
  end

  @impl true
  def handle_event("edit_reply", %{"id" => id, "body" => body}, socket) do
    %{current_scope: scope} = socket.assigns

    case Reviews.update_reply(scope, id, body) do
      {:ok, reply} ->
        payload = %{parent_id: reply.parent_id, id: reply.id, body: reply.body}
        socket = push_event(socket, "reply_updated", payload)
        broadcast_from_review(socket, {:reply_updated, payload})
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only edit your own replies.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update reply.")}
    end
  end

  @impl true
  def handle_event("delete_reply", %{"id" => id}, socket) do
    %{current_scope: scope} = socket.assigns

    case Reviews.delete_reply(scope, id) do
      {:ok, deleted} ->
        payload = %{parent_id: deleted.parent_id, id: id}
        socket = push_event(socket, "reply_deleted", payload)
        broadcast_from_review(socket, {:reply_deleted, payload})
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only delete your own replies.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete reply.")}
    end
  end

  @impl true
  def handle_event("resolve_comment", %{"id" => id, "resolved" => resolved}, socket) do
    %{review: review, current_scope: scope} = socket.assigns

    case Reviews.resolve_comment(scope, id, resolved, review.id) do
      {:ok, comment} ->
        payload = %{id: comment.id, resolved: comment.resolved}
        socket = push_event(socket, "comment_resolved", payload)
        broadcast_from_review(socket, {:comment_resolved, payload})
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, "Only the comment author or review owner can resolve this.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update comment.")}
    end
  end

  # Delta broadcast handle_info clauses — forward each event to the client via push_event.
  # comment_added and reply_added apply demo mode filtering; other events pass through
  # because filtered entities never entered client state (harmless no-ops on the JS side).

  @impl true
  def handle_info({:comment_added, %{comment: comment} = payload}, socket) do
    %{demo?: demo?, current_scope: scope} = socket.assigns

    if demo? and comment.author_identity not in ["imported", scope.identity] do
      {:noreply, socket}
    else
      {:noreply, push_event(socket, "comment_added", payload)}
    end
  end

  @impl true
  def handle_info({:comment_updated, payload}, socket) do
    {:noreply, push_event(socket, "comment_updated", payload)}
  end

  @impl true
  def handle_info({:comment_deleted, payload}, socket) do
    {:noreply, push_event(socket, "comment_deleted", payload)}
  end

  @impl true
  def handle_info({:comment_resolved, payload}, socket) do
    {:noreply, push_event(socket, "comment_resolved", payload)}
  end

  @impl true
  def handle_info({:reply_added, %{reply: reply} = payload}, socket) do
    %{demo?: demo?, current_scope: scope} = socket.assigns

    if demo? and reply.author_identity not in ["imported", scope.identity] do
      {:noreply, socket}
    else
      {:noreply, push_event(socket, "reply_added", payload)}
    end
  end

  @impl true
  def handle_info({:reply_updated, payload}, socket) do
    {:noreply, push_event(socket, "reply_updated", payload)}
  end

  @impl true
  def handle_info({:reply_deleted, payload}, socket) do
    {:noreply, push_event(socket, "reply_deleted", payload)}
  end

  @impl true
  def handle_info({:comments_full_sync, comments}, socket) do
    %{demo?: demo?, current_scope: scope} = socket.assigns

    filtered =
      filter_demo_serialized_comments(comments, demo?, scope.identity, Scope.user_id(scope))

    {:noreply, push_event(socket, "comments_full_sync", %{comments: filtered})}
  end

  @impl true
  def handle_info({:display_name_changed, payload}, socket) do
    {:noreply, push_event(socket, "display_name_changed", payload)}
  end

  defp broadcast_from_review(socket, message) do
    token = socket.assigns.review.token
    Phoenix.PubSub.broadcast_from(@pubsub, self(), "review:#{token}", message)
  end

  defp broadcast_full_sync(%{token: token} = review) do
    comments = Reviews.list_comments(review) |> serialize_comments()
    Phoenix.PubSub.broadcast(@pubsub, "review:#{token}", {:comments_full_sync, comments})
  end

  defp serialize_comments(comments) do
    Enum.map(comments, &Reviews.serialize_comment/1)
  end

  defp filter_demo_comments(comments, false, _identity, _user_id), do: comments

  defp filter_demo_comments(comments, true, identity, user_id) do
    keep? = fn c -> demo_visible?(c, identity, user_id) end

    comments
    |> Enum.filter(keep?)
    |> Enum.map(fn c ->
      filtered_replies =
        case c.replies do
          %Ecto.Association.NotLoaded{} -> %Ecto.Association.NotLoaded{}
          replies -> Enum.filter(replies, keep?)
        end

      %{c | replies: filtered_replies}
    end)
  end

  # Filters already-serialized comment maps (atom keys) for demo mode full sync.
  defp filter_demo_serialized_comments(comments, false, _identity, _user_id), do: comments

  defp filter_demo_serialized_comments(comments, true, identity, user_id) do
    keep? = fn c -> demo_visible?(c, identity, user_id) end

    comments
    |> Enum.filter(keep?)
    |> Enum.map(fn c ->
      %{c | replies: Enum.filter(c.replies, keep?)}
    end)
  end

  defp demo_visible?(c, identity, user_id) do
    c.author_identity in ["imported", identity] or
      (not is_nil(user_id) and Map.get(c, :user_id) == user_id)
  end

  @doc false
  def session_opts(conn) do
    %{
      "user_id" => Plug.Conn.get_session(conn, "user_id"),
      "identity" => Plug.Conn.get_session(conn, "identity"),
      "display_name" => Plug.Conn.get_session(conn, "display_name"),
      "request_path" => conn.request_path
    }
  end

  defp display_filename(%{files: [first | _]}), do: first.file_path
  defp display_filename(_), do: "Review"
end
