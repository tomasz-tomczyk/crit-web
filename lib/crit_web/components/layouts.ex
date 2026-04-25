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
          <svg class="h-5 w-auto" viewBox="50 -1600 3430 1650" aria-label="crit">
            <g transform="scale(1,-1)">
              <path
                d="M628 -22Q459 -22 336.5 50.5Q214 123 147.5 252.5Q81 382 81 554Q81 727 147.5 857.0Q214 987 336.5 1059.5Q459 1132 628 1132Q827 1132 960.0 1032.5Q1093 933 1125 760L846 708Q827 795 772.5 845.5Q718 896 631 896Q511 896 449.0 801.5Q387 707 387 555Q387 405 449.0 309.5Q511 214 631 214Q718 214 774.0 266.5Q830 319 848 409L1127 358Q1095 181 962.0 79.5Q829 -22 628 -22Z"
                fill="currentColor"
              /><path
                d="M128 0V1118H418V923H430Q461 1026 533.5 1079.5Q606 1133 700 1133Q751 1133 797 1123V855Q777 861 738.5 865.5Q700 870 667 870Q563 870 495.5 805.0Q428 740 428 636V0Z"
                fill="currentColor"
                transform="translate(1103,0)"
              /><path
                d="M128 0V1118H428V0ZM278 1264Q210 1264 162.0 1309.0Q114 1354 114 1418Q114 1482 162.0 1527.0Q210 1572 278 1572Q346 1572 394.5 1527.0Q443 1482 443 1418Q443 1354 394.5 1309.0Q346 1264 278 1264Z"
                fill="currentColor"
                transform="translate(1835,0)"
              /><path
                d="M683 1118V889H474V327Q474 223 576 223Q593 223 623.5 227.5Q654 232 671 236L714 11Q664 -4 614.5 -10.0Q565 -16 520 -16Q352 -16 263.0 65.5Q174 147 174 301V889H20V1118H174V1384H474V1118Z"
                fill="currentColor"
                transform="translate(2288,0)"
              /><path
                d="M342 -19Q269 -19 219.0 30.5Q169 80 169 153Q169 226 219.0 275.5Q269 325 342 325Q415 325 465.0 275.5Q515 226 515 153Q515 80 465.0 30.5Q415 -19 342 -19Z"
                fill="#7aa2f7"
                transform="translate(2936,0)"
              />
            </g>
          </svg>
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
    <header class="border-b border-(--crit-border) bg-(--crit-bg-card)">
      <div class="max-w-7xl mx-auto flex items-center justify-between px-10 py-5 max-sm:px-5 max-sm:py-4">
        <a
          href={~p"/"}
          class="text-(--crit-fg-primary) no-underline transition-colors"
        >
          <svg class="h-5 w-auto" viewBox="50 -1600 3430 1650" aria-label="crit">
            <g transform="scale(1,-1)">
              <path
                d="M628 -22Q459 -22 336.5 50.5Q214 123 147.5 252.5Q81 382 81 554Q81 727 147.5 857.0Q214 987 336.5 1059.5Q459 1132 628 1132Q827 1132 960.0 1032.5Q1093 933 1125 760L846 708Q827 795 772.5 845.5Q718 896 631 896Q511 896 449.0 801.5Q387 707 387 555Q387 405 449.0 309.5Q511 214 631 214Q718 214 774.0 266.5Q830 319 848 409L1127 358Q1095 181 962.0 79.5Q829 -22 628 -22Z"
                fill="currentColor"
              /><path
                d="M128 0V1118H418V923H430Q461 1026 533.5 1079.5Q606 1133 700 1133Q751 1133 797 1123V855Q777 861 738.5 865.5Q700 870 667 870Q563 870 495.5 805.0Q428 740 428 636V0Z"
                fill="currentColor"
                transform="translate(1103,0)"
              /><path
                d="M128 0V1118H428V0ZM278 1264Q210 1264 162.0 1309.0Q114 1354 114 1418Q114 1482 162.0 1527.0Q210 1572 278 1572Q346 1572 394.5 1527.0Q443 1482 443 1418Q443 1354 394.5 1309.0Q346 1264 278 1264Z"
                fill="currentColor"
                transform="translate(1835,0)"
              /><path
                d="M683 1118V889H474V327Q474 223 576 223Q593 223 623.5 227.5Q654 232 671 236L714 11Q664 -4 614.5 -10.0Q565 -16 520 -16Q352 -16 263.0 65.5Q174 147 174 301V889H20V1118H174V1384H474V1118Z"
                fill="currentColor"
                transform="translate(2288,0)"
              /><path
                d="M342 -19Q269 -19 219.0 30.5Q169 80 169 153Q169 226 219.0 275.5Q269 325 342 325Q415 325 465.0 275.5Q515 226 515 153Q515 80 465.0 30.5Q415 -19 342 -19Z"
                fill="#7aa2f7"
                transform="translate(2936,0)"
              />
            </g>
          </svg>
        </a>
        <nav class="flex items-center gap-6 max-sm:hidden">
          <a
            href={~p"/features"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) transition-colors"
          >
            Features
          </a>
          <a
            href={~p"/getting-started"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) transition-colors"
          >
            Get Started
          </a>
          <a
            href={~p"/self-hosting"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) transition-colors"
          >
            Self-Hosting
          </a>
          <a
            href={~p"/changelog"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) transition-colors"
          >
            Changelog
          </a>
          <a
            href="https://github.com/tomasz-tomczyk/crit"
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) transition-colors flex items-center gap-1.5"
          >
            <svg viewBox="0 0 16 16" class="size-4 fill-current" aria-hidden="true">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
            </svg>
            GitHub
          </a>
          <%= if @current_user do %>
            <a
              href={~p"/dashboard"}
              class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) transition-colors"
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
                class="text-sm text-(--crit-fg-primary) no-underline hover:text-(--crit-brand) transition-colors"
              >
                {@current_user.name || @current_user.email}
              </a>
              <.link
                href={~p"/auth/logout"}
                method="delete"
                class="text-sm text-(--crit-fg-secondary) hover:text-(--crit-fg-primary) transition-colors"
              >
                Sign out
              </.link>
            </div>
          <% else %>
            <a
              href={~p"/auth/login?return_to=/dashboard"}
              class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) transition-colors"
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
            class="p-1 text-(--crit-fg-secondary) hover:text-(--crit-fg-primary) cursor-pointer"
            aria-label="Toggle menu"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
        </div>
      </div>
      <%!-- Mobile nav dropdown --%>
      <div id="mobile-nav" class="hidden sm:hidden border-t border-(--crit-border)">
        <div class="flex flex-col gap-1 px-10 py-3">
          <a
            href={~p"/features"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) py-1.5"
          >
            Features
          </a>
          <a
            href={~p"/getting-started"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) py-1.5"
          >
            Get Started
          </a>
          <a
            href={~p"/self-hosting"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) py-1.5"
          >
            Self-Hosting
          </a>
          <a
            href={~p"/changelog"}
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) py-1.5"
          >
            Changelog
          </a>
          <a
            href="https://github.com/tomasz-tomczyk/crit"
            class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) py-1.5 flex items-center gap-1.5"
          >
            <svg viewBox="0 0 16 16" class="size-4 fill-current" aria-hidden="true">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
            </svg>
            GitHub
          </a>
          <%= if @current_user do %>
            <a
              href={~p"/dashboard"}
              class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) py-1.5"
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
              <span class="text-sm text-(--crit-fg-primary) hover:text-(--crit-brand)">
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
              class="text-sm text-(--crit-fg-secondary) no-underline hover:text-(--crit-fg-primary) py-1.5"
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
  Header for dashboard, overview, and settings pages. No marketing nav links.
  Used in both public and selfhosted modes.

  Layout: a chrome row (logo + identity popover) and a tab strip below
  (Dashboard, optional Overview, Settings). Pass `current_page` to mark
  the active tab. Sign out lives inside the identity popover on desktop
  and at the bottom of the mobile drawer.
  """
  attr :authenticated, :boolean, default: true
  attr :password_required, :boolean, default: false
  attr :current_user, :any, default: nil
  attr :show_overview_link, :boolean, default: false
  attr :current_page, :atom, default: nil

  def dashboard_header(assigns) do
    host = if assigns.show_overview_link, do: CritWeb.Endpoint.host(), else: nil

    assigns =
      assigns
      |> assign(:host, host)
      |> assign(:user_initial, user_initial(assigns.current_user))

    ~H"""
    <header class="bg-(--crit-bg-card) border-b border-(--crit-border)">
      <%!-- Chrome row: logo + scope chip (left), identity popover + theme + hamburger (right) --%>
      <div class="max-w-7xl mx-auto flex items-center justify-between gap-4 px-8 py-3.5 max-sm:px-4 max-sm:py-3">
        <div class="flex items-center gap-2.5 min-w-0">
          <a
            href={~p"/dashboard"}
            class="text-(--crit-fg-primary) no-underline inline-flex items-center -ml-1.5 px-1.5 py-1 rounded-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-(--crit-focus-ring)"
          >
            <svg class="h-[18px] w-auto" viewBox="50 -1600 3430 1650" aria-label="crit">
              <g transform="scale(1,-1)">
                <path
                  d="M628 -22Q459 -22 336.5 50.5Q214 123 147.5 252.5Q81 382 81 554Q81 727 147.5 857.0Q214 987 336.5 1059.5Q459 1132 628 1132Q827 1132 960.0 1032.5Q1093 933 1125 760L846 708Q827 795 772.5 845.5Q718 896 631 896Q511 896 449.0 801.5Q387 707 387 555Q387 405 449.0 309.5Q511 214 631 214Q718 214 774.0 266.5Q830 319 848 409L1127 358Q1095 181 962.0 79.5Q829 -22 628 -22Z"
                  fill="currentColor"
                /><path
                  d="M128 0V1118H418V923H430Q461 1026 533.5 1079.5Q606 1133 700 1133Q751 1133 797 1123V855Q777 861 738.5 865.5Q700 870 667 870Q563 870 495.5 805.0Q428 740 428 636V0Z"
                  fill="currentColor"
                  transform="translate(1103,0)"
                /><path
                  d="M128 0V1118H428V0ZM278 1264Q210 1264 162.0 1309.0Q114 1354 114 1418Q114 1482 162.0 1527.0Q210 1572 278 1572Q346 1572 394.5 1527.0Q443 1482 443 1418Q443 1354 394.5 1309.0Q346 1264 278 1264Z"
                  fill="currentColor"
                  transform="translate(1835,0)"
                /><path
                  d="M683 1118V889H474V327Q474 223 576 223Q593 223 623.5 227.5Q654 232 671 236L714 11Q664 -4 614.5 -10.0Q565 -16 520 -16Q352 -16 263.0 65.5Q174 147 174 301V889H20V1118H174V1384H474V1118Z"
                  fill="currentColor"
                  transform="translate(2288,0)"
                /><path
                  d="M342 -19Q269 -19 219.0 30.5Q169 80 169 153Q169 226 219.0 275.5Q269 325 342 325Q415 325 465.0 275.5Q515 226 515 153Q515 80 465.0 30.5Q415 -19 342 -19Z"
                  fill="#7aa2f7"
                  transform="translate(2936,0)"
                />
              </g>
            </svg>
          </a>

          <%= if @show_overview_link do %>
            <div
              role="group"
              aria-label={"Self-hosted instance: " <> @host}
              class="relative inline-flex items-stretch h-[30px] ml-1 min-w-0 max-sm:hidden text-(--crit-fg-muted) before:content-[''] before:absolute before:left-0 before:top-[7px] before:bottom-[7px] before:w-px before:bg-(--crit-border-strong)"
            >
              <span class="inline-flex items-center px-2.5">
                <span class="text-[9.5px] font-semibold uppercase tracking-[0.1em] text-(--crit-fg-muted) leading-none">
                  Self-hosted
                </span>
              </span>
              <span class="relative inline-flex items-center px-2.5 before:content-[''] before:absolute before:left-0 before:top-2 before:bottom-2 before:w-px before:bg-(--crit-border-strong)">
                <span class="font-mono text-[12.5px] font-medium text-(--crit-fg-primary) tracking-tight truncate max-w-[240px] leading-none">
                  {@host}
                </span>
              </span>
            </div>
          <% end %>
        </div>

        <div class="flex items-center gap-1.5">
          <%= if @current_user do %>
            <nav aria-label="Primary" class="flex items-center gap-0.5 max-sm:hidden">
              <.dashboard_link href={~p"/dashboard"} active={@current_page == :dashboard}>
                Dashboard
              </.dashboard_link>
              <%= if @show_overview_link do %>
                <.dashboard_link href={~p"/overview"} active={@current_page == :overview}>
                  Overview
                </.dashboard_link>
              <% end %>
            </nav>

            <span
              aria-hidden="true"
              class="w-px h-4 bg-(--crit-border-strong) mx-1.5 max-sm:hidden"
            >
            </span>

            <div class="relative max-sm:hidden">
              <button
                id="dashboard-identity-toggle"
                type="button"
                aria-haspopup="menu"
                aria-expanded="false"
                aria-controls="dashboard-identity-popover"
                phx-click={
                  JS.toggle_attribute({"hidden", "hidden"}, to: "#dashboard-identity-popover")
                  |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                }
                class="group inline-flex items-center gap-1.5 h-[30px] pl-0.5 pr-1.5 rounded-md text-(--crit-fg-secondary) hover:bg-(--crit-row-hover) hover:text-(--crit-fg-primary) aria-expanded:bg-(--crit-bg-card) aria-expanded:text-(--crit-fg-primary) cursor-pointer transition-colors focus:outline-none focus-visible:shadow-[0_0_0_2px_var(--crit-bg-page),0_0_0_4px_var(--crit-focus-ring)]"
                aria-label="Account menu"
              >
                <%= if @current_user.avatar_url do %>
                  <img
                    src={@current_user.avatar_url}
                    alt=""
                    class="h-6 w-6 rounded-full flex-shrink-0"
                  />
                <% else %>
                  <span class="h-6 w-6 rounded-full bg-(--crit-brand-bg) text-(--crit-brand) inline-flex items-center justify-center text-[10.5px] font-semibold flex-shrink-0">
                    {@user_initial}
                  </span>
                <% end %>
                <.icon
                  name="hero-chevron-down-micro"
                  class="size-3 text-(--crit-fg-muted) transition-transform group-aria-expanded:rotate-180 group-aria-expanded:text-(--crit-fg-secondary) flex-shrink-0"
                />
              </button>

              <div
                id="dashboard-identity-popover"
                role="menu"
                aria-labelledby="dashboard-identity-toggle"
                hidden
                phx-hook=".IdentityPopover"
                class="absolute right-0 top-[calc(100%+8px)] min-w-[280px] bg-(--crit-popover-bg) border border-(--crit-border-strong) rounded-[10px] p-1.5 z-40 shadow-[var(--crit-popover-shadow)]"
              >
                <script :type={Phoenix.LiveView.ColocatedHook} name=".IdentityPopover">
                  export default {
                    mounted() {
                      this.onDocClick = (e) => {
                        if (this.el.hidden) return
                        const trigger = document.getElementById("dashboard-identity-toggle")
                        if (this.el.contains(e.target) || trigger?.contains(e.target)) return
                        this.el.hidden = true
                        trigger?.setAttribute("aria-expanded", "false")
                      }
                      this.onKey = (e) => {
                        if (e.key === "Escape" && !this.el.hidden) {
                          this.el.hidden = true
                          document.getElementById("dashboard-identity-toggle")
                            ?.setAttribute("aria-expanded", "false")
                        }
                      }
                      document.addEventListener("click", this.onDocClick)
                      document.addEventListener("keydown", this.onKey)
                    },
                    destroyed() {
                      document.removeEventListener("click", this.onDocClick)
                      document.removeEventListener("keydown", this.onKey)
                    }
                  }
                </script>
                <div class="flex gap-3 items-start px-3 pt-3 pb-3.5">
                  <%= if @current_user.avatar_url do %>
                    <img
                      src={@current_user.avatar_url}
                      alt=""
                      class="h-9 w-9 rounded-md flex-shrink-0"
                    />
                  <% else %>
                    <span class="h-9 w-9 rounded-md bg-(--crit-brand-bg) text-(--crit-brand) inline-flex items-center justify-center text-[13px] font-semibold flex-shrink-0">
                      {@user_initial}
                    </span>
                  <% end %>
                  <div class="flex flex-col gap-0.5 min-w-0">
                    <span class="text-[13px] font-semibold text-(--crit-fg-primary) leading-tight">
                      {@current_user.name || @current_user.email}
                    </span>
                    <%= if @current_user.name && @current_user.email do %>
                      <span class="text-xs text-(--crit-fg-muted) leading-tight truncate max-w-[200px]">
                        {@current_user.email}
                      </span>
                    <% end %>
                  </div>
                </div>

                <div class="h-px bg-(--crit-border) my-0.5"></div>

                <div class="text-[10.5px] uppercase tracking-wider text-(--crit-fg-muted) font-semibold px-3 pt-2 pb-1">
                  Account
                </div>
                <.link
                  navigate={~p"/settings"}
                  role="menuitem"
                  class="flex items-center gap-2.5 px-2.5 py-1.5 rounded-md text-[13px] text-(--crit-fg-primary) hover:bg-(--crit-row-hover) no-underline"
                >
                  <.icon name="hero-cog-6-tooth-mini" class="size-3.5 text-(--crit-fg-muted)" />
                  <span>Settings</span>
                </.link>

                <div class="h-px bg-(--crit-border) my-0.5"></div>

                <.link
                  href={~p"/auth/logout"}
                  method="delete"
                  role="menuitem"
                  class="flex items-center gap-2.5 px-2.5 py-1.5 rounded-md text-[13px] text-(--crit-red) hover:bg-(--crit-btn-danger-hover-bg) no-underline"
                >
                  <.icon name="hero-arrow-right-on-rectangle-mini" class="size-3.5" />
                  <span>Sign out</span>
                </.link>
              </div>
            </div>
          <% else %>
            <%= if @password_required and not @authenticated do %>
              <a
                href="#login"
                class="text-sm text-(--crit-fg-secondary) hover:text-(--crit-fg-primary) transition-colors max-sm:hidden"
              >
                Sign in
              </a>
            <% end %>
          <% end %>

          <.theme_toggle />

          <button
            id="dashboard-nav-toggle"
            type="button"
            phx-click={JS.toggle_attribute({"hidden", "hidden"}, to: "#dashboard-nav")}
            class="sm:hidden p-1.5 rounded-md text-(--crit-fg-secondary) hover:text-(--crit-fg-primary) hover:bg-(--crit-row-hover) cursor-pointer"
            aria-label="Toggle menu"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
        </div>
      </div>

      <%!-- Mobile drawer --%>
      <div
        id="dashboard-nav"
        hidden
        class="sm:hidden bg-(--crit-bg-card) border-t border-(--crit-border)"
      >
        <div class="flex flex-col gap-px px-3 pt-2 pb-3.5">
          <%= if @current_user do %>
            <div class="flex items-center gap-3 px-3 py-3 border-b border-(--crit-border) mb-1.5">
              <%= if @current_user.avatar_url do %>
                <img src={@current_user.avatar_url} alt="" class="h-9 w-9 rounded-md flex-shrink-0" />
              <% else %>
                <span class="h-9 w-9 rounded-md bg-(--crit-brand-bg) text-(--crit-brand) inline-flex items-center justify-center text-[13px] font-semibold flex-shrink-0">
                  {@user_initial}
                </span>
              <% end %>
              <div class="flex flex-col gap-0.5 min-w-0">
                <span class="text-sm font-semibold text-(--crit-fg-primary) truncate">
                  {@current_user.name || @current_user.email}
                </span>
                <%= if @current_user.name && @current_user.email do %>
                  <span class="text-xs text-(--crit-fg-muted) truncate">
                    {@current_user.email}
                  </span>
                <% end %>
              </div>
            </div>

            <div class="text-[10.5px] uppercase tracking-wider text-(--crit-fg-muted) font-semibold px-2 pt-2 pb-1">
              Navigate
            </div>
            <.dashboard_mobile_link href={~p"/dashboard"} active={@current_page == :dashboard}>
              Dashboard
            </.dashboard_mobile_link>
            <%= if @show_overview_link do %>
              <.dashboard_mobile_link href={~p"/overview"} active={@current_page == :overview}>
                Overview
              </.dashboard_mobile_link>
            <% end %>

            <div class="text-[10.5px] uppercase tracking-wider text-(--crit-fg-muted) font-semibold px-2 pt-2 pb-1">
              Account
            </div>
            <.dashboard_mobile_link navigate={~p"/settings"} active={@current_page == :settings}>
              Settings
            </.dashboard_mobile_link>

            <.link
              href={~p"/auth/logout"}
              method="delete"
              class="flex items-center gap-3 px-2 py-2.5 rounded-md text-sm text-(--crit-red) no-underline hover:bg-(--crit-btn-danger-hover-bg)"
            >
              <.icon name="hero-arrow-right-on-rectangle-mini" class="size-4" />
              <span>Sign out</span>
            </.link>
          <% else %>
            <%= if @password_required and @authenticated do %>
              <.form for={%{}} action={~p"/auth/logout"} method="post" id="logout-form-mobile">
                <button
                  type="submit"
                  class="text-sm text-(--crit-red) hover:opacity-80 transition-opacity cursor-pointer py-2 px-2"
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

  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp dashboard_link(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "inline-flex items-center h-[30px] px-2.5 rounded-md text-[13px] font-medium tracking-tight no-underline transition-colors",
        if(@active,
          do: "text-(--crit-fg-primary) bg-(--crit-bg-card) hover:bg-(--crit-bg-elevated)",
          else:
            "text-(--crit-fg-secondary) hover:text-(--crit-fg-primary) hover:bg-(--crit-row-hover)"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp dashboard_mobile_link(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "flex items-center gap-3 px-2 py-2.5 rounded-md text-sm font-medium no-underline",
        if(@active,
          do: "bg-(--crit-brand-bg) text-(--crit-brand)",
          else: "text-(--crit-fg-primary) hover:bg-(--crit-row-hover)"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp user_initial(%{name: name}) when is_binary(name) and name != "",
    do: name |> String.first() |> String.upcase()

  defp user_initial(%{email: email}) when is_binary(email) and email != "",
    do: email |> String.first() |> String.upcase()

  defp user_initial(_), do: "?"

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
      class="relative flex flex-row items-center border border-(--crit-border) bg-(--crit-bg-elevated) rounded-full"
      role="radiogroup"
      aria-label="Theme"
    >
      <div class="absolute w-1/3 h-full rounded-full border border-(--crit-border-strong) bg-(--crit-bg-card) left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

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
