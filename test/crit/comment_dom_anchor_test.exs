defmodule Crit.CommentDomAnchorTest do
  use Crit.DataCase, async: true
  alias Crit.Comment

  @anchor %{
    "pathname" => "/",
    "css_selector" => "body > main > h1",
    "tag_chain" => ["body", "main", "h1"],
    "outer_html" => "<h1>Hi</h1>"
  }

  test "stores dom_anchor map" do
    cs =
      Comment.create_changeset(%Comment{}, %{
        "start_line" => 0,
        "end_line" => 0,
        "body" => "nice heading",
        "scope" => "file",
        "dom_anchor" => @anchor
      })

    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :dom_anchor)["css_selector"] == "body > main > h1"
  end

  test "rejects dom_anchor missing css_selector" do
    cs =
      Comment.create_changeset(%Comment{}, %{
        "start_line" => 0,
        "end_line" => 0,
        "body" => "x",
        "scope" => "file",
        "dom_anchor" => %{"pathname" => "/"}
      })

    refute cs.valid?
  end
end
