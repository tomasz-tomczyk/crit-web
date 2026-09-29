defmodule Crit.MarketingConsentEventsTest do
  use Crit.DataCase, async: true
  import Crit.AccountsFixtures
  alias Crit.{Accounts, Newsletters}
  alias Crit.Accounts.MarketingConsentEvent
  import Ecto.Query

  defp request_event(email) do
    Repo.one!(
      from e in MarketingConsentEvent,
        where: e.email == ^email and e.action == :subscription_requested,
        order_by: [desc: e.inserted_at],
        limit: 1
    )
  end

  defp request(email) do
    assert {:ok, :check_inbox} = Newsletters.request_subscription(%{"email" => email})
    assert_receive {:email, message}
    assert message.from == {"Crit", Application.fetch_env!(:crit, :smtp_from)}
    [_, token] = Regex.run(~r{/newsletter/confirm/(\S+)}, message.text_body)
    [_, unsubscribe_token] = Regex.run(~r{/newsletter/unsubscribe/(\S+)}, message.text_body)
    {token, unsubscribe_token}
  end

  test "signup normalizes addresses, requires confirmation, and does not create an account" do
    {token, _} = request("  READER@example.com  ")
    assert request_event("reader@example.com").action == :subscription_requested
    assert Repo.aggregate(Crit.User, :count) == 0
    assert Newsletters.recipients() == []
    assert {:ok, _} = Newsletters.confirm_subscription(token)
    assert Newsletters.recipients() == ["reader@example.com"]
    assert {:error, :invalid_token} = Newsletters.confirm_subscription(token)
  end

  test "duplicate requests neither create duplicate rows nor resend during cooldown" do
    {token, _} = request("reader@example.com")
    assert {:ok, :check_inbox} = Newsletters.request_subscription(%{email: "READER@example.com"})
    refute_receive {:email, _}
    assert Repo.aggregate(MarketingConsentEvent, :count) == 1
    assert {:ok, _} = Newsletters.confirm_subscription(token)
    assert {:ok, :check_inbox} = Newsletters.request_subscription(%{email: "reader@example.com"})
    refute_receive {:email, _}
  end

  test "requests, confirmations, and unsubscribes retain separate history rows" do
    {token, unsubscribe_token} = request("reader@example.com")
    assert {:ok, _} = Newsletters.confirm_subscription(token)
    assert {:ok, _} = Newsletters.unsubscribe(unsubscribe_token)

    events =
      Repo.all(
        from e in MarketingConsentEvent,
          where: e.email == "reader@example.com",
          order_by: e.inserted_at
      )

    assert Enum.map(events, & &1.action) == [:subscription_requested, :opted_in, :opted_out]

    assert Enum.map(events, & &1.method) == [
             :newsletter_form,
             :newsletter_confirmation,
             :newsletter_unsubscribe
           ]

    assert Enum.all?(events, &is_nil(&1.user_id))
    refute Newsletters.opted_in?("reader@example.com")
  end

  test "invalid addresses cannot subscribe" do
    for email <- [
          "",
          "not-an-email",
          "a@@example.com",
          "a b@example.com",
          String.duplicate("x", 161) <> "@example.com"
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Newsletters.request_subscription(%{email: email})
    end

    assert Repo.aggregate(MarketingConsentEvent, :count) == 0
    refute_receive {:email, _}
  end

  test "expired, tampered, and superseded confirmations cannot subscribe" do
    {token, _} = request("reader@example.com")
    subscription = request_event("reader@example.com")

    expired =
      Phoenix.Token.sign(
        CritWeb.Endpoint,
        "newsletter-confirm",
        {subscription.id, subscription.confirmation_nonce},
        signed_at: System.system_time(:second) - 86_401
      )

    assert {:error, :invalid_token} = Newsletters.confirm_subscription(expired)
    assert {:error, :invalid_token} = Newsletters.confirm_subscription(token <> "invalid")

    subscription
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -601))
    |> Repo.update!()

    {replacement, _} = request("reader@example.com")
    assert {:error, :invalid_token} = Newsletters.confirm_subscription(token)
    assert {:ok, _} = Newsletters.confirm_subscription(replacement)
  end

  test "unsubscribing cancels pending confirmation and supports confirmed resubscription" do
    {token, unsubscribe_token} = request("reader@example.com")
    assert {:ok, _} = Newsletters.unsubscribe(unsubscribe_token)
    assert {:error, :invalid_token} = Newsletters.confirm_subscription(token)
    assert Newsletters.recipients() == []
    subscription = request_event("reader@example.com")

    subscription
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -601))
    |> Repo.update!()

    {replacement, _} = request("reader@example.com")
    assert Newsletters.recipients() == []
    assert {:ok, _} = Newsletters.confirm_subscription(replacement)
    assert Newsletters.recipients() == ["reader@example.com"]
    assert {:ok, _} = Newsletters.unsubscribe(unsubscribe_token)
    assert Newsletters.recipients() == []
  end

  test "account and standalone consent agree; the latest choice wins and recipients are deduplicated" do
    user = user_fixture(email: "reader@example.com")
    assert {:ok, true} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    {token, unsubscribe_token} = request(user.email)
    assert {:ok, _} = Newsletters.confirm_subscription(token)
    assert Newsletters.recipients() == [user.email]
    assert Accounts.marketing_opted_in?(user)
    assert Accounts.marketing_opted_in?(user.id)
    assert {:ok, false} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    refute Newsletters.opted_in?(user.email)
    assert Newsletters.recipients() == []
    # A new request must not itself override an opt-out.
    subscription = request_event(user.email)

    subscription
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -601))
    |> Repo.update!()

    {new_token, _} = request(user.email)
    assert Newsletters.recipients() == []
    assert {:ok, _} = Newsletters.confirm_subscription(new_token)
    assert Accounts.marketing_opted_in?(user)
    assert {:ok, _} = Newsletters.unsubscribe(unsubscribe_token)
    refute Accounts.marketing_opted_in?(user)
    assert {:ok, true} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    assert Newsletters.recipients() == [user.email]
  end

  test "an account opt-out cancels an older public confirmation" do
    user = user_fixture(email: "reader@example.com")
    assert {:ok, true} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    {token, _} = request(user.email)
    assert {:ok, false} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    assert {:error, :invalid_token} = Newsletters.confirm_subscription(token)
    assert Newsletters.recipients() == []
  end

  test "account email changes and deletion do not revive an opted-out address" do
    user = user_fixture(email: "reader@example.com")
    {token, _} = request(user.email)
    assert {:ok, _} = Newsletters.confirm_subscription(token)
    assert {:ok, false} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    assert {:ok, user} = Accounts.update_user_profile(user, %{"email" => "new@example.com"})
    refute Newsletters.opted_in?("reader@example.com")
    assert Newsletters.recipients() == []
    assert :ok = Accounts.delete_user(user)
    refute Newsletters.opted_in?("reader@example.com")
    assert Newsletters.recipients() == []
  end

  test "account opt-in follows an updated email while old opt-outs remain suppressed" do
    user = user_fixture(email: "reader@example.com")
    assert {:ok, true} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    assert {:ok, updated} = Accounts.update_user_profile(user, %{"email" => "new@example.com"})
    assert Accounts.marketing_opted_in?(updated)
    assert Newsletters.recipients() == ["new@example.com"]
  end

  test "account opt-ins are not sent to an old address when its current email is removed" do
    user = user_fixture(email: "reader@example.com")
    assert {:ok, true} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    user |> Ecto.Changeset.change(email: nil) |> Repo.update!()
    refute Newsletters.opted_in?("reader@example.com")
    assert Newsletters.recipients() == []
  end

  test "deletion preserves the effective opt-out at a changed account email" do
    {token, _} = request("new@example.com")
    assert {:ok, _} = Newsletters.confirm_subscription(token)
    user = user_fixture(email: "reader@example.com")
    assert {:ok, true} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    assert {:ok, false} = Accounts.toggle_marketing_consent(user, "settings_toggle")
    assert {:ok, updated} = Accounts.update_user_profile(user, %{"email" => "new@example.com"})
    refute Accounts.marketing_opted_in?(updated)
    assert :ok = Accounts.delete_user(updated)
    refute Newsletters.opted_in?("new@example.com")
    assert Newsletters.recipients() == []
  end

  test "signup source is stored separately and preserved on duplicate requests" do
    for source <- ~w(homepage archive footer) do
      email = "#{source}@example.com"

      assert {:ok, :check_inbox} =
               Newsletters.request_subscription(%{
                 email: email,
                 source: source,
                 source_path: "/features"
               })

      assert_receive {:email, message}
      [_, token] = Regex.run(~r{/newsletter/confirm/(\S+)}, message.text_body)
      subscription = request_event(email)
      assert Atom.to_string(subscription.source) == source
      assert subscription.source_path == "/features"
      assert {:ok, _} = Newsletters.confirm_subscription(token)

      assert {:ok, :check_inbox} =
               Newsletters.request_subscription(%{
                 email: email,
                 source: "archive",
                 source_path: "/newsletter"
               })

      assert request_event(email).source == subscription.source
      assert request_event(email).source_path == "/features"
      refute_receive {:email, _}
    end
  end

  test "signup page paths exclude external URLs, query strings, and fragments" do
    for path <- ["https://example.com", "//example.com", "/?token=secret", "/#section"] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Newsletters.request_subscription(%{email: "reader@example.com", source_path: path})
    end

    refute_receive {:email, _}
  end

  test "unknown signup sources are rejected" do
    assert {:error, %Ecto.Changeset{valid?: false}} =
             Newsletters.request_subscription(%{email: "reader@example.com", source: "unknown"})

    refute_receive {:email, _}
  end
end
