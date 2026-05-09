defmodule Crit.Accounts.UserTokenTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts.UserToken
  alias Crit.{Repo, User}

  setup do
    {:ok, user} =
      %User{}
      |> User.registration_changeset(%{email: "a@b.com", password: "supersecret123"})
      |> Repo.insert()

    {:ok, user: user}
  end

  test "build_hashed_token returns plaintext + struct, hash matches", %{user: user} do
    {plaintext, %UserToken{} = struct} =
      UserToken.build_hashed_token(user, "remember_me", user.email)

    assert is_binary(plaintext)
    assert struct.context == "remember_me"
    assert struct.sent_to == user.email
    assert struct.user_id == user.id

    expected_hash = :crypto.hash(:sha256, Base.url_decode64!(plaintext, padding: false))
    assert struct.token == expected_hash
  end

  test "verify_token_query finds the user for a valid token", %{user: user} do
    {plaintext, struct} = UserToken.build_hashed_token(user, "remember_me", user.email)
    Repo.insert!(struct)

    {:ok, query} = UserToken.verify_token_query(plaintext, "remember_me")
    assert Repo.one(query).id == user.id
  end
end
