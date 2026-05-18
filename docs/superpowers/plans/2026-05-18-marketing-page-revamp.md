# Marketing Page Revamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Revamp the crit-web homepage to highlight the four review modes (Files, Diff, Live/Design, Preview) with a mockup-inspired design, new header navigation with Modes dropdown, and new sections (hero with browser chrome, alternating modes, integrations with real logos, testimonials, FAQ, install, footer).

**Architecture:** Replace the existing `home.html.heex` template with new sections. Modify the `site_header` in `layouts.ex` to add a Modes dropdown and reorder nav links. Add 4 new mode pages (`/modes/:mode`) as controller actions. All marketing pages use Tailwind utilities in templates — no custom CSS in `app.css`.

**Tech Stack:** Phoenix/HEEx templates, Tailwind CSS v4 utilities, existing `--crit-*` CSS variables.

**Worktree:** `~/Server/side/crit-mono/crit-web.marketing-revamp` (branch: `marketing-revamp`)

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `lib/crit_web/components/layouts.ex` | Update `site_header` — move marketing links left, add Modes dropdown; add `site_footer` component |
| Modify | `lib/crit_web/controllers/page_html/home.html.heex` | Full rewrite of homepage sections |
| Modify | `lib/crit_web/controllers/page_controller.ex` | Add `mode/2` action, add modes to `@sitemap_paths`, update `home/2` assigns |
| Modify | `lib/crit_web/controllers/page_html.ex` | Add shared components (browser chrome, snippet, mode data) |
| Create | `lib/crit_web/controllers/page_html/mode.html.heex` | Individual mode page template |
| Modify | `lib/crit_web/router.ex` | Add `get "/modes/:mode"` route |

---

### Task 1: Update Site Header — Modes Dropdown + Reordered Nav

**Files:**
- Modify: `lib/crit_web/components/layouts.ex` (the `site_header` function component, lines ~76-250)

The current header has: `[Logo] ... [Features | Get Started | Self-Hosting | Changelog | GitHub] [divider] [user menu]`

New layout: `[Logo] [Modes ▾ | Features | Changelog | GitHub] ... [existing user menu]`

Links move to the left (after logo). "Modes" gets a hover dropdown. Keep the existing right side (user menu, divider, etc.) as-is.

- [ ] **Step 1: Restructure the nav links in `site_header`**

