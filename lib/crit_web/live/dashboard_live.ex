defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.{Accounts, Reviews}
  alias Crit.Organizations

  import CritWeb.Helpers, only: [time_ago: 1, split_path: 1, activity_status: 1]
  import CritWeb.Components.MarketingToggle

  @recent_review_limit 4

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    user = scope.user

    {recent_reviews, review_count} =
      Reviews.list_user_reviews_paginated(scope, page: 1, per_page: @recent_review_limit)

    orgs = Organizations.list_user_organizations(scope)

    socket =
      socket
      |> assign(:page_title, "Dashboard - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:instance_url, CritWeb.Endpoint.url())
      |> assign(:marketing_opted_in, Accounts.marketing_opted_in?(user))
      |> assign(:orgs, orgs)
      |> assign(:recent_reviews, recent_reviews)
      |> assign(:review_count, review_count)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("toggle_marketing_consent", _params, socket) do
    case Accounts.toggle_marketing_consent(
           socket.assigns.current_scope.user,
           "dashboard_checkbox"
         ) do
      {:ok, new_value} ->
        {:noreply, assign(socket, :marketing_opted_in, new_value)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference.")}
    end
  end

  @doc false
  attr :id, :string, required: true
  attr :panel_prefix, :string, default: ""
  attr :selfhosted, :boolean, required: true
  attr :instance_url, :string, required: true
  attr :class, :string, default: nil

  def onboarding_steps(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".OnboardingTabs"
      data-panel-prefix={@panel_prefix}
      phx-update="ignore"
      class={@class}
    >
      <script :type={Phoenix.LiveView.ColocatedHook} name=".OnboardingTabs">
        function switchTab(container, tabSelector, panelSelector, tab, prefix) {
          const target = tab.dataset.target
          container.querySelectorAll(tabSelector).forEach(t => {
            t.classList.remove("border-(--crit-brand)", "text-(--crit-brand)")
            t.classList.add("border-transparent", "text-(--crit-fg-muted)")
          })
          tab.classList.remove("border-transparent", "text-(--crit-fg-muted)")
          tab.classList.add("border-(--crit-brand)", "text-(--crit-brand)")
          container.querySelectorAll(panelSelector).forEach(p => p.classList.add("hidden"))
          const panel = container.querySelector("#" + prefix + target)
          if (panel) panel.classList.remove("hidden")
        }
        export default {
          mounted() {
            const prefix = this.el.dataset.panelPrefix || ""
            this.el.addEventListener("click", (e) => {
              const installTab = e.target.closest(".install-tab")
              if (installTab) switchTab(this.el, ".install-tab", ".install-panel", installTab, prefix)
              const agentTab = e.target.closest(".agent-tab")
              if (agentTab) switchTab(this.el, ".agent-tab", ".agent-panel", agentTab, prefix)
              const copyBtn = e.target.closest(".copy-btn, .agent-copy-btn")
              if (copyBtn) {
                let text
                if (copyBtn.dataset.copy) {
                  text = copyBtn.dataset.copy
                } else {
                  const pre = copyBtn.closest("div")?.querySelector("pre")
                  if (pre) text = pre.textContent.replace(/^\$ /, "").replace(/ or .*$/, "").split("\n")[0].trim()
                }
                if (text) {
                  navigator.clipboard.writeText(text).then(() => {
                    const defaultIcon = copyBtn.querySelector(".icon-default")
                    const copiedIcon = copyBtn.querySelector(".icon-copied")
                    if (defaultIcon) defaultIcon.classList.add("hidden")
                    if (copiedIcon) copiedIcon.classList.remove("hidden")
                    setTimeout(() => {
                      if (defaultIcon) defaultIcon.classList.remove("hidden")
                      if (copiedIcon) copiedIcon.classList.add("hidden")
                    }, 2000)
                  }).catch(() => {})
                }
              }
            })
          }
        }
      </script>

      <div class="max-w-[640px] mx-auto">
        <%!-- Hero --%>
        <div class="text-center mb-12">
          <h2 class="text-2xl font-bold tracking-tight mb-2.5">
            Get your first review on the web
          </h2>
          <p class="text-xl max-sm:text-base leading-relaxed text-(--crit-fg-secondary) max-w-2xl mx-auto mb-10">
            Install crit, connect your agent, share your review in one command.
          </p>
        </div>

        <%!-- Steps --%>
        <div class="flex flex-col">
          <%!-- Step 1: Install --%>
          <div class="grid grid-cols-[40px_1fr] gap-x-5 max-sm:block">
            <div class="flex flex-col items-center max-sm:hidden">
              <div class="w-8 h-8 rounded-full border-[1.5px] border-(--crit-border-strong) bg-(--crit-bg-card) flex items-center justify-center text-sm font-semibold text-(--crit-fg-secondary) shrink-0 relative z-[1]">
                1
              </div>
              <div class="w-px flex-1 bg-(--crit-border) min-h-5"></div>
            </div>
            <div class="pb-8 min-w-0">
              <div class="text-xl font-bold tracking-tight leading-8">
                <span class="sm:hidden text-(--crit-fg-muted) font-normal mr-1.5">1.</span>Install crit
              </div>
              <div class="mt-3">
                <CritWeb.PageHTML.install_widget />
              </div>
            </div>
          </div>

          <%!-- Step 2: Connect your agent --%>
          <div class="grid grid-cols-[40px_1fr] gap-x-5 max-sm:block">
            <div class="flex flex-col items-center max-sm:hidden">
              <div class="w-8 h-8 rounded-full border-[1.5px] border-(--crit-border-strong) bg-(--crit-bg-card) flex items-center justify-center text-sm font-semibold text-(--crit-fg-secondary) shrink-0 relative z-[1]">
                2
              </div>
              <div class="w-px flex-1 bg-(--crit-border) min-h-5"></div>
            </div>
            <div class="pb-8 min-w-0">
              <div class="text-xl font-bold tracking-tight leading-8">
                <span class="sm:hidden text-(--crit-fg-muted) font-normal mr-1.5">2.</span>Connect your agent
              </div>
              <div class="mt-3">
                <CritWeb.PageHTML.agent_setup_widget />
              </div>
            </div>
          </div>

          <%= if @selfhosted do %>
            <%!-- Step 3 (selfhosted): Point crit at this instance --%>
            <div class="grid grid-cols-[40px_1fr] gap-x-5 max-sm:block">
              <div class="flex flex-col items-center max-sm:hidden">
                <div class="w-8 h-8 rounded-full border-[1.5px] border-(--crit-border-strong) bg-(--crit-bg-card) flex items-center justify-center text-sm font-semibold text-(--crit-fg-secondary) shrink-0 relative z-[1]">
                  3
                </div>
                <div class="w-px flex-1 bg-(--crit-border) min-h-5"></div>
              </div>
              <div class="pb-8 min-w-0">
                <div class="text-xl font-bold tracking-tight leading-8">
                  <span class="sm:hidden text-(--crit-fg-muted) font-normal mr-1.5">3.</span>Point crit at this instance
                </div>
                <p
                  class="mt-1.5 text-sm text-(--crit-fg-secondary) leading-relaxed"
                  phx-no-format
                >
                  By default, crit shares to <code class="font-mono text-sm text-(--crit-brand) bg-(--crit-brand-subtle) px-1 py-0.5 rounded">crit.md</code>. Set <code class="font-mono text-sm text-(--crit-brand) bg-(--crit-brand-subtle) px-1 py-0.5 rounded">share_url</code>
                  so it talks to this self-hosted instance instead.
                </p>

                <div class="mt-3 flex items-center border border-(--crit-border) rounded-md overflow-hidden bg-(--crit-code-bg)">
                  <pre class="flex-1 font-mono text-sm text-(--crit-fg-primary) m-0 px-4 py-3 overflow-x-auto whitespace-pre"><span class="text-(--crit-fg-muted) select-none">$ </span>export CRIT_SHARE_URL={@instance_url}</pre>
                  <button
                    class="copy-btn shrink-0 p-3 cursor-pointer text-(--crit-fg-muted) hover:text-(--crit-fg-primary) transition-colors"
                    aria-label="Copy to clipboard"
                    data-copy={"export CRIT_SHARE_URL=#{@instance_url}"}
                  >
                    <.icon name="hero-clipboard" class="size-4 icon-default" />
                    <.icon
                      name="hero-clipboard-document-check"
                      class="size-4 icon-copied hidden"
                    />
                  </button>
                </div>

                <p class="mt-2 text-xs text-(--crit-fg-muted) leading-relaxed">
                  Or pass <code class="font-mono">--share-url</code>
                  per command, or set <code class="font-mono">share_url</code>
                  in <code class="font-mono">~/.crit.config.json</code>.
                </p>
              </div>
            </div>
          <% end %>

          <%!-- Step: Log in --%>
          <div class="grid grid-cols-[40px_1fr] gap-x-5 max-sm:block">
            <div class="flex flex-col items-center max-sm:hidden">
              <div class="w-8 h-8 rounded-full border-[1.5px] border-(--crit-border-strong) bg-(--crit-bg-card) flex items-center justify-center text-sm font-semibold text-(--crit-fg-secondary) shrink-0 relative z-[1]">
                {if @selfhosted, do: 4, else: 3}
              </div>
              <div class="w-px flex-1 bg-(--crit-border) min-h-5"></div>
            </div>
            <div class="pb-8 min-w-0">
              <div class="text-xl font-bold tracking-tight leading-8">
                <span class="sm:hidden text-(--crit-fg-muted) font-normal mr-1.5">{if @selfhosted, do: 4, else: 3}.</span>Log in
              </div>
              <p class="mt-1.5 text-sm text-(--crit-fg-secondary) leading-relaxed" phx-no-format>
                Run <code class="font-mono text-sm text-(--crit-brand) bg-(--crit-brand-subtle) px-1 py-0.5 rounded">crit auth login</code>
                to link shared reviews to your account. Opens your browser for a one-time confirmation.
              </p>

              <div class="mt-3 flex items-center border border-(--crit-border) rounded-md overflow-hidden bg-(--crit-code-bg)">
                <pre class="flex-1 font-mono text-sm text-(--crit-fg-primary) m-0 px-4 py-3 overflow-x-auto whitespace-pre"><span class="text-(--crit-fg-muted) select-none">$ </span>crit auth login</pre>
                <button
                  class="copy-btn shrink-0 p-3 cursor-pointer text-(--crit-fg-muted) hover:text-(--crit-fg-primary) transition-colors"
                  aria-label="Copy to clipboard"
                  data-copy="crit auth login"
                >
                  <.icon name="hero-clipboard" class="size-4 icon-default" />
                  <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
                </button>
              </div>
            </div>
          </div>

          <%!-- Step: Share --%>
          <div class="grid grid-cols-[40px_1fr] gap-x-5 max-sm:block">
            <div class="flex flex-col items-center max-sm:hidden">
              <div class="w-8 h-8 rounded-full border-[1.5px] border-(--crit-border-strong) bg-(--crit-bg-card) flex items-center justify-center text-sm font-semibold text-(--crit-fg-secondary) shrink-0 relative z-[1]">
                {if @selfhosted, do: 5, else: 4}
              </div>
            </div>
            <div>
              <div class="text-xl font-bold tracking-tight leading-8">
                <span class="sm:hidden text-(--crit-fg-muted) font-normal mr-1.5">{if @selfhosted, do: 5, else: 4}.</span>Share to the web
              </div>
              <p class="mt-1.5 text-sm text-(--crit-fg-secondary) leading-relaxed" phx-no-format>
                When you're ready, run <code class="font-mono text-sm text-(--crit-brand) bg-(--crit-brand-subtle) px-1 py-0.5 rounded">crit share</code>
                to upload your review to a shareable URL.
              </p>

              <%!-- Terminal snippet --%>
              <div class="mt-3 flex items-center border border-(--crit-border) rounded-md overflow-hidden bg-(--crit-code-bg)">
                <pre class="flex-1 font-mono text-sm text-(--crit-fg-primary) m-0 px-4 py-3 overflow-x-auto whitespace-pre"><span class="text-(--crit-fg-muted) select-none">$ </span>crit share<br /><span class="text-(--crit-fg-muted) italic">Shared at {if @selfhosted, do: String.replace(@instance_url, ~r{^https?://}, ""), else: "crit.md"}/r/abc123</span></pre>
              </div>

              <%!-- Share details --%>
              <div class="mt-3 flex flex-col gap-1.5">
                <div class="flex items-baseline gap-2 text-sm text-(--crit-fg-secondary) leading-normal">
                  <.icon
                    name="hero-arrows-right-left"
                    class="size-4 text-(--crit-fg-muted) shrink-0 relative top-0.5"
                  />
                  <span>Comments sync bidirectionally — web replies flow back to your CLI</span>
                </div>
                <div class="flex items-baseline gap-2 text-sm text-(--crit-fg-secondary) leading-normal">
                  <.icon
                    name="hero-arrow-path"
                    class="size-4 text-(--crit-fg-muted) shrink-0 relative top-0.5"
                  />
                  <span>Re-share anytime to update the web version with new changes</span>
                </div>
                <div class="flex items-baseline gap-2 text-sm text-(--crit-fg-secondary) leading-normal">
                  <.icon
                    name="hero-clock"
                    class="size-4 text-(--crit-fg-muted) shrink-0 relative top-0.5"
                  />
                  <span>Reviews expire after 30 days of inactivity</span>
                </div>
                <div class="flex items-baseline gap-2 text-sm text-(--crit-fg-secondary) leading-normal">
                  <.icon
                    name="hero-trash"
                    class="size-4 text-(--crit-fg-muted) shrink-0 relative top-0.5"
                  />
                  <span phx-no-format>
                    Unpublish anytime with <code class="font-mono text-sm text-(--crit-brand) bg-(--crit-brand-subtle) px-1 py-0.5 rounded">crit unpublish</code>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-10 text-center">
          <p class="text-sm text-(--crit-fg-muted)">
            Learn more in the <a href="/getting-started" class="crit-link">getting started guide</a>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
