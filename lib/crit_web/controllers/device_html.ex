defmodule CritWeb.DeviceHTML do
  @moduledoc """
  View module for the device flow browser pages.
  Templates will be replaced by the frontend design agent.
  """
  use CritWeb, :html

  embed_templates "device_html/*"
end
