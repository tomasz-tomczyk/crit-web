defmodule Crit.NewslettersTest do
  use ExUnit.Case, async: true

  alias Crit.Newsletters

  test "browser_html rewrites relative image paths and the unsubscribe token" do
    html = ~s(<img src="images/a.png"><a href="{{{ pm:unsubscribe }}}">x</a>)

    out = Newsletters.browser_html(%{slug: "s", html: html})

    assert out =~ ~s(src="/newsletter/s/images/a.png")
    assert out =~ ~s(href="/settings")
  end
end
