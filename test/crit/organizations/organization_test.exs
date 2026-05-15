defmodule Crit.Organizations.OrganizationTest do
  use Crit.DataCase, async: true

  alias Crit.Organizations.Organization

  describe "changeset/2" do
    test "valid with name and slug" do
      changeset = Organization.changeset(%Organization{}, %{name: "Acme", slug: "acme"})
      assert changeset.valid?
    end

    test "requires name" do
      changeset = Organization.changeset(%Organization{}, %{name: "", slug: "acme"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires slug" do
      changeset = Organization.changeset(%Organization{}, %{name: "Acme", slug: ""})
      refute changeset.valid?
    end

    test "rejects name longer than 120 chars" do
      long_name = String.duplicate("a", 121)
      changeset = Organization.changeset(%Organization{}, %{name: long_name, slug: "acme"})
      assert %{name: [msg]} = errors_on(changeset)
      assert msg =~ "at most"
    end

    test "rejects control characters in name" do
      changeset = Organization.changeset(%Organization{}, %{name: "Acme\x00", slug: "acme"})
      assert %{name: ["must not contain control characters"]} = errors_on(changeset)
    end

    test "downcases slug" do
      changeset = Organization.changeset(%Organization{}, %{name: "Acme", slug: "ACME"})
      assert get_change(changeset, :slug) == "acme"
    end

    test "rejects invalid slug format" do
      changeset = Organization.changeset(%Organization{}, %{name: "Acme", slug: "-invalid-"})
      assert %{slug: [_]} = errors_on(changeset)
    end

    test "rejects slug shorter than 2 chars" do
      changeset = Organization.changeset(%Organization{}, %{name: "Acme", slug: "a"})
      assert %{slug: [_]} = errors_on(changeset)
    end
  end

  describe "create_changeset/2" do
    test "auto-generates slug from name when slug not provided" do
      changeset = Organization.create_changeset(%Organization{}, %{name: "Acme Corp"})
      assert changeset.valid?
      assert get_change(changeset, :slug) == "acme-corp"
    end

    test "uses provided slug over auto-generated" do
      changeset =
        Organization.create_changeset(%Organization{}, %{name: "Acme Corp", slug: "my-slug"})

      assert get_change(changeset, :slug) == "my-slug"
    end

    test "requires name" do
      changeset = Organization.create_changeset(%Organization{}, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "generate_slug/1" do
    test "downcases and replaces spaces with hyphens" do
      assert Organization.generate_slug("My Cool Org") == "my-cool-org"
    end

    test "strips special characters" do
      assert Organization.generate_slug("Acme, Inc.") == "acme-inc"
    end

    test "collapses multiple hyphens" do
      assert Organization.generate_slug("Acme -- Corp") == "acme-corp"
    end

    test "trims leading and trailing hyphens" do
      assert Organization.generate_slug(" -Acme- ") == "acme"
    end

    test "prefixes short results with org-" do
      assert Organization.generate_slug("A") == "org-a"
    end

    test "truncates to 60 chars" do
      long_name = String.duplicate("abcdefghij", 10)
      slug = Organization.generate_slug(long_name)
      assert String.length(slug) <= 60
    end
  end
end
