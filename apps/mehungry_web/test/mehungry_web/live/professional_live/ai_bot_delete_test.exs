defmodule MehungryWeb.ProfessionalLive.AiBotDeleteTest do
  @moduledoc """
  Delete flows for the AI-bot admin tools: personas, recipe setups, and recipe
  orders. Guards the regressions where the setup delete button silently failed
  (orders FK was `:restrict`) and orders had no delete path at all.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.AI.Bot

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp persona_fixture(attrs) do
    {:ok, persona} =
      Bot.create_persona(
        Enum.into(attrs, %{name: "Grandma", voice_prompt: "Speaks warmly."})
      )

    persona
  end

  defp setup_fixture(attrs) do
    {:ok, setup} =
      Bot.create_recipe_setup(Enum.into(attrs, %{name: "Cretan table"}))

    setup
  end

  defp order_fixture(setup, user, attrs \\ %{}) do
    {:ok, order} =
      Bot.create_recipe_order(
        Enum.into(attrs, %{
          recipe_setup_id: setup.id,
          bot_user_id: user.id,
          quantity: 3
        })
      )

    order
  end

  describe "personas" do
    test "deletes a persona and removes it from the page", %{conn: conn} do
      persona = persona_fixture(%{name: "Nonna Rosa"})

      {:ok, view, html} = live(conn, ~p"/professional/ai-bot/personas")
      assert html =~ "Nonna Rosa"

      view
      |> element("button[phx-value-id='#{persona.id}']")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Bot.get_persona!(persona.id) end
      refute render(view) =~ "Nonna Rosa"
    end

    test "deleting a persona that a setup uses nilifies the setup's persona", %{conn: conn} do
      persona = persona_fixture(%{name: "Taverna Cook"})
      setup = setup_fixture(%{name: "Seaside taverna", persona_id: persona.id})

      {:ok, view, _html} = live(conn, ~p"/professional/ai-bot/personas")

      view
      |> element("button[phx-value-id='#{persona.id}']")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Bot.get_persona!(persona.id) end
      # The setup survives; its persona link is nilified by the FK.
      assert Bot.get_recipe_setup!(setup.id).persona_id == nil
    end
  end

  describe "recipe setups" do
    test "deletes a setup and removes it from the page", %{conn: conn} do
      setup = setup_fixture(%{name: "Weeknight dinners"})

      {:ok, view, html} = live(conn, ~p"/professional/ai-bot/setups")
      assert html =~ "Weeknight dinners"

      view
      |> element("button[phx-value-id='#{setup.id}']")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Bot.get_recipe_setup!(setup.id) end
      refute render(view) =~ "Weeknight dinners"
    end

    test "deletes a setup that has orders, cascading the orders", %{conn: conn, admin: admin} do
      setup = setup_fixture(%{name: "Batch setup"})
      order = order_fixture(setup, admin)

      {:ok, view, _html} = live(conn, ~p"/professional/ai-bot/setups")

      view
      |> element("button[phx-value-id='#{setup.id}']")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Bot.get_recipe_setup!(setup.id) end
      # The dependent order cascades (FK on_delete: :delete_all) instead of
      # blocking the delete with a :restrict constraint error.
      assert_raise Ecto.NoResultsError, fn -> Bot.get_recipe_order!(order.id) end
    end
  end

  describe "recipe orders" do
    test "deletes an order and removes it from the page", %{conn: conn, admin: admin} do
      setup = setup_fixture(%{name: "Order setup"})
      _order = order_fixture(setup, admin)
      order = order_fixture(setup, admin, %{meal_type: "dinner"})

      {:ok, view, html} = live(conn, ~p"/professional/ai-bot/orders")
      assert html =~ "Order setup"

      view
      |> element("button[phx-value-id='#{order.id}']")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn -> Bot.get_recipe_order!(order.id) end
    end
  end

  test "non-admin is redirected away from the personas tool" do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} =
             live(conn, ~p"/professional/ai-bot/personas")
  end
end
