defmodule Crit.Accounts.MarketingConsentTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts
  alias Crit.Accounts.MarketingConsentEvent
  alias Crit.AccountsFixtures

  describe "toggle_marketing_consent/2" do
    test "opts in a user with no prior events" do
      user = AccountsFixtures.oauth_user_fixture()

      assert {:ok, true} = Accounts.toggle_marketing_consent(user, "registration_checkbox")
      assert Accounts.marketing_opted_in?(user)
    end

    test "opts out a user who is currently opted in" do
      user = AccountsFixtures.oauth_user_fixture()
      {:ok, true} = Accounts.toggle_marketing_consent(user, "registration_checkbox")

      assert {:ok, false} = Accounts.toggle_marketing_consent(user, "settings_toggle")
      refute Accounts.marketing_opted_in?(user)
    end

    test "toggles back to opted in" do
      user = AccountsFixtures.oauth_user_fixture()
      {:ok, true} = Accounts.toggle_marketing_consent(user, "registration_checkbox")
      {:ok, false} = Accounts.toggle_marketing_consent(user, "settings_toggle")

      assert {:ok, true} = Accounts.toggle_marketing_consent(user, "dashboard_checkbox")
      assert Accounts.marketing_opted_in?(user)
    end
  end

  describe "MarketingConsentEvent changeset" do
    test "rejects invalid action" do
      changeset =
        MarketingConsentEvent.changeset(%MarketingConsentEvent{}, %{
          action: "invalid",
          method: "settings_toggle"
        })

      assert errors_on(changeset).action
    end

    test "rejects invalid method" do
      changeset =
        MarketingConsentEvent.changeset(%MarketingConsentEvent{}, %{
          action: "opted_in",
          method: "invalid"
        })

      assert errors_on(changeset).method
    end
  end

  describe "marketing_opted_in?/1" do
    test "returns false when no events exist" do
      user = AccountsFixtures.oauth_user_fixture()

      refute Accounts.marketing_opted_in?(user)
    end

    test "accepts a user_id string" do
      user = AccountsFixtures.oauth_user_fixture()
      {:ok, true} = Accounts.toggle_marketing_consent(user, "registration_checkbox")

      assert Accounts.marketing_opted_in?(user.id)
    end

    test "events for one user do not affect another" do
      user1 = AccountsFixtures.oauth_user_fixture()
      user2 = AccountsFixtures.oauth_user_fixture()

      {:ok, true} = Accounts.toggle_marketing_consent(user1, "registration_checkbox")

      assert Accounts.marketing_opted_in?(user1)
      refute Accounts.marketing_opted_in?(user2)
    end
  end
end
