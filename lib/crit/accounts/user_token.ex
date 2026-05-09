defmodule Crit.Accounts.UserToken do
  use Crit.Schema

  import Ecto.Query

  alias Crit.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  @remember_me_validity_in_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Crit.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Builds a hashed token used for remember-me."
  def build_hashed_token(user, context, sent_to)
      when context in ["remember_me"] do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Verifies a token against the database for a given context, returning the
  associated user when valid and within TTL.
  """
  def verify_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        days = days_for_context(context)

        query =
          from t in UserToken,
            join: u in assoc(t, :user),
            where:
              t.token == ^hashed and
                t.context == ^context and
                t.inserted_at > ago(^days, "day"),
            select: u

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Query for tokens of one or more contexts belonging to a user."
  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  defp days_for_context("remember_me"), do: @remember_me_validity_in_days
end
