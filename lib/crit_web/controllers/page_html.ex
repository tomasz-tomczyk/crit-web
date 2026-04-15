defmodule CritWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use CritWeb, :html

  embed_templates "page_html/*"

  @doc "Converts `backtick` spans in plain text to styled <code> elements."
  def inline_code(text) do
    Regex.split(~r/`([^`]+)`/, text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/^`([^`]+)`$/, part) do
        [_, code] ->
          Phoenix.HTML.raw(
            "<code class=\"font-mono text-[0.9em] text-[var(--crit-accent)] bg-[var(--crit-bg-tertiary)] px-1 py-0.5 rounded\">#{Phoenix.HTML.html_escape(code) |> Phoenix.HTML.safe_to_string()}</code>"
          )

        nil ->
          text_escaped = Phoenix.HTML.html_escape(part) |> Phoenix.HTML.safe_to_string()
          Phoenix.HTML.raw(text_escaped)
      end
    end)
    |> Enum.map(&Phoenix.HTML.safe_to_string/1)
    |> Enum.join()
    |> Phoenix.HTML.raw()
  end

  def format_stat(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 1)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 0) |> trunc()} KB"
      true -> "#{bytes} B"
    end
  end

  def install_widget(assigns) do
    ~H"""
    <div class="flex gap-0 border-b border-[var(--crit-border)]">
      <button
        class="install-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 border-(--crit-accent) text-(--crit-accent) transition-colors cursor-pointer bg-transparent"
        data-target="tab-brew"
      >
        Homebrew
      </button>
      <button
        class="install-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 border-transparent text-(--crit-fg-muted) hover:text-(--crit-fg-secondary) transition-colors cursor-pointer bg-transparent"
        data-target="tab-go"
      >
        Go
      </button>
      <button
        class="install-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 border-transparent text-(--crit-fg-muted) hover:text-(--crit-fg-secondary) transition-colors cursor-pointer bg-transparent"
        data-target="tab-nix"
      >
        Nix
      </button>
    </div>

    <div
      id="tab-brew"
      class="install-panel border border-t-0 border-[var(--crit-border)] rounded-b-md overflow-hidden"
    >
      <div class="flex items-center bg-[var(--crit-code-bg)]">
        <pre class="flex-1 font-mono text-sm text-[var(--crit-fg-primary)] m-0 px-5 py-3.5 overflow-x-auto"><span class="text-[var(--crit-fg-muted)] select-none">$ </span>brew install tomasz-tomczyk/tap/crit</pre>
        <button
          class="copy-btn shrink-0 p-3 cursor-pointer text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] transition-colors"
          aria-label="Copy to clipboard"
        >
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </button>
      </div>
    </div>

    <div
      id="tab-go"
      class="install-panel hidden border border-t-0 border-[var(--crit-border)] rounded-b-md overflow-hidden"
    >
      <div class="flex items-center bg-[var(--crit-code-bg)]">
        <pre class="flex-1 font-mono text-sm text-[var(--crit-fg-primary)] m-0 px-5 py-3.5 overflow-x-auto"><span class="text-[var(--crit-fg-muted)] select-none">$ </span>go install github.com/tomasz-tomczyk/crit@latest</pre>
        <button
          class="copy-btn shrink-0 p-3 cursor-pointer text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] transition-colors"
          aria-label="Copy to clipboard"
        >
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </button>
      </div>
    </div>

    <div
      id="tab-nix"
      class="install-panel hidden border border-t-0 border-[var(--crit-border)] rounded-b-md overflow-hidden"
    >
      <div class="flex items-center bg-[var(--crit-code-bg)]">
        <pre class="flex-1 font-mono text-sm text-[var(--crit-fg-primary)] m-0 px-5 py-3.5 overflow-x-auto"><span class="text-[var(--crit-fg-muted)] select-none">$ </span>nix profile install github:tomasz-tomczyk/crit</pre>
        <button
          class="copy-btn shrink-0 p-3 cursor-pointer text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] transition-colors"
          aria-label="Copy to clipboard"
        >
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </button>
      </div>
    </div>

    <div class="mt-3 flex items-center gap-4">
      <div class="font-mono text-xs text-[var(--crit-fg-muted)] w-[70px] shrink-0 text-right">
        then run
      </div>
      <div class="flex-1 flex items-center border border-[var(--crit-border)] rounded-md overflow-hidden bg-[var(--crit-code-bg)]">
        <pre class="flex-1 font-mono text-sm text-[var(--crit-fg-primary)] m-0 px-5 py-3.5 overflow-x-auto"><span class="text-[var(--crit-fg-muted)] select-none">$ </span>crit<span class="text-[var(--crit-fg-muted)]"> or </span>crit plan.md</pre>
        <button
          class="copy-btn shrink-0 p-3 cursor-pointer text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] transition-colors"
          aria-label="Copy to clipboard"
        >
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </button>
      </div>
    </div>

    <p class="text-sm text-[var(--crit-fg-muted)] mt-3">
      Or download a pre-built binary from <a
        href="https://github.com/tomasz-tomczyk/crit/releases"
        class="text-[var(--crit-accent)] no-underline hover:underline"
      >GitHub Releases</a>.
    </p>
    """
  end

  @agent_installs [
    %{
      id: "claude-code",
      name: "Claude Code",
      copy: "/plugin marketplace add tomasz-tomczyk/crit\n/plugin install crit",
      lines: [
        %{type: :cmd, prompt: "> ", text: "/plugin marketplace add tomasz-tomczyk/crit"},
        %{type: :cmd, prompt: "> ", text: "/plugin install crit"},
        %{type: :output, text: "Installed crit (skills: crit, crit-cli)"}
      ]
    },
    %{
      id: "cursor",
      name: "Cursor",
      copy: "/install-plugin tomasz-tomczyk/crit",
      lines: [
        %{type: :cmd, prompt: "> ", text: "/install-plugin tomasz-tomczyk/crit"},
        %{type: :output, text: "Installed crit (skills: crit, crit-cli)"}
      ]
    },
    %{
      id: "copilot",
      name: "Copilot",
      copy: "crit install github-copilot",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install github-copilot"},
        %{type: :output, text: "Installed .github/skills/crit/SKILL.md"}
      ]
    },
    %{
      id: "codex",
      name: "Codex",
      copy: "crit install codex",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install codex"},
        %{type: :output, text: "Installed .agents/skills/crit/SKILL.md"}
      ]
    },
    %{
      id: "windsurf",
      name: "Windsurf",
      copy: "crit install windsurf",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install windsurf"},
        %{type: :output, text: "Installed .windsurf/rules/crit.md"}
      ]
    },
    %{
      id: "opencode",
      name: "OpenCode",
      copy: "crit install opencode",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install opencode"},
        %{type: :output, text: "Installed .opencode/commands/crit.md"}
      ]
    },
    %{
      id: "cline",
      name: "Cline",
      copy: "crit install cline",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install cline"},
        %{type: :output, text: "Installed .clinerules/crit.md"}
      ]
    },
    %{
      id: "aider",
      name: "Aider",
      copy: "crit install aider",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install aider"},
        %{type: :output, text: "Installed CONVENTIONS.md"}
      ]
    }
  ]

  def agent_setup_widget(assigns) do
    assigns = assign(assigns, :agents, @agent_installs)

    ~H"""
    <div class="flex gap-0 border-b border-[var(--crit-border)] overflow-x-auto">
      <button
        :for={{agent, idx} <- Enum.with_index(@agents)}
        class={[
          "agent-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 transition-colors cursor-pointer bg-transparent whitespace-nowrap",
          if(idx == 0,
            do: "border-(--crit-accent) text-(--crit-accent)",
            else: "border-transparent text-(--crit-fg-muted) hover:text-(--crit-fg-secondary)"
          )
        ]}
        data-target={"agent-#{agent.id}"}
      >
        {agent.name}
      </button>
    </div>

    <div
      :for={{agent, idx} <- Enum.with_index(@agents)}
      id={"agent-#{agent.id}"}
      class={[
        "agent-panel border border-t-0 border-[var(--crit-border)] rounded-b-md overflow-hidden",
        idx != 0 && "hidden"
      ]}
    >
      <div class="flex items-start bg-[var(--crit-code-bg)]">
        <div class="flex-1 px-5 py-3.5 font-mono text-sm min-w-0">
          <div :for={line <- agent.lines}>
            <%= if line.type == :cmd do %>
              <div>
                <span class="text-[var(--crit-fg-muted)] select-none">{line.prompt}</span>
                <span class="text-[var(--crit-fg-primary)]">{line.text}</span>
              </div>
            <% else %>
              <div class="select-none">
                <span class="text-[var(--crit-green)]">&#10003;</span>
                <span class="text-[var(--crit-fg-muted)]">{line.text}</span>
              </div>
            <% end %>
          </div>
        </div>
        <button
          class="agent-copy-btn shrink-0 p-3 mt-0.5 cursor-pointer text-[var(--crit-fg-muted)] hover:text-[var(--crit-fg-primary)] transition-colors"
          aria-label="Copy to clipboard"
          data-copy={agent.copy}
        >
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </button>
      </div>
    </div>

    <p class="text-sm text-[var(--crit-fg-muted)] mt-3">
      <a href="/integrations" class="text-[var(--crit-accent)] no-underline hover:underline">
        Full setup docs &rarr;
      </a>
    </p>
    """
  end
end
