defmodule Mix.Tasks.Crit.CreateUserTest do
  use Crit.DataCase, async: false

  test "creates a user" do
    Mix.Task.run("crit.create_user", ["new@example.com", "supersecret-1234"])
    assert Crit.Accounts.get_user_by_email("new@example.com")
  end
end
