# Testimonials Section Design

## Overview

Add a "What engineers are saying" testimonials section to the homepage, positioned between the demo video and the install widget. Minimal quote cards styled with Tailwind and `--crit-*` CSS variables.

## Placement

Homepage (`home.html.heex`), between the demo video section and the install widget section.

## Data

Testimonials defined as a list of maps in `page_controller.ex`, passed to the template as an assign. Each map contains:

- `body` — the quote text
- `author` — display name
- `handle` — X/Twitter handle (without @)
- `url` — link to the person's X profile

Initial testimonials (in this order):

1. **Omer (@omervk)**: "Crit saves me so much time reviewing Claude Code plans - instead of fumbling with line numbers or accidental sends, I get a clean local UI to batch my feedback and iterate, all without leaving my workflow."
2. **Vincent (@vineus)**: "I've been using crit to review plans for some times. I use claude code in the command line without an IDE, so being to quickly check the plan with rendering is super nice. The system allowing you to add comments is the killer feature: it's like a pull request review but for your plan. On long, complex plans I used to ask claude things like \"on point 3., we should do X, drop point 7., ...\". Using comments makes it more straightforward and easy to review later."

## Visual Design

### Section heading

- Monospace, uppercase, tracked-wide, accent-colored eyebrow: "What engineers are saying"
- Matches the hero eyebrow style ("Local-first . No login . Works with any agent")

### Quote cards

- Grid: `grid grid-cols-2` on desktop, single column on mobile
- Card: `--crit-bg-secondary` background, `--crit-border` border, rounded corners
- Quote text: regular body font, `--crit-fg-primary`, natural reading size
- Author line: name + linked X handle in `--crit-fg-muted`, monospace
- No photos, no star ratings, no logos
- Consistent padding matching surrounding sections

### Responsive

Follows the existing homepage pattern: 2 columns on desktop, 1 column on mobile using `max-sm:grid-cols-1`.

## Growth

Adding a testimonial = adding a map to the list in `page_controller.ex`. No template changes needed. The `:for` comprehension renders whatever is in the list.

## What This Does NOT Include

- No dedicated `/testimonials` or `/wall-of-love` route
- No database table
- No new CSS classes in `app.css` (Tailwind only)
- No carousel, rotation, or animation
- No photos or avatars
