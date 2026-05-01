defmodule CritWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use CritWeb, :html

  embed_templates "error_html/*"

  # Fallback for any template without a dedicated .heex file (e.g. 500).
  # Phoenix.Controller.status_message_from_template/1 returns the standard
  # text like "Internal Server Error".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
