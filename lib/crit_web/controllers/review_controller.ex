defmodule CritWeb.ReviewController do
  use CritWeb, :controller

  def set_name(conn, %{"name" => name}) do
    case Crit.DisplayName.normalize(name) do
      nil ->
        conn |> put_status(422) |> json(%{error: "name cannot be blank"})

      name ->
        scope = conn.assigns.current_scope

        if scope.identity do
          Crit.Reviews.update_display_name(scope, name)

          for {_id, token} <- Crit.Reviews.reviews_for_identity(scope) do
            Phoenix.PubSub.broadcast(
              Crit.PubSub,
              "review:#{token}",
              {:display_name_changed, %{identity: scope.identity, name: name}}
            )
          end
        end

        conn |> put_session("display_name", name) |> json(%{ok: true})
    end
  end

  def set_name(conn, _params) do
    conn |> put_status(422) |> json(%{error: "name is required"})
  end
end
