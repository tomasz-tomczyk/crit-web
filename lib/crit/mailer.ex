defmodule Crit.Mailer do
  @moduledoc """
  Swoosh mailer. `configured?/0` reports whether outbound mail can actually be
  delivered (i.e. the runtime adapter is something other than the no-op
  `Swoosh.Adapters.Local`). Used to gate forgot-password / change-email forms
  in selfhost deployments where SMTP isn't set up.
  """
  use Swoosh.Mailer, otp_app: :crit

  @spec configured?() :: boolean()
  def configured? do
    case Application.get_env(:crit, __MODULE__, [])[:adapter] do
      Swoosh.Adapters.SMTP -> true
      Swoosh.Adapters.Test -> true
      _ -> false
    end
  end
end
