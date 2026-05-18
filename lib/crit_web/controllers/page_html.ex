defmodule CritWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use CritWeb, :html

  embed_templates "page_html/*"

  @modes [
    %{
      slug: "plans-docs",
      label: "Plans & docs",
      nav_label: "Review plans & docs",
      cmd: "files / markdown",
      screenshot: "plan",
      video: "https://assets.crit.md/plan-mode.mp4",
      blurb:
        "Your agent drafted a 300-line plan. In the terminal it's a wall of markdown. Crit renders it in the browser — comment on the section that's wrong, not the whole document.",
      bullets: ["Markdown render", "Per-line comments", "Diff every round"]
    },
    %{
      slug: "code",
      label: "Code",
      nav_label: "Review code diffs",
      cmd: "branch / pr changes",
      screenshot: "diff",
      video: "https://assets.crit.md/diff-mode.mp4",
      blurb:
        "Your agent touched 14 files across your branch. Crit auto-detects the changes, shows syntax-highlighted diffs, and lets you comment on any line — like a PR review, but instant and local.",
      bullets: ["Syntax highlighting", "Stacked PRs", "Git, jj, sapling"]
    },
    %{
      slug: "live",
      label: "Live",
      nav_label: "Review running apps",
      cmd: "running app / dev server",
      screenshot: "live",
      video: "https://assets.crit.md/live-mode.mp4",
      blurb:
        "Your agent built a frontend and it's running on localhost. Crit proxies the page into a review surface — click the button that's misaligned, pin a comment to it.",
      bullets: ["Comment on DOM", "Automatic reload", "Interactive browser"]
    },
    %{
      slug: "preview",
      label: "Preview",
      nav_label: "Review HTML artifacts",
      cmd: "static html artifact",
      screenshot: "preview",
      video: "https://assets.crit.md/preview-mode.mp4",
      blurb:
        "Your agent generated a landing page as a static HTML file. Crit renders it in an iframe so you can click elements and comment.",
      bullets: [
        "Static HTML iframe",
        "Asset siblings served",
        "No dev server needed"
      ]
    }
  ]

  def modes, do: @modes

  slot :inner_block, required: true
  attr :url, :string, required: true
  attr :tag, :string, default: nil

  def browser_chrome(assigns) do
    ~H"""
    <div class="bg-(--crit-bg-card) border border-(--crit-border) rounded-xl overflow-hidden shadow-lg relative">
      <div class="flex items-center px-4 py-3 bg-(--crit-bg-elevated) border-b border-(--crit-border)">
        <div class="flex gap-2">
          <span class="w-3 h-3 rounded-full" style="background: #f7768e;"></span>
          <span class="w-3 h-3 rounded-full" style="background: #e0af68;"></span>
          <span class="w-3 h-3 rounded-full" style="background: #56d364;"></span>
        </div>
        <div class="flex-1 flex justify-center px-4">
          <div class="bg-(--crit-bg-card) border border-(--crit-border) rounded-full px-4 py-1 font-mono text-xs text-(--crit-fg-muted) truncate max-w-[90%]">
            {@url}
          </div>
        </div>
        <div class="flex gap-1">
          <span class="w-1 h-1 rounded-full bg-(--crit-fg-muted)"></span>
          <span class="w-1 h-1 rounded-full bg-(--crit-fg-muted)"></span>
          <span class="w-1 h-1 rounded-full bg-(--crit-fg-muted)"></span>
        </div>
      </div>
      <div>
        {render_slot(@inner_block)}
      </div>
      <span
        :if={@tag}
        class="absolute top-12 right-3 font-mono text-xs uppercase bg-(--crit-bg-elevated) text-(--crit-fg-muted) px-2 py-0.5 rounded"
      >
        {@tag}
      </span>
    </div>
    """
  end

  attr :label, :string, required: true

  def browser_chrome_placeholder(assigns) do
    ~H"""
    <div
      class="flex items-center justify-center aspect-video"
      style="background: repeating-linear-gradient(-45deg, transparent, transparent 10px, rgba(128,128,128,0.07) 10px, rgba(128,128,128,0.07) 20px);"
    >
      <span class="font-mono text-sm text-(--crit-fg-muted)">{@label}</span>
    </div>
    """
  end

  @doc "Converts `backtick` spans in plain text to styled <code> elements."
  def inline_code(text) do
    Regex.split(~r/`([^`]+)`/, text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/^`([^`]+)`$/, part) do
        [_, code] ->
          Phoenix.HTML.raw(
            "<code class=\"font-mono text-sm text-(--crit-brand) bg-(--crit-bg-elevated) px-1 py-0.5 rounded\">#{Phoenix.HTML.html_escape(code) |> Phoenix.HTML.safe_to_string()}</code>"
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

  attr :id, :string, default: "install-section"

  def install_section(assigns) do
    ~H"""
    <section id="install" class="py-16 max-sm:py-10">
      <div class="max-w-[880px] mx-auto px-10 max-sm:px-4 w-full">
        <div class="text-center mb-10 max-sm:mb-8">
          <h2 class="text-5xl font-extrabold tracking-tight mb-4 max-sm:text-4xl">
            5-second install<span class="text-(--crit-brand)">.</span>
          </h2>
          <p class="text-lg text-(--crit-fg-secondary) max-sm:text-base">
            Single binary. No account, no config, no dependencies.
          </p>
        </div>

        <.install_widget id={@id} />
      </div>
    </section>
    """
  end

  attr :id, :string, default: "install"

  def install_widget(assigns) do
    ~H"""
    <div class="flex gap-0 border-b border-(--crit-border)">
      <button
        class="install-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 border-(--crit-brand) text-(--crit-brand) transition-colors cursor-pointer bg-transparent"
        data-target={"#{@id}-brew"}
      >
        Homebrew
      </button>
      <button
        class="install-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 border-transparent text-(--crit-fg-muted) hover:text-(--crit-fg-secondary) transition-colors cursor-pointer bg-transparent"
        data-target={"#{@id}-go"}
      >
        Go
      </button>
      <button
        class="install-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 border-transparent text-(--crit-fg-muted) hover:text-(--crit-fg-secondary) transition-colors cursor-pointer bg-transparent"
        data-target={"#{@id}-nix"}
      >
        Nix
      </button>
      <button
        class="install-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 border-transparent text-(--crit-fg-muted) hover:text-(--crit-fg-secondary) transition-colors cursor-pointer bg-transparent"
        data-target={"#{@id}-windows"}
      >
        Windows
      </button>
    </div>

    <div
      id={"#{@id}-brew"}
      class="install-panel border border-t-0 border-(--crit-border) rounded-b-md overflow-hidden"
    >
      <div
        class="copy-btn flex items-center bg-(--crit-code-bg) cursor-pointer text-(--crit-fg-muted)"
        data-copy="brew install crit"
      >
        <pre class="flex-1 font-mono text-sm text-(--crit-fg-primary) m-0 px-5 py-3.5 overflow-x-auto"><span class="text-(--crit-fg-muted) select-none">$ </span>brew install crit</pre>
        <div class="shrink-0 p-3">
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </div>
      </div>
    </div>

    <div
      id={"#{@id}-go"}
      class="install-panel hidden border border-t-0 border-(--crit-border) rounded-b-md overflow-hidden"
    >
      <div
        class="copy-btn flex items-center bg-(--crit-code-bg) cursor-pointer text-(--crit-fg-muted)"
        data-copy="go install github.com/tomasz-tomczyk/crit@latest"
      >
        <pre class="flex-1 font-mono text-sm text-(--crit-fg-primary) m-0 px-5 py-3.5 overflow-x-auto"><span class="text-(--crit-fg-muted) select-none">$ </span>go install github.com/tomasz-tomczyk/crit@latest</pre>
        <div class="shrink-0 p-3">
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </div>
      </div>
    </div>

    <div
      id={"#{@id}-nix"}
      class="install-panel hidden border border-t-0 border-(--crit-border) rounded-b-md overflow-hidden"
    >
      <div
        class="copy-btn flex items-center bg-(--crit-code-bg) cursor-pointer text-(--crit-fg-muted)"
        data-copy="nix profile install github:tomasz-tomczyk/crit"
      >
        <pre class="flex-1 font-mono text-sm text-(--crit-fg-primary) m-0 px-5 py-3.5 overflow-x-auto"><span class="text-(--crit-fg-muted) select-none">$ </span>nix profile install github:tomasz-tomczyk/crit</pre>
        <div class="shrink-0 p-3">
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </div>
      </div>
    </div>

    <div
      id={"#{@id}-windows"}
      class="install-panel hidden border border-t-0 border-(--crit-border) rounded-b-md overflow-hidden"
    >
      <div
        class="copy-btn flex items-center bg-(--crit-code-bg) cursor-pointer text-(--crit-fg-muted)"
        data-copy="iwr https://github.com/tomasz-tomczyk/crit/releases/latest/download/crit-windows-amd64.exe -OutFile crit.exe"
      >
        <pre class="flex-1 font-mono text-sm text-(--crit-fg-primary) m-0 px-5 py-3.5 overflow-x-auto"><span class="text-(--crit-fg-muted) select-none">PS&gt; </span>iwr https://github.com/tomasz-tomczyk/crit/releases/latest/download/crit-windows-amd64.exe -OutFile crit.exe</pre>
        <div class="shrink-0 p-3">
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </div>
      </div>
      <p class="text-xs text-(--crit-fg-muted) px-5 py-2.5 border-t border-(--crit-border)">
        Then move <code class="font-mono">crit.exe</code>
        somewhere on your <code class="font-mono">PATH</code>. ARM64 users: swap
        <code class="font-mono">amd64</code>
        for <code class="font-mono">arm64</code>. WSL users: use the Linux binary instead.
      </p>
    </div>

    <p class="text-sm text-(--crit-fg-secondary) mt-3">
      Or download a pre-built binary from <a
        href="https://github.com/tomasz-tomczyk/crit/releases"
        class="crit-link"
      >GitHub Releases</a>.
    </p>
    """
  end

  @agent_installs [
    %{
      id: "claude-code",
      name: "Claude Code",
      copy: "claude plugin marketplace add tomasz-tomczyk/crit\nclaude plugin install crit@crit",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "claude plugin marketplace add tomasz-tomczyk/crit"},
        %{type: :cmd, prompt: "$ ", text: "claude plugin install crit@crit"},
        %{type: :output, text: "Installed crit (skills: crit, crit-cli)"}
      ]
    },
    %{
      id: "cursor",
      name: "Cursor",
      copy: "crit install cursor",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install cursor"},
        %{type: :output, text: "Installed: .cursor/skills/crit/SKILL.md"},
        %{type: :output, text: "Installed: .cursor/skills/crit-cli/SKILL.md"}
      ]
    },
    %{
      id: "copilot",
      name: "Copilot",
      copy: "crit install github-copilot",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install github-copilot"},
        %{type: :output, text: "Installed: .github/skills/crit/SKILL.md"},
        %{type: :output, text: "Installed: .github/skills/crit-cli/SKILL.md"}
      ]
    },
    %{
      id: "codex",
      name: "Codex",
      copy: "crit install codex",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install codex"},
        %{type: :output, text: "Installed: .agents/skills/crit/SKILL.md"},
        %{type: :output, text: "Installed: .agents/skills/crit-cli/SKILL.md"}
      ]
    },
    %{
      id: "opencode",
      name: "OpenCode",
      copy: "crit install opencode",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install opencode"},
        %{type: :output, text: "Installed: .opencode/commands/crit.md"},
        %{type: :output, text: "Installed: .opencode/skills/crit/SKILL.md"}
      ]
    },
    %{
      id: "gemini",
      name: "Gemini",
      copy: "crit install gemini",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install gemini"},
        %{type: :output, text: "Installed: .gemini/commands/crit.toml"},
        %{type: :output, text: "Installed: .gemini/skills/crit-cli/SKILL.md"},
        %{type: :output, text: "Updated:   .gemini/settings.json (exit_plan_mode hook)"}
      ]
    },
    %{
      id: "qwen",
      name: "Qwen",
      copy: "crit install qwen",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install qwen"},
        %{type: :output, text: "Installed: .qwen/skills/crit/SKILL.md"},
        %{type: :output, text: "Installed: .qwen/skills/crit-cli/SKILL.md"}
      ]
    },
    %{
      id: "hermes",
      name: "Hermes",
      copy: "crit install hermes",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "cd ~ && crit install hermes"},
        %{type: :output, text: "Installed: ~/.hermes/skills/crit/SKILL.md"},
        %{type: :output, text: "Installed: ~/.hermes/skills/crit-cli/SKILL.md"}
      ]
    },
    %{
      id: "pi",
      name: "Pi",
      copy: "crit install pi",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install pi"},
        %{type: :output, text: "Installed: .pi/skills/crit/SKILL.md"},
        %{type: :output, text: "Installed: .pi/skills/crit-cli/SKILL.md"}
      ]
    },
    %{
      id: "grok",
      name: "Grok",
      copy: "crit install grok",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install grok"},
        %{type: :output, text: "Installed: .grok/skills/crit/SKILL.md"},
        %{type: :output, text: "Installed: .grok/skills/crit-cli/SKILL.md"}
      ]
    },
    %{
      id: "windsurf",
      name: "Windsurf",
      copy: "crit install windsurf",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install windsurf"},
        %{type: :output, text: "Installed: .windsurf/rules/crit.md"}
      ]
    },
    %{
      id: "cline",
      name: "Cline",
      copy: "crit install cline",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install cline"},
        %{type: :output, text: "Installed: .clinerules/crit.md"}
      ]
    },
    %{
      id: "aider",
      name: "Aider",
      copy: "crit install aider",
      lines: [
        %{type: :cmd, prompt: "$ ", text: "crit install aider"},
        %{type: :output, text: "Installed: .crit/aider-conventions.md"},
        %{
          type: :output,
          text: "Updated:   .aider.conf.yml (added .crit/aider-conventions.md under read:)"
        }
      ]
    }
  ]

  def agent_setup_widget(assigns) do
    assigns = assign(assigns, :agents, @agent_installs)

    ~H"""
    <div class="flex gap-0 border-b border-(--crit-border) overflow-x-auto">
      <button
        :for={{agent, idx} <- Enum.with_index(@agents)}
        class={[
          "agent-tab font-mono text-sm px-4 py-2 -mb-px border-b-2 transition-colors cursor-pointer bg-transparent whitespace-nowrap",
          if(idx == 0,
            do: "border-(--crit-brand) text-(--crit-brand)",
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
        "agent-panel border border-t-0 border-(--crit-border) rounded-b-md overflow-hidden",
        idx != 0 && "hidden"
      ]}
    >
      <div class="flex items-start bg-(--crit-code-bg)">
        <div class="flex-1 px-5 py-3.5 font-mono text-sm min-w-0">
          <div :for={line <- agent.lines}>
            <%= if line.type == :cmd do %>
              <div>
                <span class="text-(--crit-fg-muted) select-none">{line.prompt}</span>
                <span class="text-(--crit-fg-primary)">{line.text}</span>
              </div>
            <% else %>
              <div class="select-none">
                <span class="text-(--crit-green)">&#10003;</span>
                <span class="text-(--crit-fg-muted)">{line.text}</span>
              </div>
            <% end %>
          </div>
        </div>
        <button
          class="copy-btn shrink-0 p-3 mt-0.5 cursor-pointer text-(--crit-fg-muted) hover:text-(--crit-fg-primary) transition-colors"
          aria-label="Copy to clipboard"
          data-copy={agent.copy}
        >
          <.icon name="hero-clipboard" class="size-4 icon-default" />
          <.icon name="hero-clipboard-document-check" class="size-4 icon-copied hidden" />
        </button>
      </div>
    </div>

    <div class="flex gap-6 text-sm text-(--crit-fg-muted) mt-3">
      <a href="/integrations" class="crit-link">
        Full setup docs &rarr;
      </a>
      <a href="/integrations/build-your-own" class="crit-link">
        Build your own &rarr;
      </a>
    </div>
    """
  end
end
