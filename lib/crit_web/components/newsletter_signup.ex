defmodule CritWeb.NewsletterSignup do
  use CritWeb, :html

  attr :form, Phoenix.HTML.Form, required: true
  attr :id, :string, required: true
  attr :source, :string, default: "archive", values: ~w(homepage archive footer)
  attr :source_path, :string, default: nil
  attr :compact, :boolean, default: false
  attr :message, :string, default: nil
  attr :appearance, :string, default: "quiet", values: ~w(quiet filled)
  attr :show_note, :boolean, default: true

  def signup(assigns) do
    ~H"""
    <div>
      <p
        :if={@message}
        id={"#{@id}-status"}
        role="status"
        class="mb-4 text-sm text-(--crit-fg-secondary)"
      >
        {@message}
      </p>
      <.form
        for={@form}
        id={@id}
        action={~p"/newsletter/subscribe"}
        class={["flex items-start gap-2", !@compact && "max-sm:flex-col"]}
      >
        <input type="hidden" name={@form[:source].name} value={@source} />
        <input :if={@source_path} type="hidden" name={@form[:source_path].name} value={@source_path} />
        <div class="flex-1 w-full min-w-0">
          <.input
            field={@form[:email]}
            id={"#{@id}-email"}
            type="email"
            aria-label="Email address"
            placeholder="you@example.com"
            autocomplete="email"
            required
            maxlength="160"
            class={[
              "w-full rounded-md border border-(--crit-border) text-(--crit-fg-primary) placeholder:text-(--crit-fg-muted) focus:outline-2 focus:outline-(--crit-brand)",
              @compact && "min-h-9 px-3 py-1.5 text-sm max-sm:min-h-11 max-sm:text-base",
              !@compact && "min-h-11 px-3 py-2 text-base",
              @appearance == "filled" && "bg-(--crit-bg-page)",
              @appearance == "quiet" && "bg-transparent"
            ]}
          />
        </div>
        <button
          type="submit"
          class={[
            "shrink-0 rounded-md border transition-colors cursor-pointer",
            @compact && "min-h-9 px-3 py-1.5 text-sm max-sm:min-h-11",
            !@compact && "min-h-11 px-4 py-2 text-sm",
            @appearance == "quiet" &&
              "border-(--crit-border) text-(--crit-fg-secondary) hover:text-(--crit-fg-primary) hover:border-(--crit-fg-muted)",
            @appearance == "filled" &&
              "border-(--crit-border-strong) bg-(--crit-bg-elevated) text-(--crit-fg-primary) font-medium hover:opacity-90 [html[data-theme=light]_&]:border-(--crit-fg-primary) [html[data-theme=light]_&]:bg-(--crit-fg-primary) [html[data-theme=light]_&]:text-(--crit-bg-page) [@media(prefers-color-scheme:light)]:[html:not([data-theme])_&]:border-(--crit-fg-primary) [@media(prefers-color-scheme:light)]:[html:not([data-theme])_&]:bg-(--crit-fg-primary) [@media(prefers-color-scheme:light)]:[html:not([data-theme])_&]:text-(--crit-bg-page)",
            !@compact && "max-sm:w-full"
          ]}
        >Subscribe</button>
      </.form>
      <p :if={@show_note && !@compact} class="mt-2 text-xs text-(--crit-fg-secondary) leading-relaxed">
        No account needed.
        Unsubscribe anytime.
        <a href={~p"/privacy"} class="underline hover:text-(--crit-fg-secondary)">Privacy</a>
      </p>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :latest_issue, :map, default: nil

  def homepage(assigns) do
    ~H"""
    <section id="newsletter" aria-labelledby="newsletter-title" class="py-8 max-sm:py-6">
      <div class="max-w-7xl mx-auto w-full px-10 max-sm:px-4">
        <div class="rounded-xl border border-(--crit-border) bg-(--crit-bg-card) px-7 pt-7 pb-4 max-sm:px-5 max-sm:pt-5 max-sm:pb-3">
          <div class="flex items-start gap-10 max-md:flex-col max-md:gap-5">
            <div class="flex items-start gap-3 flex-1 min-w-0 pt-1">
              <span class="text-(--crit-brand) shrink-0 pt-0.5" aria-hidden="true">
                <.icon name="hero-envelope" class="size-5" />
              </span>
              <div>
                <h2 id="newsletter-title" class="text-base font-semibold tracking-tight">
                  Email me about new features and releases
                </h2>
                <p class="mt-1 text-sm text-(--crit-fg-secondary)">
                  Occasional product notes, delivered to your inbox.
                  We email only when it's actually worth your time.
                </p>
              </div>
            </div>
            <div class="w-full max-w-xl max-md:max-w-none">
              <.signup
                form={@form}
                id="homepage-newsletter"
                source="homepage"
                source_path="/"
                appearance="filled"
                show_note={false}
              />
            </div>
          </div>
          <div class="mt-5 pt-3 border-t border-(--crit-border) flex items-center gap-x-5 gap-y-1 flex-wrap max-sm:gap-x-3">
            <span
              :if={@latest_issue}
              class="font-mono text-[11px] text-(--crit-fg-secondary) shrink-0"
            >Latest</span>
            <time
              :if={@latest_issue}
              datetime={Date.to_iso8601(@latest_issue.published_at)}
              class="text-xs text-(--crit-fg-secondary) shrink-0 max-sm:hidden"
            >
              {Calendar.strftime(@latest_issue.published_at, "%-d %b %Y")}
            </time>
            <a
              :if={@latest_issue}
              href={~p"/newsletter/#{@latest_issue.slug}"}
              class="flex items-center gap-2 min-h-11 text-sm text-(--crit-fg-primary) hover:text-(--crit-brand) transition-colors max-sm:order-3 max-sm:basis-full"
            >
              {@latest_issue.title}
              <span class="shrink-0" aria-hidden="true">&rarr;</span>
            </a>
            <a
              href={~p"/newsletter"}
              class="inline-flex items-center gap-1.5 min-h-11 text-xs text-(--crit-fg-secondary) hover:text-(--crit-brand) transition-colors shrink-0 ml-auto"
            >
              Previous newsletters <span aria-hidden="true">&rarr;</span>
            </a>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
