defmodule Crit.UserTest do
  use Crit.DataCase, async: true

  alias Crit.User

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = User.changeset(%User{}, %{provider: "github", provider_uid: "12345"})
      assert changeset.valid?
    end

    test "invalid without provider" do
      changeset = User.changeset(%User{}, %{provider_uid: "12345"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).provider
    end

    test "invalid without provider_uid" do
      changeset = User.changeset(%User{}, %{provider: "github"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).provider_uid
    end

    test "accepts optional fields" do
      attrs = %{
        provider: "github",
        provider_uid: "12345",
        email: "user@example.com",
        name: "Jane Doe",
        avatar_url: "https://example.com/avatar.png"
      }

      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :email) == "user@example.com"
      assert get_change(changeset, :name) == "Jane Doe"
    end
  end
end
