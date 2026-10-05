defmodule Crit.Notifications.ExtraAddressesTest do
  use Crit.DataCase, async: true

  import Crit.AccountsFixtures
  import Swoosh.TestAssertions

  alias Crit.Accounts
  alias Crit.Notifications.ExtraAddresses

  test "request stores the address as pending and emails a confirmation link" do
    user = user_fixture(%{name: "Owner"})

    assert {:ok, updated} = ExtraAddresses.request(user, " Work@Example.com ")
    assert updated.preferences.notification_emails == []
    assert updated.preferences.pending_notification_emails == ["work@example.com"]

    assert_email_sent(fn email ->
      assert email.to == [{"", "work@example.com"}]
      assert email.subject == "Confirm this address for Crit notifications"
      assert email.text_body =~ "Owner (#{user.email})"
      assert email.text_body =~ "/settings/notification-emails/confirm/"
      refute email.text_body =~ "/r/"
      true
    end)
  end

  test "request rejects the account address, duplicates, and a fourth address" do
    user = user_fixture()

    assert {:error, :included} = ExtraAddresses.request(user, user.email)
    assert {:ok, user} = ExtraAddresses.request(user, "a@example.com")
    assert {:error, :pending} = ExtraAddresses.request(user, "a@example.com")

    assert {:ok, user} = ExtraAddresses.request(user, "b@example.com")
    assert {:ok, user} = ExtraAddresses.request(user, "c@example.com")
    assert {:error, %Ecto.Changeset{}} = ExtraAddresses.request(user, "d@example.com")
    assert length(user.preferences.pending_notification_emails) == 3
  end

  test "confirm moves a pending address onto the recipient list" do
    user = user_fixture()
    {:ok, user} = ExtraAddresses.request(user, "work@example.com")

    assert_email_sent(fn email ->
      [url] = Regex.run(~r{https?://\S+}, email.text_body)
      token = url |> String.split("/") |> List.last()

      assert {:ok, :pending, "work@example.com"} = ExtraAddresses.preview(token)
      assert user.preferences.notification_emails == []

      assert {:ok, "work@example.com"} = ExtraAddresses.confirm(token)
      assert {:ok, "work@example.com"} = ExtraAddresses.confirm(token)

      {:ok, updated} = Accounts.get_user(user.id)
      assert updated.preferences.notification_emails == ["work@example.com"]
      assert updated.preferences.pending_notification_emails == []
      assert {:ok, :confirmed, "work@example.com"} = ExtraAddresses.preview(token)
      true
    end)
  end

  test "unsubscribe removes a confirmed address and a second use stays unsubscribed" do
    user = user_fixture()

    {:ok, user} =
      Accounts.update_preferences(user, %{notification_emails: ["work@example.com"]})

    token =
      user
      |> ExtraAddresses.unsubscribe_url("work@example.com")
      |> String.split("/")
      |> List.last()

    assert {:ok, :active, "work@example.com"} = ExtraAddresses.unsubscribe_preview(token)
    assert {:ok, "work@example.com"} = ExtraAddresses.unsubscribe(token)
    assert {:ok, "work@example.com"} = ExtraAddresses.unsubscribe(token)

    {:ok, updated} = Accounts.get_user(user.id)
    assert updated.preferences.notification_emails == []
    assert {:ok, :gone, "work@example.com"} = ExtraAddresses.unsubscribe_preview(token)
  end

  test "confirm rejects a token after the address is removed" do
    user = user_fixture()
    {:ok, user} = ExtraAddresses.request(user, "work@example.com")

    assert_email_sent(fn email ->
      [url] = Regex.run(~r{https?://\S+}, email.text_body)
      token = url |> String.split("/") |> List.last()

      {:ok, _} =
        Accounts.update_preferences(user, %{
          pending_notification_emails: []
        })

      assert :error = ExtraAddresses.preview(token)
      assert :error = ExtraAddresses.confirm(token)
      true
    end)
  end
end
