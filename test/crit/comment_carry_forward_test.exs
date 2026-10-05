defmodule Crit.CommentCarryForwardTest do
  use ExUnit.Case, async: true

  alias Crit.CommentCarryForward

  test "follows an anchor when lines are inserted above it" do
    old = "# Plan\n\nStep 1\n\nStep 2\n"
    new = "# Plan\n\nNew line A\nNew line B\nStep 1\n\nStep 2\n"

    assert CommentCarryForward.place(old, new, 3, 3, "Step 1") == {5, 5, false}
  end

  test "marks a comment drifted when its anchor text is gone" do
    old = "# Plan\n\nStep 1\n"
    new = "# Plan\n\nSomething else\n"

    assert CommentCarryForward.place(old, new, 3, 3, "Step 1") == {3, 3, true}
  end

  test "keeps an in-place append anchored" do
    anchor = "- Don't create a group for just 1 commit — merge it into the closest group"

    old = "# Plan\n\n#{anchor}\n"

    new =
      "# Plan\n\n#{anchor} (unless it's a single significant feature that warrants its own callout)\n"

    assert CommentCarryForward.place(old, new, 3, 3, anchor) == {3, 3, false}
  end

  test "keeps a line anchored when a middle clause is cut out" do
    anchor = "      continue. If this organization has no locations yet,{\" \"}"

    old =
      "<div>\n  Please select a location above to\n" <>
        anchor <> "\n  <Link to=\"/admin\">create one here</Link>\n</div>\n"

    new =
      "<div>\n  Please select a location above to\n" <>
        "      continue.{\" \"}\n" <>
        "  <Link to=\"/admin\">Go to admin to create one</Link>\n</div>\n"

    assert CommentCarryForward.place(old, new, 3, 3, anchor) == {3, 3, false}
  end

  test "remaps without a drift flag when there is no anchor" do
    old = "# Plan\n\nStep 1\n\nStep 2\n"
    new = "# Plan\n\nNew line A\nNew line B\nStep 1\n\nStep 2\n"

    assert CommentCarryForward.place(old, new, 3, 3, nil) == {5, 5, false}
  end

  test "extracts the commented lines from the file they were written against" do
    content = "# Plan\n\nStep 1\nStep 2\n"

    assert CommentCarryForward.extract_anchor(content, 3, 4) == "Step 1\nStep 2"
    assert CommentCarryForward.extract_anchor(content, 0, 1) == ""
    assert CommentCarryForward.extract_anchor("", 1, 1) == ""
  end

  test "a sent position still counts as anchored when the line was only extended" do
    anchor = "keep this sentence"
    content = "intro\nkeep this sentence, and more\n"

    refute CommentCarryForward.drifted_at?(content, 2, 2, anchor)
  end

  test "a sent position is drifted when the anchor is no longer on that line" do
    assert CommentCarryForward.drifted_at?("intro\ngone\n", 2, 2, "keep this sentence intact")
  end
end
