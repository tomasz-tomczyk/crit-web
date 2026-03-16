defmodule Crit.ChangelogTest do
  use ExUnit.Case, async: true

  alias Crit.Changelog

  describe "parse_release/2" do
    test "parses a GitHub release API response into a release map" do
      api_response = %{
        "tag_name" => "v0.5.1",
        "name" => "v0.5.1",
        "body" => "## What's Changed\n\n* Fix bug by @user",
        "published_at" => "2026-03-10T12:00:00Z",
        "html_url" => "https://github.com/tomasz-tomczyk/crit/releases/tag/v0.5.1",
        "draft" => false,
        "prerelease" => false
      }

      release = Changelog.parse_release(api_response, :cli)

      assert release.version == "v0.5.1"
      assert release.name == "v0.5.1"
      assert release.body_html =~ "Changed"
      assert release.published_at == ~U[2026-03-10 12:00:00Z]
      assert release.url == "https://github.com/tomasz-tomczyk/crit/releases/tag/v0.5.1"
      assert release.source == :cli
    end

    test "returns :skip for draft releases" do
      draft = %{
        "tag_name" => "v0.6.0-rc1",
        "name" => "v0.6.0-rc1",
        "body" => "Draft",
        "published_at" => "2026-03-10T12:00:00Z",
        "html_url" => "https://github.com/tomasz-tomczyk/crit/releases/tag/v0.6.0-rc1",
        "draft" => true,
        "prerelease" => false
      }

      assert Changelog.parse_release(draft, :cli) == :skip
    end

    test "returns :skip for prerelease" do
      prerelease = %{
        "tag_name" => "v0.6.0-rc1",
        "name" => "v0.6.0-rc1",
        "body" => "RC",
        "published_at" => "2026-03-10T12:00:00Z",
        "html_url" => "https://github.com/tomasz-tomczyk/crit/releases/tag/v0.6.0-rc1",
        "draft" => false,
        "prerelease" => true
      }

      assert Changelog.parse_release(prerelease, :cli) == :skip
    end
  end

  describe "format_date/1" do
    test "formats a DateTime as a readable date" do
      assert Changelog.format_date(~U[2026-03-10 12:00:00Z]) == "March 10, 2026"
    end
  end
end
