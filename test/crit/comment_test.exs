defmodule Crit.CommentTest do
  use Crit.DataCase, async: true

  alias Crit.Comment

  @valid_attrs %{
    start_line: 1,
    end_line: 3,
    body: "Looks good!",
    author_identity: "550e8400-e29b-41d4-a716-446655440000",
    review_round: 0
  }

  describe "create_changeset/2" do
    test "valid attrs produce valid changeset" do
      changeset = Comment.create_changeset(%Comment{}, @valid_attrs)
      assert changeset.valid?
    end

    test "body is required" do
      attrs = Map.delete(@valid_attrs, :body)
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "start_line is optional (nullable for replies)" do
      attrs = Map.delete(@valid_attrs, :start_line)
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert changeset.valid?
    end

    test "end_line is optional (nullable for replies)" do
      attrs = Map.delete(@valid_attrs, :end_line)
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert changeset.valid?
    end

    test "start_line must be greater than 0" do
      attrs = %{@valid_attrs | start_line: 0}
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert %{start_line: _} = errors_on(changeset)
    end

    test "end_line must be greater than 0" do
      attrs = %{@valid_attrs | end_line: 0}
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert %{end_line: _} = errors_on(changeset)
    end

    test "body has max length of 50KB" do
      huge_body = String.duplicate("x", 51_201)
      attrs = %{@valid_attrs | body: huge_body}
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert %{body: ["must be at most 50 KB"]} = errors_on(changeset)
    end

    test "display_name has max length of 40" do
      long_name = String.duplicate("a", 41)
      attrs = Map.put(@valid_attrs, :author_display_name, long_name)
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert %{author_display_name: _} = errors_on(changeset)
    end

    test "accepts optional display_name" do
      attrs = Map.put(@valid_attrs, :author_display_name, "Alice")
      changeset = Comment.create_changeset(%Comment{}, attrs)
      assert changeset.valid?
    end
  end
end
