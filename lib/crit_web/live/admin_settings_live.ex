defmodule CritWeb.AdminSettingsLive do
  use CritWeb, :live_view

  alias Crit.Settings

  @impl true
  def mount(_params, _session, socket) do
    setting = Settings.get()

    socket =
      socket
      |> assign(:page_title, "Admin — Settings")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:setting, setting)
      |> assign(:form, build_form(setting))

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("validate", %{"setting" => params}, socket) do
    changeset =
      socket.assigns.setting
      |> Settings.change(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "setting"))}
  end

  @impl true
  def handle_event("save", %{"setting" => params}, socket) do
    case Settings.update(params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(:setting, setting)
         |> assign(:form, build_form(setting))
         |> put_flash(:info, "Settings updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "setting"))}
    end
  end

  # Seed the virtual MB / KB fields from the persisted byte values so the form
  # opens showing `10` (MB) and `50` (KB) rather than blanks.
  defp build_form(setting) do
    setting = %{
      setting
      | max_document_mb: Crit.Setting.bytes_to_mb(setting.max_document_bytes),
        max_comment_body_kb: Crit.Setting.bytes_to_kb(setting.max_comment_body_bytes)
    }

    to_form(Settings.change(setting), as: "setting")
  end
end
