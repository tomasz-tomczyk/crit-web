defmodule CritWeb.ReviewDisplayTest do
  use ExUnit.Case, async: true

  alias CritWeb.ReviewDisplay

  defp cookie(map), do: map |> JSON.encode!() |> URI.encode(&URI.char_unreserved?/1)

  test "defaults to line numbers on and scrolling" do
    assert ReviewDisplay.for_cookie(nil) == %{line_numbers: "on", code_overflow: "scroll"}
    assert ReviewDisplay.for_cookie("garbage") == %{line_numbers: "on", code_overflow: "scroll"}
  end

  test "reads the reader's choice from crit-settings" do
    assert ReviewDisplay.for_cookie(cookie(%{"lineNumbers" => "off", "codeOverflow" => "wrap"})) ==
             %{line_numbers: "off", code_overflow: "wrap"}
  end

  test "unknown values fall back" do
    assert ReviewDisplay.for_cookie(cookie(%{"lineNumbers" => 0, "codeOverflow" => "sideways"})) ==
             %{line_numbers: "on", code_overflow: "scroll"}
  end
end
