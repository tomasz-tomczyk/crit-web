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
        "On the hosted version (crit.md), multiple reviewers can comment on the same document. Each author's comments are color-coded by a unique hue so you can tell at a glance who said what."
      ],
      why_this_matters: [
        "AI coding agents are fast, but they're also opaque. When Claude Code or Cursor rewrites a function, you don't get a natural place to say \"this is wrong at line 12\" unless you're already in a PR workflow. Most people end up pasting chunks of code into the chat and hoping the agent understands which part they mean. That's slow and error-prone.",
        "Inline comments let you anchor feedback to the exact lines that need it. Instead of writing \"the error handling in the auth function looks wrong,\" you select lines 34-41 and leave a comment there. The agent reads `.crit.json` (the review state file) and knows precisely what you're reacting to. No ambiguity, no re-explaining context.",
        "This also matters when reviewing plans, not just code. If your agent writes a markdown spec or a step-by-step plan before executing, you can review that document the same way you'd review a PR. Comment on the parts that need changing, approve the parts that look right, and hand it back."
      ],
      how_crit_compares:
        "GitHub PR reviews have the same interaction model, but they require a repo, a branch, and a push — which doesn't fit a local planning loop where the document hasn't been committed yet. CodeRabbit and similar tools automate the review itself; Crit is for when you are the reviewer and you want structured control over what the agent does next."
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
      ],
      why_this_matters: [
        "When an AI agent makes changes across 8 files, the question isn't just \"what changed\" — it's \"did it change the right things and only the right things.\" A flat file view doesn't answer that. You need colored diffs, line by line, so you can scan for unintended deletions or additions that crept in alongside the real changes.",
        "Round diffs are the part that's harder to find elsewhere. After you leave comments and the agent makes a second pass, you need to know what it actually did in response. Did it address your comment? Did it introduce something new while fixing something else? The diff between review rounds surfaces this clearly, without you manually diffing files or reading through git history.",
        "Split and unified view toggling is a small thing, but it matters. Split works better for structural changes where you want to see old and new side by side. Unified is faster to scan for line-level edits. Having both means you're not adapting to the tool."
      ],
      how_crit_compares:
        "Standard `git diff` in the terminal gives you unified diffs but no persistence, no comments, and no round-to-round comparison. Tools like Kaleidoscope and the GitHub diff viewer handle git diffs well but don't connect to an AI review loop. Crit's round diffs are specifically designed for iterative agent sessions, not one-time code review."
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
      ],
      why_this_matters: [
        "The default interaction with AI coding agents is conversational: you type, it responds, you type again. That works for small tasks. For anything involving real code changes across multiple files, it breaks down because the conversation history gets long, context is lost, and you can't easily point back to \"that thing you changed in round 2.\"",
        "Crit replaces the conversation loop with a structured review loop. You review the output, leave comments on specific lines, submit Finish Review, and `crit listen` notifies the agent. The agent reads exactly what you wrote and where you wrote it, then runs `crit go` when it's done. You get a diff. You review again. The loop has a clear state at each step.",
        "This structure also makes it easier to stop and resume. The state lives in `.crit.json`, so if you close your terminal and come back the next day, the review is still there. You're not reconstructing context from a chat thread."
      ],
      how_crit_compares:
        "Most AI agent workflows treat human feedback as a free-text prompt injected into the conversation. That works, but it's informal — there's no enforced structure around what the human reviewed, what they approved, and what they asked to change. Crit externalizes that state into a file the agent reads directly, which is more reliable and easier to audit after the fact."
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
      ],
      why_this_matters: [
        "If you work in the terminal, switching to a mouse to click through a review breaks flow. You're already in a mental mode of reading and judging code; stopping to grab the mouse and drag through line numbers is friction that adds up across a long review session.",
        "Crit's keyboard navigation lets you move line by line with `j`/`k`, open a comment form with `c`, and submit — without touching the mouse at all. For developers who spend most of the day in Neovim or a terminal multiplexer, this makes Crit feel like it belongs in the same environment rather than being a browser tool you have to context-switch into.",
        "Finishing a review is also a keyboard action. When you're done, press `f` and the review closes. The whole loop, from opening Crit to handing off to the agent, can stay entirely keyboard-driven."
      ],
      how_crit_compares:
        "Web-based review tools like GitHub's PR interface and CodeRabbit's dashboard are mouse-first. There are browser extensions that add some keyboard navigation to GitHub reviews, but they're patchy and don't extend to tools outside of GitHub. Crit's keybindings are built in from the start, not bolted on."
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
      ],
      why_this_matters: [
        "Before your agent writes a single line of code, you want to make sure the plan is right. But plans are often reviewed solo — you read the markdown, leave comments, and iterate. At some point you want a teammate, a tech lead, or a stakeholder to weigh in on the approach before the agent starts building.",
        "A share link lets you send the plan with all your inline comments intact. The person you send it to sees the same document with the same annotations, and they can add their own. That's useful for getting sign-off on an architecture decision, collecting feedback from someone who isn't in your terminal, or asking a colleague \"does this plan look right to you\" before the agent executes.",
        "Unpublishing is straightforward — use the Unpublish button in the UI or run `crit unpublish` from the terminal. Shared reviews also auto-expire after 30 days of inactivity, so nothing lingers indefinitely."
      ],
      how_crit_compares:
        "Google Docs and Notion let you share documents with comments, but they're not designed for reviewing structured plans with line-level precision. GitHub PR reviews support inline comments but require a repo and a push — your plan hasn't been committed yet. Crit share links are open — anyone with the URL can view and comment, no account needed."
    },
    "syntax-highlighting" => %{
      title: "Syntax Highlighting",
      tagline: "190+ languages with per-line commenting",
      description:
        "Fenced code blocks are syntax-highlighted with highlight.js and split into individual lines so you can comment on specific lines inside code - not just the block as a whole.",
      details: [
        "Supports 190+ languages via highlight.js — Go, Python, JavaScript, TypeScript, Rust, Ruby, Java, C, C++, Shell, SQL, YAML, and many more.",
        "Each line inside a fenced code block is a separate commentable element. Select line 3 of a code block and leave a review note right there.",
        "Highlighting respects your current theme - dark and light palettes are both fully styled.",
        "Code blocks preserve whitespace and formatting exactly as written. Long lines wrap so nothing is hidden off-screen."
      ],
      why_this_matters: [
        "AI agents frequently produce output that mixes prose and code — a plan document that includes shell commands, a spec that has SQL examples, a markdown file with embedded TypeScript snippets. When you're reviewing that output, you need the code to actually render as code, not as a wall of monospace text.",
        "Syntax highlighting makes errors visible. A wrong variable name or a mismatched bracket is much easier to spot when tokens are colored by role. When you're reviewing agent output for correctness, not just structure, that visual parsing matters.",
        "Per-line commenting inside code blocks is the part that's easy to overlook. Most markdown renderers highlight the block as a whole. Crit splits fenced code blocks into individual lines so you can select lines 4-7 inside a code block and leave a comment there, the same way you would on any other part of the document."
      ],
      how_crit_compares:
        "Standard markdown previewers (VS Code preview, Marked, etc.) render syntax highlighting but don't support comments. GitHub renders fenced code blocks with highlighting and allows PR comments at the file level, but you can't comment on a specific line inside a code block in a plain markdown file. Crit treats code blocks as first-class reviewable content."
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
      ],
      why_this_matters: [
        "AI agents are capable of producing architecture diagrams, sequence flows, and state machines as Mermaid syntax if you ask them to. That's useful, but raw Mermaid text is hard to review. You can read it, but you can't quickly tell whether the flow makes sense until you see the rendered diagram.",
        "When Crit renders the diagram inline, you can review the visual output and the source simultaneously. If the sequence diagram shows the wrong order of events, you select the relevant lines in the source and leave a comment. The agent gets the comment with line numbers pointing to the exact Mermaid code that needs changing.",
        "This is particularly useful for architecture review at the planning stage. Before an agent writes any code, you can ask it to produce a diagram of the proposed approach, review it in Crit, leave comments, and let it revise before implementation starts. Catching structural issues in a diagram is faster than catching them in code."
      ],
      how_crit_compares:
        "Most markdown editors that support Mermaid (GitHub markdown preview, Notion, HackMD) render diagrams in preview mode, but they don't support inline comments on the source. Dedicated diagramming tools like Miro and draw.io don't accept Mermaid input and aren't designed for the write-review-revise loop with an AI agent."
    }
  }

  @feature_order ~w(inline-comments split-unified-diff ai-review-loop vim-keybindings share-reviews syntax-highlighting mermaid-diagrams)

  @testimonials [
    %{
      highlight: "A clean local UI to batch my feedback and iterate.",
      body: [
        "Crit saves me so much time reviewing Claude Code plans - instead of fumbling with line numbers or accidental sends, I get a clean local UI to batch my feedback and iterate, all without leaving my workflow."
      ],
      author: "Omer",
      role: "Principal Engineer",
      handle: "omervk"
    },
    %{
      highlight: "It's like a pull request review but for your plan.",
      body: [
        "I've been using crit to review plans for some times. I use claude code in the command line without an IDE, so being to quickly check the plan with rendering is super nice.",
        "The system allowing you to add comments is the killer feature: it's like a pull request review but for your plan.",
        "On long, complex plans I used to ask claude things like \"on point 3., we should do X, drop point 7., ...\". Using comments makes it more straightforward and easy to review later."
      ],
      author: "Vincent",
      role: "Senior Software Engineer",
      handle: "vineus"
    }
  ]

  def home(conn, _params) do
    if Application.get_env(:crit, :selfhosted) do
      redirect(conn, to: "/dashboard")
    else
      render(conn, :home,
        demo_token: Application.get_env(:crit, :demo_review_token),
        testimonials: @testimonials,
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
          "url" => "https://crit.md",
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
                "item" => "https://crit.md/"
              },
              %{
                "@type" => "ListItem",
                "position" => 2,
                "name" => "Features",
                "item" => "https://crit.md/features"
              },
              %{
                "@type" => "ListItem",
                "position" => 3,
                "name" => feature.title,
                "item" => "https://crit.md/features/#{slug}"
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
      integrations: Crit.Integrations.list(),
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

  def getting_started(conn, _params) do
    render(conn, :getting_started,
      canonical_url: canonical_url(conn),
      page_title: "Getting Started - Crit",
      meta_description:
        "Install Crit and run your first review in under a minute. Single binary, zero dependencies. Works with Claude Code, Cursor, GitHub Copilot, and any AI coding agent."
    )
  end

  def changelog(conn, _params) do
    releases = Crit.Changelog.list_releases()
    cli_releases = Enum.filter(releases, &(&1.source == :cli))
    web_releases = Enum.filter(releases, &(&1.source == :web))

    render(conn, :changelog,
      cli_releases: cli_releases,
      web_releases: web_releases,
      canonical_url: canonical_url(conn),
      page_title: "Changelog - Crit",
      meta_description: "What's new in Crit. Release notes for the Crit CLI and crit.md."
    )
  end

  defp canonical_url(conn) do
    "#{CritWeb.Endpoint.url()}#{conn.request_path}"
  end
end
