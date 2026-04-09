defmodule CritWeb.ReviewController do
  use CritWeb, :controller

  def set_name(conn, %{"name" => name}) do
    case Crit.DisplayName.normalize(name) do
      nil ->
        conn |> put_status(422) |> json(%{error: "name cannot be blank"})

      name ->
        identity = get_session(conn, "identity")

        if identity do
          Crit.Reviews.update_display_name(identity, name)

          for {_id, token} <- Crit.Reviews.reviews_for_identity(identity) do
            Phoenix.PubSub.broadcast(
              Crit.PubSub,
              "review:#{token}",
              {:display_name_changed, %{identity: identity, name: name}}
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
