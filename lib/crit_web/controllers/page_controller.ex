defmodule CritWeb.PageController do
  use CritWeb, :controller

  @features %{
    "inline-comments" => %{
      title: "Inline Comments",
      tagline: "PR-style comments on plans and code diffs",
      description:
        "Click and drag line numbers to select a range, then leave a comment - just like a pull request review, but on any file your agent touched.",
      details: [
        "Select a single line or drag across multiple lines to highlight a range. A comment form appears immediately so you can start typing.",
        "Comments support markdown - use **bold**, *italic*, `inline code`, code blocks, links, and lists to format your feedback.",
        "Edit or delete any comment you've made. Each comment is anchored to the exact lines it references.",
        "On the hosted version (crit.live), multiple reviewers can comment on the same document. Each author's comments are color-coded by a unique hue so you can tell at a glance who said what."
      ]
    },
    "split-unified-diff" => %{
      title: "Git Diffs & Round Diffs",
      tagline: "See exactly what your agent changed",
      description:
        "Branch review shows git diffs with colored additions and deletions. Between review rounds, Crit shows what your agent changed in response to your comments. Toggle between split and unified views.",
      details: [
        "Toggle between split (side-by-side) and unified (inline) diff views with a single click. Your preference is remembered across rounds.",
        "Code files display git diff hunks with dual line numbers, expandable context, and colored backgrounds for additions and deletions.",
        "Between review rounds, changed sections are visually marked so you can quickly spot what your agent edited — in both markdown and code files. Navigate between changes with `n`/`N`.",
        "Comments from the previous round are carried forward. Resolved comments are marked, and open ones remain visible on the updated lines."
      ]
    },
    "ai-review-loop" => %{
      title: "AI Review Loop",
      tagline: "Review, hand off to your agent, iterate",
      description:
        "Leave comments, click Finish Review, and your agent is notified automatically via `crit listen`. The agent reads `.crit.json`, makes edits, and runs `crit go <port>` when done. Crit reloads with a diff, and you review again.",
      details: [
        "When you click \"Finish Review\", Crit writes `.crit.json` - structured comment data with per-file sections. Your agent is notified automatically if it was listening via `crit listen`.",
        "The prompt tells the agent to read `.crit.json`, address unresolved comments, and run `crit go <port>` when done. No copy-paste needed — `crit listen` delivers it directly.",
        "When the agent runs `crit go`, the browser starts a new round with a diff of what changed. Previous comments show as resolved or still open.",
        "Add new comments on the updated version and repeat. When all comments are resolved, Crit detects it and generates a clean confirmation prompt — the loop ends when you're satisfied."
      ]
    },
    "vim-keybindings" => %{
      title: "Vim Keybindings",
      tagline: "Full keyboard-driven review workflow",
      description:
        "Navigate lines, leave comments, and finish reviews without ever touching the mouse. Crit's keybindings are designed for developers who live in the terminal.",
      details: [
        "Use j/k to move between lines and blocks, n/N to jump between changes. The same motions you already know from vim.",
        "Press c to open the comment form on the current line. Type your feedback, then Ctrl+Enter to submit. Press Escape to cancel.",
        "Use e to edit an existing comment, d to delete it. Press f to finish the review and copy the prompt. Press t to toggle the table of contents.",
        "Press ? at any time to see the full shortcut reference."
      ]
    },
    "share-reviews" => %{
      title: "Share Reviews",
      tagline: "One-click public links for async collaboration",
      description:
        "Generate a public link with one click. Anyone with the link can view the document and add their own comments. Unpublish anytime to revoke access.",
      details: [
        "Click the Share button in Crit and a unique URL is generated instantly. Or share directly from the CLI with `crit share plan.md` — no browser needed.",
        "Anyone who opens the link sees the full document with all comments. They can add their own feedback without installing anything - it works in any browser.",
        "Each reviewer's comments are color-coded by a unique hue, making it easy to track who said what in a multi-person review.",
        "Use `crit share --qr` to print a QR code in the terminal for quick mobile access. Unpublish anytime with `crit unpublish`. Shared reviews auto-expire after 30 days of inactivity."
      ]
    },
    "syntax-highlighting" => %{
      title: "Syntax Highlighting",
      tagline: "13+ languages with per-line commenting",
      description:
        "Fenced code blocks are syntax-highlighted with highlight.js and split into individual lines so you can comment on specific lines inside code - not just the block as a whole.",
      details: [
        "Supports Go, Python, JavaScript, TypeScript, Rust, Ruby, Java, C, C++, Shell, SQL, YAML, JSON, and more via highlight.js.",
        "Each line inside a fenced code block is a separate commentable element. Select line 3 of a code block and leave a review note right there.",
        "Highlighting respects your current theme - dark and light palettes are both fully styled.",
        "Code blocks preserve whitespace and formatting exactly as written. Long lines wrap so nothing is hidden off-screen."
      ]
    },
    "mermaid-diagrams" => %{
      title: "Mermaid Diagrams",
      tagline: "Rendered diagrams from fenced mermaid blocks",
      description:
        "Write mermaid syntax in a fenced code block and Crit renders it as an SVG diagram - flowcharts, sequence diagrams, state machines, and more.",
      details: [
        "Fenced blocks tagged with ```mermaid are automatically rendered as SVG diagrams in the browser. No extra tooling or plugins required.",
        "Supports flowcharts, sequence diagrams, class diagrams, state diagrams, Gantt charts, ER diagrams, and other mermaid diagram types.",
        "Diagrams scale to fit the available width without overflowing the layout.",
        "You can still comment on mermaid blocks. Select the block's line range and leave feedback about the diagram's structure or content."
      ]
    }
  }

  @feature_order ~w(inline-comments split-unified-diff ai-review-loop vim-keybindings share-reviews syntax-highlighting mermaid-diagrams)

  @integration_meta [
    %{
      id: "claude-code",
      name: "Claude Code",
      file_path: ".claude/commands/crit.md",
      source: "claude-code/crit.md",
      description:
        "Add the /crit slash command. It launches Crit, reads your comments, and revises the output automatically.",
      secondary_label: "CLAUDE.md snippet (optional)",
      secondary_file_path: "Append to your CLAUDE.md",
      secondary_source: "claude-code/CLAUDE.md"
    },
    %{
      id: "cursor",
      name: "Cursor",
      file_path: ".cursor/commands/crit.md",
      source: "cursor/crit-command.md",
      description:
        "Add the /crit slash command. It launches Crit, reads your comments, and revises the output automatically.",
      secondary_label: "Cursor rule (optional)",
      secondary_file_path: "Copy to .cursor/rules/crit.mdc",
      secondary_source: "cursor/crit.mdc"
    },
    %{
      id: "windsurf",
      name: "Windsurf",
      file_path: ".windsurf/rules/crit.md",
      source: "windsurf/crit.md",
      description:
        "Add a Windsurf rule that teaches the agent to use Crit for reviewing plans and code changes."
    },
    %{
      id: "github-copilot",
      name: "GitHub Copilot",
      file_path: ".github/prompts/crit.prompt.md",
      source: "github-copilot/crit.prompt.md",
      description:
        "Add the /crit slash command. It launches Crit, reads your comments, and revises the output automatically.",
      secondary_label: "Copilot instructions (optional)",
      secondary_file_path: "Append to .github/copilot-instructions.md",
      secondary_source: "github-copilot/copilot-instructions.md"
    },
    %{
      id: "aider",
      name: "Aider",
      file_path: "CONVENTIONS.md",
      source: "aider/CONVENTIONS.md",
      description:
        "Append to your Aider conventions file to teach the agent to use Crit for reviewing plans and code changes."
    },
    %{
      id: "cline",
      name: "Cline",
      file_path: ".clinerules/crit.md",
      source: "cline/crit.md",
      description:
        "Add a Cline rule that teaches the agent to use Crit for reviewing plans and code changes."
    }
  ]

  @integrations Crit.Integrations.load(@integration_meta)

  def home(conn, _params) do
    if Application.get_env(:crit, :selfhosted) do
      redirect(conn, to: "/dashboard")
    else
      render(conn, :home,
        demo_token: Application.get_env(:crit, :demo_review_token),
        canonical_url: canonical_url(conn),
        page_title: "Crit - Inline code review for AI coding agents",
        meta_description:
          "Review AI-generated plans before coding. Review code changes before merging. Inline comments, multi-round diffs, and a structured feedback loop for any AI coding agent. Single binary, works locally.",
        json_ld: %{
          "@context" => "https://schema.org",
          "@type" => "SoftwareApplication",
          "name" => "Crit",
          "applicationCategory" => "DeveloperApplication",
          "operatingSystem" => "macOS, Linux, Windows",
          "description" =>
            "Review AI-generated plans before coding. Inline comments, multi-round diffs, and a structured feedback loop for any AI coding agent.",
          "url" => "https://crit.live",
          "offers" => %{
            "@type" => "Offer",
            "price" => "0",
            "priceCurrency" => "USD"
          }
        }
      )
    end
  end

  def features(conn, _params) do
    render(conn, :features,
      feature_order: @feature_order,
      features: @features,
      canonical_url: canonical_url(conn),
      page_title: "Features - Crit",
      meta_description:
        "Inline comments, multi-round diffs, git diff viewer, vim keybindings, shared reviews, syntax highlighting, and more. Built for reviewing AI agent output at every stage."
    )
  end

  def feature(conn, %{"slug" => slug}) do
    case Map.fetch(@features, slug) do
      {:ok, feature} ->
        render(conn, :feature,
          feature: feature,
          slug: slug,
          demo_token: Application.get_env(:crit, :demo_review_token),
          feature_order: @feature_order,
          features: @features,
          canonical_url: canonical_url(conn),
          page_title: "#{feature.title} - Crit",
          meta_description: "#{feature.tagline}. #{feature.description}",
          json_ld: %{
            "@context" => "https://schema.org",
            "@type" => "BreadcrumbList",
            "itemListElement" => [
              %{
                "@type" => "ListItem",
                "position" => 1,
                "name" => "Home",
                "item" => "https://crit.live/"
              },
              %{
                "@type" => "ListItem",
                "position" => 2,
                "name" => "Features",
                "item" => "https://crit.live/features"
              },
              %{
                "@type" => "ListItem",
                "position" => 3,
                "name" => feature.title,
                "item" => "https://crit.live/features/#{slug}"
              }
            ]
          }
        )

      :error ->
        conn
        |> put_status(:not_found)
        |> put_view(CritWeb.ErrorHTML)
        |> render(:"404")
    end
  end

  def integrations(conn, _params) do
    render(conn, :integrations,
      integrations: @integrations,
      canonical_url: canonical_url(conn),
      page_title: "Integrations - Crit",
      meta_description:
        "Set up Crit with Claude Code, Cursor, GitHub Copilot, Windsurf, Aider, or Cline. Drop-in config files for each agent."
    )
  end

  def terms(conn, _params) do
    render(conn, :terms,
      canonical_url: canonical_url(conn),
      page_title: "Terms of Service - Crit",
      meta_description:
        "Terms of service for Crit, the markdown review tool for AI coding agents."
    )
  end

  def privacy(conn, _params) do
    render(conn, :privacy,
      canonical_url: canonical_url(conn),
      page_title: "Privacy Policy - Crit",
      meta_description:
        "Privacy policy for Crit. Local-first by default - your files never leave your machine unless you explicitly share."
    )
  end

  def self_hosting(conn, _params) do
    render(conn, :self_hosting,
      canonical_url: canonical_url(conn),
      page_title: "Self-Hosting - Crit",
      meta_description:
        "Run your own instance of Crit Web with Docker. Full guide with docker-compose, environment variables, and setup instructions."
    )
  end

  defp canonical_url(conn) do
    "#{CritWeb.Endpoint.url()}#{conn.request_path}"
  end
end
