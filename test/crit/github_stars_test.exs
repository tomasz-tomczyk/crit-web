defmodule Crit.GithubStarsTest do
  use ExUnit.Case, async: true

  alias Crit.GithubStars

  describe "format_count/1" do
    test "formats small counts without separators" do
      assert GithubStars.format_count(42) == "42"
    end

    test "adds thousands separators" do
      assert GithubStars.format_count(1234) == "1,234"
      assert GithubStars.format_count(1_234_567) == "1,234,567"
    end
  end
end
