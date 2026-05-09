defmodule CritWeb.AdminUsersLive do
  use CritWeb, :live_view

  alias Crit.{Accounts, Authorization}

  @impl true
  def mount(_params, _session, socket) do
    users = list_sorted_users()

    socket =
      socket
      |> assign(:page_title, "Admin — Users")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:user_count, length(users))
      |> assign(:delete_target, nil)
      |> assign(:delete_confirmation, "")
      |> stream(:users, users)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("request_delete", %{"id" => id}, socket) do
    case Accounts.get_user(id) do
      {:ok, target} ->
        {:noreply,
         socket
         |> assign(:delete_target, target)
         |> assign(:delete_confirmation, "")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "User not found.")}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:delete_target, nil)
     |> assign(:delete_confirmation, "")}
  end

  def handle_event("validate_delete", %{"confirmation" => confirmation}, socket) do
    {:noreply, assign(socket, :delete_confirmation, confirmation)}
  end

  def handle_event("confirm_delete", %{"confirmation" => confirmation}, socket) do
    scope = socket.assigns.current_scope
    target = socket.assigns.delete_target

    cond do
      is_nil(target) ->
        {:noreply, socket}

      not email_matches?(target, confirmation) ->
        {:noreply,
         socket
         |> assign(:delete_confirmation, confirmation)
         |> put_flash(:error, "Email does not match.")}

      not Authorization.can?(scope, :delete_user, target) ->
        {:noreply, put_flash(socket, :error, "Not allowed.")}

      true ->
        do_delete(socket, scope, target)
    end
  end

  defp do_delete(socket, scope, target) do
    case Accounts.delete_user(target) do
      :ok ->
        socket =
          socket
          |> stream_delete(:users, target)
          |> assign(:user_count, max(socket.assigns.user_count - 1, 0))
          |> assign(:delete_target, nil)
          |> assign(:delete_confirmation, "")
          |> put_flash(:info, "User deleted.")

        if target.id == scope.user.id do
          {:noreply, redirect(socket, to: "/")}
        else
          {:noreply, socket}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete user.")}
    end
  end

  defp email_matches?(%{email: email}, confirmation)
       when is_binary(email) and is_binary(confirmation) do
    String.downcase(String.trim(confirmation)) == String.downcase(email)
  end

  defp email_matches?(_, _), do: false

  defp list_sorted_users do
    Accounts.list_users()
    |> Enum.sort_by(fn u ->
      # admins first (false sorts before true → invert), then newest first
      {u.role != :admin, -DateTime.to_unix(u.inserted_at)}
    end)
  end
end
