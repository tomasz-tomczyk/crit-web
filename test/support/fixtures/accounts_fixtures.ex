defmodule Crit.AccountsFixtures do
  @moduledoc """
  Test helpers for creating user-related entities.
  """

  alias Crit.Accounts

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def oauth_user_fixture(attrs \\ %{}) do
    base = %{
      "sub" => "uid#{System.unique_integer([:positive])}",
      "name" => "Test User",
      "email" => unique_user_email(),
      "picture" => "https://example.com/avatar.png"
    }

    params = Map.merge(base, Map.new(attrs, fn {k, v} -> {to_string(k), v} end))
    {:ok, user} = Accounts.find_or_create_from_oauth("github", params)
    user
  end
end
