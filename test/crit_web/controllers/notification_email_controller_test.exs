defmodule CritWeb.NotificationEmailControllerTest do
  use CritWeb.ConnCase, async: true

  import Crit.AccountsFixtures
  import Swoosh.TestAssertions

  alias Crit.Accounts
  alias Crit.Notifications.ExtraAddresses

  test "GET shows a confirm button and does not confirm the address", %{conn: conn} do
    user = user_fixture()
    {:ok, user} = ExtraAddresses.request(user, "work@example.com")
    token = confirmation_token()

    conn = get(conn, ~p"/settings/notification-emails/confirm/#{token}")

    assert html_response(conn, 200) =~ "Confirm this address"
    assert html_response(conn, 200) =~ "Confirm address"
    {:ok, updated} = Accounts.get_user(user.id)
    assert updated.preferences.notification_emails == []
    assert updated.preferences.pending_notification_emails == ["work@example.com"]
  end

  test "POST confirms the address", %{conn: conn} do
    user = user_fixture()
    {:ok, _user} = ExtraAddresses.request(user, "work@example.com")
    token = confirmation_token()

    conn = post(conn, ~p"/settings/notification-emails/confirm/#{token}")

    assert html_response(conn, 200) =~ "Address confirmed"
    {:ok, updated} = Accounts.get_user(user.id)
    assert updated.preferences.notification_emails == ["work@example.com"]
    assert updated.preferences.pending_notification_emails == []
  end

  test "opening the unsubscribe link stops that address", %{conn: conn} do
    user = user_fixture()

    {:ok, user} =
      Accounts.update_preferences(user, %{notification_emails: ["work@example.com"]})

    token =
      user
      |> ExtraAddresses.unsubscribe_url("work@example.com")
      |> String.split("/")
      |> List.last()

    page = get(conn, ~p"/settings/notification-emails/unsubscribe/#{token}")
    assert html_response(page, 200) =~ "will no longer receive"
    {:ok, updated} = Accounts.get_user(user.id)
    assert updated.preferences.notification_emails == []

    page = get(conn, ~p"/settings/notification-emails/unsubscribe/#{token}")
    assert html_response(page, 200) =~ "will no longer receive"
  end

  test "an unknown token is rejected", %{conn: conn} do
    conn = get(conn, ~p"/settings/notification-emails/confirm/not-a-token")
    assert html_response(conn, 422) =~ "Link not valid"
  end

  defp confirmation_token do
    {:email, email} = assert_email_sent()
    [url] = Regex.run(~r{https?://\S+}, email.text_body)
    url |> String.split("/") |> List.last()
  end
end
