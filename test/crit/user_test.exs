defmodule Crit.UserTest do
  use Crit.DataCase, async: true

  alias Crit.User

  describe "registration_changeset/3" do
    test "requires email and password" do
      changeset = User.registration_changeset(%User{}, %{})
      refute changeset.valid?
      assert %{email: ["can't be blank"], password: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email format" do
      changeset =
        User.registration_changeset(%User{}, %{email: "not-an-email", password: "supersecret123"})

      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "validates minimum password length" do
      changeset = User.registration_changeset(%User{}, %{email: "a@b.com", password: "short"})
      assert "should be at least 8 byte(s)" in errors_on(changeset).password
    end

    test "downcases email" do
      changeset =
        User.registration_changeset(%User{}, %{email: "A@B.com", password: "supersecret123"})

      assert get_change(changeset, :email) == "a@b.com"
    end

    test "hashes the password" do
      changeset =
        User.registration_changeset(%User{}, %{email: "a@b.com", password: "supersecret123"})

      refute get_change(changeset, :password)
      assert hashed = get_change(changeset, :hashed_password)
      assert Bcrypt.verify_pass("supersecret123", hashed)
    end
  end

  describe "valid_password?/2" do
    test "true for correct password, false for wrong" do
      hash = Bcrypt.hash_pwd_salt("supersecret123")
      assert User.valid_password?(%User{hashed_password: hash}, "supersecret123")
      refute User.valid_password?(%User{hashed_password: hash}, "wrong")
    end

    test "false when no hash present (no-user-verify path)" do
      refute User.valid_password?(%User{hashed_password: nil}, "anything")
    end
  end

  describe "password_changeset/3" do
    test "rejects mismatched confirmation" do
      changeset =
        User.password_changeset(%User{}, %{
          password: "supersecret123",
          password_confirmation: "different-pw-1234"
        })

      assert "does not match password" in errors_on(changeset).password_confirmation
    end

    test "happy path hashes" do
      changeset =
        User.password_changeset(%User{}, %{
          password: "supersecret123",
          password_confirmation: "supersecret123"
        })

      assert get_change(changeset, :hashed_password)
      refute get_change(changeset, :password)
    end
  end

  describe "oauth_changeset/2" do
    test "requires provider and provider_uid" do
      changeset = User.oauth_changeset(%User{}, %{})
      refute changeset.valid?

      assert %{provider: ["can't be blank"], provider_uid: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "invalid without provider" do
      changeset = User.oauth_changeset(%User{}, %{provider_uid: "12345"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).provider
    end

    test "invalid without provider_uid" do
      changeset = User.oauth_changeset(%User{}, %{provider: "github"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).provider_uid
    end

    test "allows nil email and name" do
      changeset =
        User.oauth_changeset(%User{}, %{
          provider: "github",
          provider_uid: "12345",
          email: nil,
          name: nil
        })

      assert changeset.valid?
    end

    test "downcases email" do
      changeset =
        User.oauth_changeset(%User{}, %{
          provider: "github",
          provider_uid: "12345",
          email: "User@Example.COM"
        })

      assert get_change(changeset, :email) == "user@example.com"
    end

    test "valid with full attrs" do
      attrs = %{
        provider: "github",
        provider_uid: "12345",
        email: "user@example.com",
        name: "Jane Doe",
        avatar_url: "https://example.com/avatar.png"
      }

      changeset = User.oauth_changeset(%User{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :email) == "user@example.com"
      assert get_change(changeset, :name) == "Jane Doe"
      assert get_change(changeset, :avatar_url) == "https://example.com/avatar.png"
    end
  end
end
