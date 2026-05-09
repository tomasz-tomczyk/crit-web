defmodule CritWeb.AdminUsersLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  alias Crit.Accounts
  alias Crit.AccountsFixtures
  alias Crit.Repo

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

  defp create_user!(email) do
    AccountsFixtures.user_fixture(%{email: email})
  end

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id})

  describe "auth gate" do
    test "non-admin is halted and redirected with flash", %{conn: conn} do
      user = create_user!("regular@example.com")
      conn = login(conn, user)

      assert {:error, {:redirect, %{to: "/dashboard", flash: flash}}} =
               live(conn, ~p"/admin/users")

      assert flash["error"] =~ "Admins"
    end

    test "unauthenticated is redirected via :require_authenticated_user", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/admin/users")
      assert to =~ "log_in" or to =~ "/auth/login" or to == "/"
    end
  end

  describe "admin user list" do
    test "admin sees themselves and other users", %{conn: conn} do
      admin = create_admin!()
      _other = create_user!("alice@example.com")

      conn = login(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ admin.email
      assert html =~ "alice@example.com"
    end
  end

  describe "delete user (with email confirmation)" do
    test "admin deletes a non-admin user, cascading their reviews and comments", %{conn: conn} do
      admin = create_admin!()
      target = create_user!("victim@example.com")

      review = review_fixture(user_id: target.id)

      conn = login(conn, admin)
      {:ok, view, _} = live(conn, ~p"/admin/users")

      view
      |> element("[data-test='delete-user-#{target.id}']")
      |> render_click()

      assert has_element?(view, "#delete-user-modal")

      view
      |> form("#confirm-delete-form", %{"confirmation" => target.email})
      |> render_submit()

      assert {:error, :not_found} = Accounts.get_user(target.id)
      refute Repo.get(Crit.Review, review.id)
    end

    test "admin can delete a fellow admin (no env-pinned UI gate)", %{conn: conn} do
      admin = create_admin!("a1@example.com")
      other_admin = create_admin!("a2@example.com")

      conn = login(conn, admin)
      {:ok, view, _} = live(conn, ~p"/admin/users")

      view
      |> element("[data-test='delete-user-#{other_admin.id}']")
      |> render_click()

      view
      |> form("#confirm-delete-form", %{"confirmation" => other_admin.email})
      |> render_submit()

      assert {:error, :not_found} = Accounts.get_user(other_admin.id)
    end

    test "wrong email leaves the user in place", %{conn: conn} do
      admin = create_admin!()
      target = create_user!("victim@example.com")

      conn = login(conn, admin)
      {:ok, view, _} = live(conn, ~p"/admin/users")

      view
      |> element("[data-test='delete-user-#{target.id}']")
      |> render_click()

      view
      |> form("#confirm-delete-form", %{"confirmation" => "wrong@example.com"})
      |> render_submit()

      assert {:ok, _} = Accounts.get_user(target.id)
      assert has_element?(view, "#delete-user-modal")
    end

    test "email match is case-insensitive and trims whitespace", %{conn: conn} do
      admin = create_admin!()
      target = create_user!("victim@example.com")

      conn = login(conn, admin)
      {:ok, view, _} = live(conn, ~p"/admin/users")

      view
      |> element("[data-test='delete-user-#{target.id}']")
      |> render_click()

      view
      |> form("#confirm-delete-form", %{"confirmation" => "  VICTIM@Example.com  "})
      |> render_submit()

      assert {:error, :not_found} = Accounts.get_user(target.id)
    end

    test "cancel closes the modal without deleting", %{conn: conn} do
      admin = create_admin!()
      target = create_user!("victim@example.com")

      conn = login(conn, admin)
      {:ok, view, _} = live(conn, ~p"/admin/users")

      view
      |> element("[data-test='delete-user-#{target.id}']")
      |> render_click()

      assert has_element?(view, "#delete-user-modal")

      view |> render_click("cancel_delete")

      refute has_element?(view, "#delete-user-modal")
      assert {:ok, _} = Accounts.get_user(target.id)
    end
  end
end
