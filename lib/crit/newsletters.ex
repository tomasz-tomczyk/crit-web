defmodule Crit.Newsletters do
  @moduledoc """
  Hosted-only newsletter archives loaded from `priv/newsletters/<slug>/`.

  Each newsletter is a full HTML email (`index.html`) plus optional `images/`.
  Production email sends should point image `src` at Cloudflare R2
  (`https://assets.crit.md/newsletter/<slug>/…`); the browser view rewrites
  relative `images/` paths to the local image route for preview and for
  archives that still use relative paths.
  """

  import Ecto.Query
  alias Crit.{Mailer, Repo}
  alias Crit.Accounts.MarketingConsentEvent

  @issues [
    %{
      slug: "2026-09-first-update",
      title: "Story mode, a new renderer, and finish hooks",
      published_at: ~D[2026-09-29],
      description:
        "The first Crit update: a new way to review diffs, faster rendering, and hooks for your review loop."
    }
  ]

  @doc "Published issues, newest first. Draft directories are never listed."
  def list, do: Enum.sort_by(@issues, & &1.published_at, {:desc, Date})

  def change_subscription(attrs \\ %{}),
    do: MarketingConsentEvent.newsletter_changeset(%MarketingConsentEvent{}, attrs)

  @doc "Request confirmation. Requests do not grant consent and are throttled per email."
  def request_subscription(attrs) do
    changeset = change_subscription(attrs)

    if changeset.valid? do
      Repo.transact(fn ->
        email = Ecto.Changeset.get_field(changeset, :email)
        lock_email(email)
        latest = latest_request(email)

        if (latest && opted_in?(email)) ||
             (latest && DateTime.diff(DateTime.utc_now(), latest.inserted_at) < 600) do
          {:ok, :check_inbox}
        else
          invalidate_requests(email)

          request =
            changeset
            |> Ecto.Changeset.put_change(:confirmation_nonce, Ecto.UUID.generate())
            |> Repo.insert!()

          token =
            Phoenix.Token.sign(
              CritWeb.Endpoint,
              "newsletter-confirm",
              {request.id, request.confirmation_nonce}
            )

          url = CritWeb.Endpoint.url() <> "/newsletter/confirm/" <> token

          message =
            Swoosh.Email.new()
            |> Swoosh.Email.to(request.email)
            |> Swoosh.Email.from({"Crit", Application.fetch_env!(:crit, :smtp_from)})
            |> Swoosh.Email.subject("Confirm your Crit newsletter subscription")
            |> Swoosh.Email.text_body("""
            You asked to receive occasional Crit updates.

            Confirm your subscription (this link expires in 24 hours):
            #{url}

            No account needed. You can unsubscribe at any time:
            #{unsubscribe_url(request)}

            If you didn't request this, you can ignore this email.
            """)

          case Mailer.deliver(message) do
            {:ok, _} -> {:ok, :check_inbox}
            {:error, _} -> {:error, :delivery_failed}
          end
        end
      end)
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  def confirmation(token) do
    with {:ok, {id, nonce}} when is_binary(nonce) <-
           Phoenix.Token.verify(CritWeb.Endpoint, "newsletter-confirm", token, max_age: 86_400),
         %MarketingConsentEvent{action: :subscription_requested, confirmation_nonce: ^nonce} =
           request <-
           Repo.get(MarketingConsentEvent, id) do
      {:ok, request}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def confirm_subscription(token) do
    with {:ok, request} <- confirmation(token) do
      Repo.transact(fn ->
        lock_email(request.email)

        # Recheck after the lock: an unsubscribe or newer request may have invalidated it.
        with {:ok, current} <- confirmation(token) do
          invalidate_requests(current.email)
          append_consent(current, :opted_in, "newsletter_confirmation")
        end
      end)
    end
  end

  def unsubscribe_url(request) do
    token = Phoenix.Token.sign(CritWeb.Endpoint, "newsletter-unsubscribe", request.id)
    CritWeb.Endpoint.url() <> "/newsletter/unsubscribe/" <> token
  end

  def subscription_for_unsubscribe(token) do
    with {:ok, id} <-
           Phoenix.Token.verify(CritWeb.Endpoint, "newsletter-unsubscribe", token,
             max_age: :infinity
           ),
         %MarketingConsentEvent{action: :subscription_requested, email: email} = request
         when is_binary(email) <-
           Repo.get(MarketingConsentEvent, id) do
      {:ok, request}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def unsubscribe(token) do
    with {:ok, request} <- subscription_for_unsubscribe(token) do
      Repo.transact(fn ->
        lock_email(request.email)
        invalidate_requests(request.email)
        append_consent(request, :opted_out, "newsletter_unsubscribe")
      end)
    end
  end

  defp append_consent(request, action, method) do
    %MarketingConsentEvent{
      email: request.email,
      source: request.source,
      source_path: request.source_path
    }
    |> MarketingConsentEvent.changeset(%{action: action, method: method})
    |> Repo.insert()
  end

  defp lock_email(email) do
    # A row lock cannot serialize the first request, because no row exists yet.
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [email])
  end

  defp invalidate_requests(email) do
    from(e in MarketingConsentEvent,
      where:
        e.email == ^email and e.action == :subscription_requested and
          not is_nil(e.confirmation_nonce)
    )
    |> Repo.update_all(set: [confirmation_nonce: nil])
  end

  defp latest_request(email) do
    Repo.one(
      from e in MarketingConsentEvent,
        where: e.email == ^email and e.action == :subscription_requested,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: 1
    )
  end

  defp consent_query do
    from e in MarketingConsentEvent,
      left_join: u in Crit.User,
      on: u.id == e.user_id,
      where: e.action in [:opted_in, :opted_out],
      select:
        {fragment(
           "lower(CASE WHEN ? IS NOT NULL THEN ? ELSE ? END)",
           e.user_id,
           u.email,
           e.email
         ), e.action, e.inserted_at, e.id}
  end

  @doc "Current consent across account and anonymous events; requests do not count as opt-ins."
  def opted_in?(email) when is_binary(email) do
    latest =
      consent_query()
      |> where(
        [e, u],
        fragment("lower(CASE WHEN ? IS NOT NULL THEN ? ELSE ? END)", e.user_id, u.email, e.email) ==
          ^String.downcase(email) or
          (e.action == :opted_out and e.email == ^String.downcase(email))
      )
      |> order_by([e], desc: e.inserted_at, desc: e.id)
      |> limit(1)
      |> Repo.one()

    match?({_, :opted_in, _, _}, latest)
  end

  def opted_in?(_), do: false

  @doc "Confirmed newsletter recipients from the existing consent event history, deduplicated."
  def recipients do
    current_addresses = Repo.all(consent_query())

    suppressed_addresses =
      Repo.all(
        from e in MarketingConsentEvent,
          where: e.action == :opted_out and not is_nil(e.email),
          select: {e.email, e.action, e.inserted_at, e.id}
      )

    # Account preferences follow the current account email; historical opt-outs
    # also remain attached to the address at which they were made.
    (current_addresses ++ suppressed_addresses)
    |> Enum.reject(fn {email, _, _, _} -> is_nil(email) end)
    |> Enum.group_by(fn {email, _, _, _} -> email end)
    |> Enum.filter(fn {_, events} ->
      {_, action, _, _} =
        Enum.max_by(events, fn {_, _, time, id} ->
          {DateTime.to_unix(time, :microsecond), id}
        end)

      action == :opted_in
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @assets_prefix "https://assets.crit.md/newsletter"

  @doc "Lookup a newsletter by slug. Returns nil when missing."
  def get(slug) when is_binary(slug) do
    path = Path.join([root(), slug, "index.html"])

    if File.exists?(path) do
      %{slug: slug, path: path, html: File.read!(path)}
    else
      nil
    end
  end

  def get(_), do: nil

  @doc "Absolute path to an image under a newsletter's images/ dir, or nil."
  def image_path(slug, name) when is_binary(slug) and is_binary(name) do
    if safe_image_name?(name) do
      path = Path.join([root(), slug, "images", name])
      if File.exists?(path), do: path, else: nil
    else
      nil
    end
  end

  def image_path(_, _), do: nil

  @doc """
  Prepare HTML for the hosted browser view: rewrite relative image paths and
  neutralize Postmark-only tokens that don't apply outside the inbox.
  """
  def browser_html(%{slug: slug, html: html}) do
    html
    |> String.replace(~s(src="images/), ~s(src="/newsletter/#{slug}/images/))
    |> String.replace("{{{ pm:unsubscribe }}}", "/settings")
  end

  @doc "Canonical R2 URL for a newsletter image (for email HTML before send)."
  def asset_url(slug, name), do: "#{@assets_prefix}/#{slug}/#{name}"

  defp root, do: Path.join(:code.priv_dir(:crit), "newsletters")

  defp safe_image_name?(name) do
    name != "" and not String.contains?(name, "..") and not String.contains?(name, "/") and
      not String.contains?(name, "\\")
  end
end
