defmodule CritWeb.AdminSettingsLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Crit.AccountsFixtures
  alias Crit.Repo
  alias Crit.Settings

  setup do
    original = Application.get_env(:crit, :selfhosted)
    Application.put_env(:crit, :selfhosted, true)
    on_exit(fn -> restore_selfhosted(original) end)
    :ok
  end

  defp restore_selfhosted(nil), do: Application.delete_env(:crit, :selfhosted)
  defp restore_selfhosted(v), do: Application.put_env(:crit, :selfhosted, v)

  defp create_admin!(email \\ "admin@example.com") do
    user = AccountsFixtures.user_fixture(%{email: email})
    {:ok, user} = user |> Crit.User.role_changeset(%{role: :admin}) |> Repo.update()
    user
  end

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id})

  describe "auth gate" do
    test "non-admin is redirected to /dashboard", %{conn: conn} do
      user = AccountsFixtures.user_fixture(%{email: "u@example.com"})
      conn = login(conn, user)

      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/admin/settings")
    end
  end

  describe "form" do
    test "admin sees current values", %{conn: conn} do
      conn = login(conn, create_admin!())

      {:ok, _view, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Max document size"
      assert html =~ "Max comments per review"
      assert html =~ "Max comment body"
    end

    test "save converts MB/KB to bytes and updates the settings row", %{conn: conn} do
      conn = login(conn, create_admin!())
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      view
      |> form("#admin-settings-form",
        setting: %{
          max_document_mb: "1",
          max_comments_per_review: "200",
          max_comment_body_kb: "10"
        }
      )
      |> render_submit()

      assert %{
               max_document_bytes: 1_048_576,
               max_comments_per_review: 200,
               max_comment_body_bytes: 10_240
             } = Settings.get()
    end

    test "validation rejects non-positive numbers", %{conn: conn} do
      conn = login(conn, create_admin!())
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      html =
        view
        |> form("#admin-settings-form",
          setting: %{
            max_document_mb: "-1",
            max_comments_per_review: "0",
            max_comment_body_kb: "0"
          }
        )
        |> render_submit()

      assert html =~ "must be greater than"
    end
  end
end
