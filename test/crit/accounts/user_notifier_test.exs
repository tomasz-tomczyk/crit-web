defmodule Crit.Accounts.UserNotifierTest do
  use Crit.DataCase, async: true
  import Swoosh.TestAssertions

  alias Crit.Accounts.UserNotifier
  alias Crit.User

  setup do
    {:ok, user: %User{email: "a@b.com"}}
  end

  test "deliver_reset_password_instructions sends an email with the URL", %{user: user} do
    {:ok, _} = UserNotifier.deliver_reset_password_instructions(user, "https://example.test/reset/abc")
    assert_email_sent(fn email ->
      assert email.to == [{"", "a@b.com"}]
      assert email.subject == "Reset your password"
      assert email.text_body =~ "https://example.test/reset/abc"
    end)
  end

  test "deliver_update_email_instructions sends an email with the URL", %{user: user} do
    {:ok, _} = UserNotifier.deliver_update_email_instructions(user, "https://example.test/confirm/xyz")
    assert_email_sent(fn email ->
      assert email.subject == "Confirm your new email"
      assert email.text_body =~ "https://example.test/confirm/xyz"
    end)
  end
end
