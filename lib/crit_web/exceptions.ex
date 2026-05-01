defmodule CritWeb.NotFoundError do
  @moduledoc """
  Raised to render the 404 page. Phoenix's `render_errors` config
  (see `config/config.exs`) catches exceptions whose `plug_status`
  is 404 and renders `CritWeb.ErrorHTML` with template `"404"`.
  """
  defexception message: "not found", plug_status: 404
end
