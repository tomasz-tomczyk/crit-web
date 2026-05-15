---
description: Triggered when querying, listing, or displaying reviews — especially in new endpoints, LiveViews, or admin/overview pages
globs:
  - lib/crit/reviews.ex
  - lib/crit/organizations.ex
  - lib/crit_web/live/**
  - lib/crit_web/controllers/**
---

# Review queries must respect org membership boundaries

Reviews can belong to an organization (`organization_id`). Users must never see reviews from orgs they are not a member of — not in listings, not in API responses, not in admin/overview pages. This includes reviews the user *created* if they have since left the org.

## Rules

1. **Never use unfiltered `:all` queries in user-facing code.** `list_reviews_with_counts/0` returns every review in the system. It exists only for true system-admin contexts (if any). For any page where a user is viewing reviews, use a scoped variant.

2. **Every review filter must exclude inaccessible org reviews.** Even "my reviews" queries must filter out org-scoped reviews where the user is no longer a member. The `{:user, user_id}` filter does this via an org membership subquery. Never filter by just `r.user_id == ^user_id` without also checking org membership for org-scoped reviews.

3. **For "all reviews visible to me" listings**, use `Reviews.list_visible_reviews_with_counts(scope)` which filters to: user's own non-org reviews + reviews from orgs the user belongs to.

4. **For single-review access by token**, always call `Reviews.check_org_access(review, scope)` before returning data. This applies to LiveView mounts, API controllers, raw file endpoints, and any new endpoint.

5. **For org-scoped review listings**, always go through `Organizations.list_org_reviews_paginated(scope, org, opts)` (or equivalent wrapper) which validates `Scope.org_id(scope) == org.id`.

6. **When adding a new endpoint or page that shows reviews**, ask two questions: "Could this show a review from an org the user isn't in?" AND "Could this show a review the user created but can no longer access (e.g., they left the org)?" If yes to either, add the appropriate filter.

## Why

Two real bugs informed these rules:
- The selfhosted `/overview` page used `list_reviews_with_counts/0` and showed org-scoped reviews to non-members.
- The personal `/reviews` page showed org-scoped reviews the user created but could no longer access after leaving the org — dead links that leaked metadata.

Both were caught before shipping but demonstrate that org membership must be checked on every query path, not just the access gate.
