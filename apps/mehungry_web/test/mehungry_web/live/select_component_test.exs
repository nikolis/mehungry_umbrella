defmodule MehungryWeb.SelectComponentTest do
  use Phoenix.LiveView

  use MehungryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import LiveIsolatedComponent

  describe "Select Component Test" do
    setup [:register_and_log_in_user]

    test "Select Component test", %{conn: _conn, user: user} do
      items = [%{id: 1, name: "one"}, %{id: 2, name: "two"}, %{id: 3, name: "three"}]

      form =
        to_form(%{"number_selection" => "", "anything_else" => ""})

      form = %Phoenix.HTML.Form{form | index: 1}

      {ok, view, html} =
        live_isolated_component(MehungryWeb.SelectComponent, %{
          current_user: user,
          form: form,
          items: items,
          input_variable: "number_selection",
          id: 1,
          initial_open: true
        })

      clicked =
        view
        |> element("li", "three")
        |> render_click()

      IO.inspect(clicked, label: "clicked")

      IO.inspect(
        "--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
      )

      IO.inspect(html, label: "clicked")
    end
  end
end
