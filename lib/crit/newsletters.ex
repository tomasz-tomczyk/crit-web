defmodule Crit.Newsletters do
  @moduledoc """
  Hosted-only newsletter archives loaded from `priv/newsletters/<slug>/`.

  Each newsletter is a full HTML email (`index.html`) plus optional `images/`.
  Production email sends should point image `src` at Cloudflare R2
  (`https://assets.crit.md/newsletter/<slug>/…`); the browser view rewrites
  relative `images/` paths to the local image route for preview and for
  archives that still use relative paths.
  """

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