In `layouts.ex`, find the `site_header` component. Replace the `<nav>` block. The new nav has:
1. A "Modes" dropdown (hover-reveal, like the mockup's `topnav-modes`)
2. Features link
3. Changelog link  
4. GitHub link

Keep the existing right side (divider, user menu / auth buttons) — don't replace it with new CTA buttons.

The Modes dropdown items are:
- Plans & docs → `/modes/plans-docs`
- Code → `/modes/code`
- Live → `/modes/live`
- Preview → `/modes/preview`

Each dropdown item shows the mode name on the left and a mono description on the right (like the mockup).

Use `JS.toggle_attribute` for mobile menu if needed. For desktop, use CSS hover (`:hover` + `:focus-within` on a wrapper div) to show the dropdown — no JS needed.

The dropdown styling: absolute positioned below the trigger, `bg-(--crit-bg-card)` with border, shadow, rounded corners. Items are flex rows with name and mono description.

- [ ] **Step 2: Test header renders correctly**

Run: `cd ~/Server/side/crit-mono/crit-web.marketing-revamp && DB_PORT=5433 mise exec -- mix test test/crit_web/controllers/page_controller_test.exs -v`

- [ ] **Step 3: Start dev server and visually verify**

Run: `cd ~/Server/side/crit-mono/crit-web.marketing-revamp && mise exec -- mix phx.server`

Open `http://localhost:4000` and verify:
- Logo on far left
- Nav links appear to the right of logo  
- Modes dropdown opens on hover, shows 4 items
- Right side has Star on GitHub + Get Started buttons
- Mobile: nav collapses appropriately

- [ ] **Step 4: Commit**

```bash
git add lib/crit_web/components/layouts.ex
git commit -m "feat: restructure site header with Modes dropdown and CTA buttons"
```

---

### Task 2: Add Shared Homepage Components to PageHTML

**Files:**
- Modify: `lib/crit_web/controllers/page_html.ex`

Add reusable function components that the homepage and mode pages will use:

1. `browser_chrome/1` — fake browser window wrapper (dots, URL bar, body slot). Takes `url`, `tag` (optional overlay label), and inner content as slot.
2. `snippet/1` — copy-to-clipboard command snippet (like `$ brew install crit`). Takes `cmd` and optional `prompt`.
3. Mode data constants (the 4 modes with their labels, descriptions, slugs, etc.)

- [ ] **Step 1: Add `browser_chrome` component**

This renders:
- A container with rounded corners, border, card bg, shadow
- A bar with 3 colored dots (red/yellow/green), a pill-shaped URL display, and placeholder right dots
- A body area that renders the slot content
- Optional tag overlay (absolute positioned top-right, mono uppercase)

All Tailwind utilities — no custom CSS.

- [ ] **Step 2: Add `@modes` module attribute**

```elixir
@modes [
  %{slug: "plans-docs", label: "Plans & docs", cmd: "files / markdown / source",
    blurb: "Markdown plans and source files render in the browser. Comment on lines, ranges, code blocks inside fences.",
    bullets: ["Markdown render", "Per-line comments", "Code-fence ranges", "Mermaid diagrams"]},
  %{slug: "code", label: "Code", cmd: "branch / pr changes",
    blurb: "Auto-detects changed files in your repo. Split or unified diff, file tree with status & comment counts.",
    bullets: ["Auto file detection", "Split / unified", "Round-to-round diff", "PR sync (push/pull)"]},
  %{slug: "live", label: "Live", cmd: "running app / dev server",
    blurb: "Reverse-proxies your dev server into an iframe. Click any DOM element to pin a comment to it. Selectors survive minor drift.",
    bullets: ["Click-to-pin DOM", "Drift detection", "Threading", "Round comparisons"]},
  %{slug: "preview", label: "Preview", cmd: "static html artifact",
    blurb: "For static HTML artifacts agents emit — landing pages, mockups, generated dashboards. Same pin commenting as live mode.",
    bullets: ["Static HTML iframe", "Asset siblings served", "Pin to elements", "No dev server needed"]},
]
```

- [ ] **Step 3: Commit**

```bash
git add lib/crit_web/controllers/page_html.ex
git commit -m "feat: add browser_chrome component and mode data to PageHTML"
```

---

### Task 3: Rewrite Homepage — Hero Section

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex`
- Modify: `lib/crit_web/controllers/page_controller.ex` (add assigns)

The hero keeps our existing copy and voice, but changes the visual layout:
1. Keep our existing tagline: "Local-first · No login · Works with any agent"
2. Keep our headline: "Your feedback loop with the agent."
3. Keep our subhead paragraph
4. CTAs: Keep existing "Get started" + "See demo" + "Star on GitHub" buttons, but add a "Watch 2-min demo" link that opens a YouTube modal
5. Below CTAs: big screenshot in a browser chrome frame (instead of the YouTube embed)

- [ ] **Step 1: Replace hero section in home.html.heex**

Remove everything from the opening `<section>` (the hero) through the YouTube facade. Replace with:

- Eyebrow: mono text, brand color
- H1: big, extrabold, tracking-tight  
- Paragraph: secondary color, max-width
- CTA row: snippet (reuse existing `install_widget` pattern but simplified inline), star button, demo link
- Browser chrome wrapping a screenshot image (use existing `/images/screenshots/...` or placeholder)

The "Watch 2-min demo" link opens a YouTube video modal (overlay with embedded iframe). Build the modal as part of this task — clicking the link shows a centered modal with backdrop, the YouTube embed, and a close button. Escape key and backdrop click close it. Use JS commands for show/hide.

- [ ] **Step 2: Update page_controller `home/2` assigns if needed**

The existing `home/2` passes `demo_token`, `testimonials`, `stats`. Keep all of these. Add `modes: @modes` if needed (modes data can also come from PageHTML directly).

- [ ] **Step 3: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex lib/crit_web/controllers/page_controller.ex
git commit -m "feat: new hero section with browser chrome screenshot and CTAs"
```

---

### Task 4: Homepage — Four Modes Section (Alternating Layout)

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex`

After the hero, add: "Whatever your agent produces, crit has a surface for it."

Then 4 mode blocks, alternating text-left/screenshot-right and text-right/screenshot-left. Each block has:
- Mono eyebrow (the `cmd` description)
- Mode name as heading
- Description paragraph
- Bullet chips
- "Learn more →" link to `/modes/:slug`
- Browser chrome with screenshot placeholder (leave blank for user to fill)

Use `Enum.with_index` and check even/odd for alternating layout. Grid with `grid-cols-2` on desktop, stacked on mobile. Alternate which column the text goes in via `order` classes.

- [ ] **Step 1: Add modes section to home.html.heex**

After the hero section, add the modes section. Use `@modes` from PageHTML or inline the data. Each mode gets:
- A two-column grid row
- Even indices: text left, browser right
- Odd indices: browser left, text right
- Responsive: single column on mobile, natural order

Bullets render as small chips/pills with brand-colored dot prefix.

- [ ] **Step 2: Visually verify alternating layout**

Check that modes alternate sides correctly. Screenshots show as placeholder (hatched pattern or gray box with label).

- [ ] **Step 3: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex
git commit -m "feat: add four modes section with alternating layout"
```

---

### Task 5: Homepage — Integrations Section with Real Logos

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex`

Adapt the mockup's integration block. Use actual SVG logos from `/images/integrations/`. Each integration tile shows:
- The real logo (dark/light variants via `logo-dark`/`logo-light` classes)
- Name
- Arrow/link indicator

Display as a grid of tiles. Existing integrations with logos: claude-code, cursor, github-copilot, opencode, codex, gemini, qwen, windsurf, cline, grok, pi. Link each to `/integrations/:tool`.

Header: eyebrow "Works with any agent", heading with `/crit` kbd styling, lead text.

- [ ] **Step 1: Add integrations section**

Grid of integration tiles, each with:
- `<a>` wrapping the tile, linking to `/integrations/:tool_id`
- 28x28 logo image (dark + light variants)
- Name text
- Arrow icon

Footer note: "Don't see your agent? Anything that can read a file and execute a shell command can drive crit."

- [ ] **Step 2: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex
git commit -m "feat: add integrations section with real agent logos"
```

---

### Task 6: Homepage — Testimonials Section

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex`

Adapt the mockup's testimonials but:
- Remove the big `"` quotation mark from top-left corner
- Show shorter highlight quotes prominently
- Full body text below, smaller
- Author info with avatar at bottom
- Grid layout: 2-3 columns on desktop, 1 on mobile

Use the existing `@testimonials` data from `page_controller.ex`. Each testimonial has: `highlight`, `body` (list of paragraphs), `author`, `role`, `link`, `avatar`.

Design the card to be cleaner than the mockup — no decorative quote mark, just clean typography with the highlight as the visual anchor.

- [ ] **Step 1: Add testimonials section**

Cards with:
- Highlight text (larger, semibold, primary color)
- Body paragraphs (smaller, secondary color) — truncated or shown in full
- Author row: avatar, name (linked), role

Section header: eyebrow + heading like "What engineers say" or similar.

- [ ] **Step 2: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex
git commit -m "feat: add testimonials section with clean card design"
```

---

### Task 7: Homepage — FAQ Section

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex`
- Modify: `lib/crit_web/controllers/page_controller.ex` (add FAQ data)

Port the mockup's FAQ section ("The honest version of why crit"). 6 Q&A items in a 2-column grid. Each is a card with the question as a bold heading and the answer as body text.

- [ ] **Step 1: Add FAQ data to page_controller.ex**

Add `@faq` module attribute with the 6 questions from the mockup (adapt as needed).

- [ ] **Step 2: Add FAQ section to home.html.heex**

Two-column grid of cards. Each card has bold question heading + answer paragraph. Eyebrow: "FAQ", heading: "The honest version of why crit."

- [ ] **Step 3: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex lib/crit_web/controllers/page_controller.ex
git commit -m "feat: add FAQ section to homepage"
```

---

### Task 8: Homepage — Install Section

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex`

Adapt the mockup's install widget. Center-aligned, with:
- Eyebrow "Install", heading "Get it."
- Lead text: "Single binary. Local by default. No login."
- The existing `install_widget` component (tabs for Homebrew/Go/Nix/Windows)
- "then run" line
- GitHub Releases link

The existing `install_widget` already handles the tabbed install commands. Wrap it in the new section styling (centered, max-width constrained).

- [ ] **Step 1: Add install section**

Reuse `<CritWeb.PageHTML.install_widget />` inside a centered section with the mockup's header treatment.

- [ ] **Step 2: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex
git commit -m "feat: add centered install section to homepage"
```

---

### Task 9: Global Site Footer Component

**Files:**
- Modify: `lib/crit_web/components/layouts.ex` — add a `site_footer` function component
- Modify: `lib/crit_web/controllers/page_html/home.html.heex` — use `<Layouts.site_footer />`
- Other marketing templates can adopt it too (features, getting-started, etc.)

New global footer with:
- 4-column grid: Brand + description | Modes links | Project links | Share links
- Colophon line at bottom: "© Tomasz Tomczyk · Built in the open." and "Made for engineers who'd rather review than retype."
- All Tailwind, matches the mockup's dark footer style

- [ ] **Step 1: Add footer section**

Add `site_footer` as a function component in `layouts.ex` (like `site_header`). Four columns:
1. Logo + description + "MIT-licensed · single binary · zero telemetry"
2. Modes: Plans & docs, Diff, Live, Preview (linked to `/modes/:slug`)
3. Project: GitHub, crit-web, Releases, Contributing
4. Share: crit.live (hosted), Self-host

Bottom bar with copyright and tagline.

- [ ] **Step 2: Commit**

```bash
git add lib/crit_web/components/layouts.ex lib/crit_web/controllers/page_html/home.html.heex
git commit -m "feat: add global site_footer component to layouts"
```

---

### Task 10: Remove Old Homepage Sections

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex`

The old homepage had sections we're replacing:
- Old hero (blinking cursor headline + YouTube embed) → replaced in Task 3
- Old install + agent setup side-by-side → replaced by new install section
- Old feature sections (AI loop, plans+code, share reviews) → replaced by modes
- Old secondary features 3-up grid → removed (content covered by modes)
- Old "Built by" founder section → removed (can be added back later)
- Old platform stats section → removed (can be added back later)
- Old "Plus the small stuff" pills → removed

If any old sections remain after Tasks 3-9, clean them up now.

- [ ] **Step 1: Audit and remove leftover old sections**

Ensure the homepage flows: Header → Hero → Modes → Integrations → Testimonials → FAQ → Install → Footer.

Remove any orphaned sections from the old layout.

- [ ] **Step 2: Run tests**

Run: `cd ~/Server/side/crit-mono/crit-web.marketing-revamp && DB_PORT=5433 mise exec -- mix test test/crit_web/controllers/page_controller_test.exs -v`

- [ ] **Step 3: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex
git commit -m "chore: remove old homepage sections replaced by revamp"
```

---

### Task 11: Add Mode Pages Route + Controller + Template

**Files:**
- Modify: `lib/crit_web/router.ex` — add `get "/modes/:mode", PageController, :mode`
- Modify: `lib/crit_web/controllers/page_controller.ex` — add `mode/2` action
- Create: `lib/crit_web/controllers/page_html/mode.html.heex` — mode page template
- Modify: `lib/crit_web/controllers/page_controller.ex` — add to `@sitemap_paths`

Each mode page (Files, Diff, Live, Preview) gets its own URL at `/modes/:mode`. The template follows the mockup's `mode-page.jsx` pattern:
- Hero with eyebrow, title, lead text, tags/chips, browser screenshot
- "The loop" steps section
- Feature grid
- CTA to install

- [ ] **Step 1: Add route**

In `router.ex`, inside the marketing `scope`, add:
```elixir
get "/modes/:mode", PageController, :mode
```

- [ ] **Step 2: Add `mode/2` action in page_controller.ex**

Look up the mode by slug from a `@modes_data` map. Return 404 if not found. Render with mode-specific title, description, and data.

```elixir
@modes_data %{
  "plans-docs" => %{label: "Plans & docs", ...},
  "code" => %{label: "Code", ...},
  "live" => %{label: "Live", ...},
  "preview" => %{label: "Preview", ...},
}

def mode(conn, %{"mode" => slug}) do
  case Map.fetch(@modes_data, slug) do
    {:ok, mode} -> render(conn, :mode, mode: mode, ...)
    :error -> conn |> put_status(:not_found) |> put_view(CritWeb.ErrorHTML) |> render(:"404")
  end
end
```

- [ ] **Step 3: Create mode.html.heex template**

Basic structure:
- Site header
- Hero section with mode eyebrow, title, lead, tag chips, browser chrome screenshot
- Steps section ("The loop, when you're reviewing a [mode]")
- Feature grid (2-col, cards with title + description)
- Install CTA at bottom

Use the mode data to populate all fields. Screenshots will be placeholders initially.

- [ ] **Step 4: Add to sitemap**

Add `/modes/plans-docs`, `/modes/code`, `/modes/live`, `/modes/preview` to `@sitemap_paths`.

- [ ] **Step 5: Test route works**

Run: `cd ~/Server/side/crit-mono/crit-web.marketing-revamp && DB_PORT=5433 mise exec -- mix test -v`
Verify: `curl -s http://localhost:4000/modes/files | head -5` returns HTML.

- [ ] **Step 6: Commit**

```bash
git add lib/crit_web/router.ex lib/crit_web/controllers/page_controller.ex lib/crit_web/controllers/page_html.ex lib/crit_web/controllers/page_html/mode.html.heex
git commit -m "feat: add /modes/:mode pages for Files, Diff, Live, Preview"
```

---

### Task 12: Final Visual Polish + Precommit

**Files:**
- Various (touch-ups across all modified files)

- [ ] **Step 1: Run full precommit check**

Run: `cd ~/Server/side/crit-mono/crit-web.marketing-revamp && DB_PORT=5433 mise exec -- mix precommit`

Fix any compilation warnings, formatting issues, or test failures.

- [ ] **Step 2: Visual review in browser**

Start server and check:
- Homepage flows naturally through all sections
- Dark mode looks correct
- Light mode looks correct (toggle via data-theme)
- Mobile responsive (narrow viewport)
- All links work (modes dropdown, mode pages, integrations, etc.)
- Browser chrome screenshots render correctly (or show clean placeholders)

- [ ] **Step 3: Fix any issues found**

- [ ] **Step 4: Final commit if needed**

```bash
git add -A
git commit -m "fix: visual polish and precommit fixes for marketing revamp"
```
