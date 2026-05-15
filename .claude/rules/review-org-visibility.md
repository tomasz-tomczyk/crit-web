---
description: Triggered when querying, listing, or displaying reviews — especially in new endpoints, LiveViews, or admin/overview pages
globs:
  - lib/crit/reviews.ex
  - lib/crit/organizations.ex
  - lib/crit_web/live/**
  - lib/crit_web/controllers/**
---

# Review queries must respect org membership boundaries

Reviews can belong to an organization (`organization_id`). Users must never see reviews from orgs they are not a member of — not in listings, not in API responses, not in admin/overview pages.

## Rules

1. **Never use unfiltered `:all` queries in user-facing code.** `list_reviews_with_counts/0` returns every review in the system. It exists only for true system-admin contexts (if any). For any page where a user is viewing reviews, use a scoped variant.

2. **For "all reviews visible to me" listings**, use `Reviews.list_visible_reviews_with_counts(scope)` which filters to: reviews with no org + reviews from orgs the user belongs to.

3. **For single-review access by token**, always call `Reviews.check_org_access(review, scope)` before returning data. This applies to LiveView mounts, API controllers, raw file endpoints, and any new endpoint.

4. **For org-scoped review listings**, always go through `Organizations.list_org_reviews_paginated(scope, org, opts)` (or equivalent wrapper) which validates `Scope.org_id(scope) == org.id`.

5. **When adding a new endpoint or page that shows reviews**, ask: "Could this show a review from an org the user isn't in?" If yes, add the appropriate filter.

## Why

This was a real bug: the selfhosted `/overview` page used `list_reviews_with_counts/0` and showed org-scoped reviews to users who weren't members of those orgs. Clicking through was correctly gated, but the listing itself leaked titles, file paths, comment counts, and author info.
