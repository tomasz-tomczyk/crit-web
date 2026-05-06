defmodule Crit.MailerTest do
  use ExUnit.Case, async: false

  test "configured?/0 returns true for Test adapter" do
    assert Crit.Mailer.configured?()
  end

  test "configured?/0 returns true for SMTP adapter" do
    original = Application.get_env(:crit, Crit.Mailer)
    on_exit(fn -> Application.put_env(:crit, Crit.Mailer, original) end)

    Application.put_env(:crit, Crit.Mailer, adapter: Swoosh.Adapters.SMTP)
    assert Crit.Mailer.configured?()
  end

  test "configured?/0 returns false for Local adapter" do
    original = Application.get_env(:crit, Crit.Mailer)
    on_exit(fn -> Application.put_env(:crit, Crit.Mailer, original) end)

    Application.put_env(:crit, Crit.Mailer, adapter: Swoosh.Adapters.Local)
    refute Crit.Mailer.configured?()
  end
end
