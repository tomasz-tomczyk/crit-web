defmodule CritWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CritWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Minimal layout for the full-screen review page (no app navbar/chrome).
  Called by LiveView when `layout: {CritWeb.Layouts, :review}` is set;
  receives `@inner_content` (rendered LiveView template) in assigns.
  """
  def review(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    {@inner_content}
    """
  end

  @doc """
  Shared site header with navigation links, used across all public pages.
  """
  attr :current_user, :any, default: nil

  def site_header(assigns) do
    ~H"""
    <header class="border-b border-[var(--crit-border)] bg-[var(--crit-bg-secondary)]">
      <div class="max-w-[1100px] mx-auto flex items-center justify-between px-10 py-5 max-sm:px-5 max-sm:py-4">
        <a
          href={~p"/"}
          class="font-mono text-xl font-bold text-[var(--crit-accent)] tracking-tight no-underline hover:text-[var(--crit-accent-hover)] transition-colors"
        >
          Crit
        </a>
        <nav class="flex items-center gap-6 max-sm:hidden">
          <a
            href={~p"/features"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] transition-colors"
          >
            Features
          </a>
          <a
            href={~p"/getting-started"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] transition-colors"
          >
            Get Started
          </a>
          <a
            href={~p"/self-hosting"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] transition-colors"
          >
            Self-Hosting
          </a>
          <a
            href={~p"/changelog"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] transition-colors"
          >
            Changelog
          </a>
          <a
            href="https://github.com/tomasz-tomczyk/crit"
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] transition-colors flex items-center gap-1.5"
          >
            <svg viewBox="0 0 16 16" class="size-4 fill-current" aria-hidden="true">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
            </svg>
            GitHub
          </a>
          <%= if @current_user do %>
            <a
              href={~p"/dashboard"}
              class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] transition-colors"
            >
              Dashboard
            </a>
            <div class="flex items-center gap-3">
              <%= if @current_user.avatar_url do %>
                <img
                  src={@current_user.avatar_url}
                  alt={@current_user.name}
                  class="h-6 w-6 rounded-full"
                />
              <% end %>
              <a
                href={~p"/settings"}
                class="text-sm text-[var(--crit-fg-primary)] no-underline hover:text-[var(--crit-accent)] transition-colors"
              >
                {@current_user.name || @current_user.email}
              </a>
              <.link
                href={~p"/auth/logout"}
                method="delete"
                class="text-sm text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] transition-colors"
              >
                Sign out
              </.link>
            </div>
          <% else %>
            <a
              href={~p"/auth/login?return_to=/dashboard"}
              class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] transition-colors"
            >
              Sign in
            </a>
          <% end %>
          <.theme_toggle />
        </nav>
        <%!-- Mobile: theme toggle + hamburger --%>
        <div class="flex items-center gap-3 sm:hidden">
          <.theme_toggle />
          <button
            id="mobile-nav-toggle"
            class="p-1 text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] cursor-pointer"
            aria-label="Toggle menu"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
        </div>
      </div>
      <%!-- Mobile nav dropdown --%>
      <div id="mobile-nav" class="hidden sm:hidden border-t border-[var(--crit-border)]">
        <div class="flex flex-col gap-1 px-10 py-3">
          <a
            href={~p"/features"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-1.5"
          >
            Features
          </a>
          <a
            href={~p"/getting-started"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-1.5"
          >
            Get Started
          </a>
          <a
            href={~p"/self-hosting"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-1.5"
          >
            Self-Hosting
          </a>
          <a
            href={~p"/changelog"}
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-1.5"
          >
            Changelog
          </a>
          <a
            href="https://github.com/tomasz-tomczyk/crit"
            class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-1.5 flex items-center gap-1.5"
          >
            <svg viewBox="0 0 16 16" class="size-4 fill-current" aria-hidden="true">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
            </svg>
            GitHub
          </a>
          <%= if @current_user do %>
            <a
              href={~p"/dashboard"}
              class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-1.5"
            >
              Dashboard
            </a>
            <a
              href={~p"/settings"}
              class="flex items-center gap-2 py-1.5 no-underline"
            >
              <%= if @current_user.avatar_url do %>
                <img
                  src={@current_user.avatar_url}
                  alt={@current_user.name}
                  class="h-5 w-5 rounded-full"
                />
              <% end %>
              <span class="text-sm text-[var(--crit-fg-primary)] hover:text-[var(--crit-accent)]">
                {@current_user.name || @current_user.email}
              </span>
            </a>
            <.link
              href={~p"/auth/logout"}
              method="delete"
              class="text-sm text-red-400 hover:text-red-300 no-underline py-1.5"
            >
              Sign out
            </.link>
          <% else %>
            <a
              href={~p"/auth/login?return_to=/dashboard"}
              class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-1.5"
            >
              Sign in
            </a>
          <% end %>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Header for dashboard and admin pages. No marketing nav links.
  Used in both public and selfhosted modes.
  """
  attr :authenticated, :boolean, default: true
  attr :password_required, :boolean, default: false
  attr :current_user, :any, default: nil
  attr :show_admin_link, :boolean, default: false
  attr :show_my_reviews_link, :boolean, default: false
  attr :show_settings_link, :boolean, default: false

  def dashboard_header(assigns) do
    ~H"""
    <header class="border-b border-[var(--crit-border)] bg-[var(--crit-bg-secondary)]">
      <div class="max-w-[1100px] mx-auto flex items-center justify-between px-10 py-5 max-sm:px-5 max-sm:py-4">
        <div class="flex items-center gap-3">
          <a
            href={~p"/dashboard"}
            class="font-mono text-xl font-bold text-[var(--crit-accent)] tracking-tight no-underline hover:text-[var(--crit-accent-hover)] transition-colors"
          >
            Crit
          </a>
        </div>
        <nav class="flex items-center gap-4">
          <%= if @current_user do %>
            <div class="flex items-center gap-3 max-sm:hidden">
              <%= if @current_user.avatar_url do %>
                <img
                  src={@current_user.avatar_url}
                  alt={@current_user.name}
                  class="h-8 w-8 rounded-full"
                />
              <% end %>
              <span class="text-sm text-[var(--crit-fg-primary)]">
                {@current_user.name || @current_user.email}
              </span>
              <%= if @show_my_reviews_link do %>
                <.link
                  href={~p"/dashboard"}
                  class="text-sm text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)]"
                >
                  My Reviews
                </.link>
              <% end %>
              <%= if @show_admin_link do %>
                <.link
                  href={~p"/admin"}
                  class="text-sm text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)]"
                >
                  Admin
                </.link>
              <% end %>
              <%= if @show_settings_link do %>
                <.link
                  navigate={~p"/settings"}
                  class="text-sm text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)]"
                >
                  Settings
                </.link>
              <% end %>
              <.link
                href={~p"/auth/logout"}
                method="delete"
                class="text-sm text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)]"
              >
                Sign out
              </.link>
            </div>
          <% else %>
            <%= if @password_required and not @authenticated do %>
              <a
                href="#login"
                class="text-sm text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] transition-colors max-sm:hidden"
              >
                Sign in
              </a>
            <% end %>
          <% end %>
          <.theme_toggle />
          <button
            id="dashboard-nav-toggle"
            class="sm:hidden p-1 text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] cursor-pointer"
            aria-label="Toggle menu"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
        </nav>
      </div>
      <%!-- Mobile nav dropdown --%>
      <div id="dashboard-nav" class="hidden sm:hidden border-t border-[var(--crit-border)]">
        <div class="flex flex-col px-5 py-2">
          <%= if @show_my_reviews_link do %>
            <.link
              href={~p"/dashboard"}
              class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-2"
            >
              My Reviews
            </.link>
          <% end %>
          <%= if @show_admin_link do %>
            <.link
              href={~p"/admin"}
              class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-2"
            >
              Admin
            </.link>
          <% end %>
          <%= if @show_settings_link do %>
            <.link
              navigate={~p"/settings"}
              class="text-sm text-[var(--crit-fg-muted)] no-underline hover:text-[var(--crit-fg-primary)] py-2"
            >
              Settings
            </.link>
          <% end %>
          <%= if @current_user do %>
            <.link
              href={~p"/auth/logout"}
              method="delete"
              class="text-sm text-red-400 hover:text-red-300 no-underline py-2"
            >
              Sign out
            </.link>
          <% else %>
            <%= if @password_required and @authenticated do %>
              <.form for={%{}} action={~p"/auth/logout"} method="post" id="logout-form-mobile">
                <button
                  type="submit"
                  class="text-sm text-red-400 hover:text-red-300 transition-colors cursor-pointer py-2"
                >
                  Sign out
                </button>
              </.form>
            <% end %>
          <% end %>
        </div>
      </div>
    </header>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      class="relative flex flex-row items-center border border-[var(--crit-border)] bg-[var(--crit-bg-tertiary)] rounded-full"
      role="radiogroup"
      aria-label="Theme"
    >
      <div class="absolute w-1/3 h-full rounded-full border border-[var(--crit-border)] bg-[var(--crit-bg-hover)] left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        role="radio"
        aria-label="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        role="radio"
        aria-label="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        role="radio"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
