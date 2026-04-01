# Testimonials Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "What engineers are saying" testimonials section to the homepage between the Features section and the Self-Hosting card.

**Architecture:** Testimonials are defined as a module attribute list in `page_controller.ex` (same pattern as `@features`), passed as an assign, and rendered via a `:for` comprehension in the template. Pure Tailwind styling, no custom CSS.

**Tech Stack:** Phoenix, HEEx templates, Tailwind CSS with `--crit-*` CSS variables

---

### Task 1: Add testimonials data to PageController

**Files:**
- Modify: `lib/crit_web/controllers/page_controller.ex:140-168`

- [ ] **Step 1: Add `@testimonials` module attribute after `@feature_order` (line 140)**

Add the following after line 140 (`@feature_order ~w(...)`):

```elixir
@testimonials [
  %{
    body:
      "Crit saves me so much time reviewing Claude Code plans - instead of fumbling with line numbers or accidental sends, I get a clean local UI to batch my feedback and iterate, all without leaving my workflow.",
    author: "Omer",
    handle: "omervk"
  },
  %{
    body:
      "I've been using crit to review plans for some times. I use claude code in the command line without an IDE, so being to quickly check the plan with rendering is super nice. The system allowing you to add comments is the killer feature: it's like a pull request review but for your plan. On long, complex plans I used to ask claude things like \"on point 3., we should do X, drop point 7., ...\". Using comments makes it more straightforward and easy to review later.",
    author: "Vincent",
    handle: "vineus"
  }
]
```

- [ ] **Step 2: Pass `@testimonials` to the template in the `home/2` function**

In the `home/2` function's `render` call (line 146), add `testimonials: @testimonials` to the assigns:

```elixir
render(conn, :home,
  demo_token: Application.get_env(:crit, :demo_review_token),
  testimonials: @testimonials,
  canonical_url: canonical_url(conn),
  ...
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly with no warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/crit_web/controllers/page_controller.ex
git commit -m "feat: add testimonials data to page controller"
```

---

### Task 2: Add testimonials section to homepage template

**Files:**
- Modify: `lib/crit_web/controllers/page_html/home.html.heex:597` (insert before `<!-- ===== Self-Hosting ===== -->`)

- [ ] **Step 1: Insert testimonials section before the Self-Hosting section**

Insert the following block between line 596 (`</section>` closing the Features section) and line 598 (`<!-- ===== Self-Hosting ===== -->`):

```heex
<%!-- ===== Testimonials ===== --%>
  <section class="max-w-[1100px] mx-auto mt-14 mb-8 px-10 max-sm:px-5 w-full">
    <p class="font-mono text-xs tracking-widest uppercase text-(--crit-accent) mb-6">
      What engineers are saying
    </p>
    <div class="grid grid-cols-2 gap-4 max-sm:grid-cols-1">
      <div
        :for={testimonial <- @testimonials}
        class="rounded-lg border border-(--crit-border) bg-(--crit-bg-secondary) p-6"
      >
        <p class="text-sm leading-relaxed text-(--crit-fg-primary) mb-4">
          "<%= testimonial.body %>"
        </p>
        <p class="font-mono text-xs text-(--crit-fg-muted)">
          <%= testimonial.author %>
          <a
            href={"https://x.com/#{testimonial.handle}"}
            class="text-(--crit-fg-dimmed) hover:text-(--crit-accent) transition-colors ml-1"
            target="_blank"
            rel="noopener noreferrer"
          >
            @<%= testimonial.handle %>
          </a>
        </p>
      </div>
    </div>
  </section>
```

- [ ] **Step 2: Start the dev server and verify visually**

Run: `dev up` (or `mix phx.server` if already set up)
Open: `http://localhost:4000`
Expected: Scrolling down past the features grid and compact feature strip, there's a "What engineers are saying" section with two cards side-by-side. Omer's quote appears first (left), Vincent's second (right). On mobile viewport, they stack vertically.

- [ ] **Step 3: Verify formatting checks pass**

Run: `mix format --check-formatted`
Expected: No formatting issues.

- [ ] **Step 4: Commit**

```bash
git add lib/crit_web/controllers/page_html/home.html.heex
git commit -m "feat: add testimonials section to homepage"
```

---

### Task 3: Run full precommit checks

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass (compile, format, sobelow, audit, test).

- [ ] **Step 2: Fix any issues**

If any check fails, fix and re-run until clean.

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address precommit issues"
```
