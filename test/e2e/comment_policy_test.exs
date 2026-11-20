defmodule CritWeb.E2E.CommentPolicyTest do
  use CritWeb.E2ECase, async: true

  defp api_base_url, do: base_url()

  # Set comment_policy via the API. We can't fully simulate owner-driven UI
  # toggling without a logged-in browser session (no E2E auth helper exists),
  # so we drive the policy change through the seeded admin path instead and
  # verify the viewer-side effects in the browser.
  #
  # Anonymous PUT silently ignores comment_policy, so we use the dev-only
  # seed pattern: create the review with an authenticated bearer token, then
  # PUT with that bearer to set the policy.
  defp seed_user_and_token(request) do
    res =
      APIRequestContext.post!(request, "#{api_base_url()}/api/test/seed-user",
        data: %{name: "CP Owner"}
      )

    assert APIResponse.status(res) == 200
    APIResponse.json!(res)
  end

  defp set_comment_policy_as_owner(request, token, delete_token, bearer, policy) do
    res =
      APIRequestContext.put!(request, "#{api_base_url()}/api/reviews/#{token}",
        headers: %{"Authorization" => "Bearer #{bearer}"},
        data: %{
          delete_token: delete_token,
          files: [%{path: "a.md", content: "# hi\n"}],
          comments: [],
          review_round: 1,
          comment_policy: policy
        }
      )

    assert APIResponse.status(res) == 200
    body = APIResponse.json!(res)
    assert body["comment_policy"] == policy
  end

  describe "comment policy" do
    test "logged_in_only — anon viewer sees the sign-in banner and no add-comment button",
         %{browser: browser, request: request} do
      %{"token" => bearer} = seed_user_and_token(request)

      # Create review as the authenticated owner so the bearer scope owns it.
      create_res =
        APIRequestContext.post!(request, "#{api_base_url()}/api/reviews",
          headers: %{"Authorization" => "Bearer #{bearer}"},
          data: %{files: [%{path: "a.md", content: "# hi\n"}], comments: []}
        )

      assert APIResponse.status(create_res) == 201
      %{"url" => url, "delete_token" => delete_token} = APIResponse.json!(create_res)
      [_, token] = String.split(url, "/r/")

      set_comment_policy_as_owner(request, token, delete_token, bearer, "logged_in_only")

      # Anonymous browser viewer.
      ctx = Browser.new_context!(browser)
      page = BrowserContext.new_page!(ctx)
      load_review(page, token)

      Expect.to_be_visible!(Page.locator(page, ~s([data-test="signin-banner"])))

      Expect.to_contain_text!(
        Page.locator(page, ~s([data-test="signin-banner"])),
        "Sign-in required"
      )

      # Hidden via server-rendered .crit-page.crit-no-comments class.
      Expect.to_have_count!(Page.locator(page, ".crit-page.crit-no-comments"), 1)

      delete_review(request, delete_token)
    end

    test "disallowed — header carries the signal, no body banner, comment affordances hidden",
         %{browser: browser, request: request} do
      %{"token" => bearer} = seed_user_and_token(request)

      create_res =
        APIRequestContext.post!(request, "#{api_base_url()}/api/reviews",
          headers: %{"Authorization" => "Bearer #{bearer}"},
          data: %{files: [%{path: "a.md", content: "# hi\n"}], comments: []}
        )

      %{"url" => url, "delete_token" => delete_token} = APIResponse.json!(create_res)
      [_, token] = String.split(url, "/r/")

      set_comment_policy_as_owner(request, token, delete_token, bearer, "disallowed")

      ctx = Browser.new_context!(browser)
      page = BrowserContext.new_page!(ctx)
      load_review(page, token)

      Expect.to_be_hidden!(Page.locator(page, ~s([data-test="signin-banner"])))

      Expect.to_contain_text!(
        Page.locator(page, ~s([data-test="comment-policy-badge"])),
        "Disabled"
      )

      Expect.to_have_count!(Page.locator(page, ".crit-page.crit-no-comments"), 1)

      delete_review(request, delete_token)
    end

    test "owner menu — picking a policy closes the panel", %{request: request, page: page} do
      %{"user_id" => user_id, "token" => bearer} = seed_user_and_token(request)

      create_res =
        APIRequestContext.post!(request, "#{api_base_url()}/api/reviews",
          headers: %{"Authorization" => "Bearer #{bearer}"},
          data: %{files: [%{path: "a.md", content: "# hi\n"}], comments: []}
        )

      assert APIResponse.status(create_res) == 201
      %{"url" => url, "delete_token" => delete_token} = APIResponse.json!(create_res)
      [_, token] = String.split(url, "/r/")

      Page.goto!(page, "/test/login-as/#{user_id}")
      load_review(page, token)

      panel = Page.locator(page, "#comment-policy-menu-panel")
      Locator.click!(Page.locator(page, "#comment-policy-menu-trigger"))
      Expect.to_have_attribute!(panel, "data-open", "true")
      Expect.to_be_visible!(panel)

      Locator.click!(Page.locator(page, ~s([data-test="comment-policy-set-logged_in_only"])))
      Expect.to_have_attribute!(panel, "data-open", "false")
      Expect.to_be_hidden!(panel)

      Expect.to_have_attribute!(
        Page.locator(page, "#comment-policy-menu-trigger"),
        "aria-expanded",
        "false"
      )

      Expect.to_contain_text!(
        Page.locator(page, "#comment-policy-menu-trigger"),
        "Login required"
      )

      delete_review(request, delete_token)
    end

    test "open — no banner, no badge for anon viewer", %{request: request, page: page} do
      %{token: token, delete_token: delete_token} = create_review(request)
      load_review(page, token)

      Expect.to_be_hidden!(Page.locator(page, ~s([data-test="signin-banner"])))
      Expect.to_have_count!(Page.locator(page, ~s([data-test="comment-policy-badge"])), 0)
      Expect.to_have_count!(Page.locator(page, ".crit-page.crit-no-comments"), 0)

      delete_review(request, delete_token)
    end
  end
end
