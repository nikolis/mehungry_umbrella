defmodule MehungryWeb.VisitorPlugTest do
  use MehungryWeb.ConnCase, async: true

  alias MehungryWeb.VisitorPlug

  defp conn_with_consent(status) do
    build_conn()
    |> init_test_session(%{})
    |> assign(:cookie_consent, status)
  end

  describe "call/2 with consent :accepted" do
    test "assigns a visitor_id UUID to the session" do
      conn = conn_with_consent(:accepted) |> VisitorPlug.call([])
      visitor_id = get_session(conn, :visitor_id)
      assert is_binary(visitor_id)
      assert String.length(visitor_id) == 36
    end

    test "preserves an existing visitor_id" do
      existing_id = Ecto.UUID.generate()

      conn =
        conn_with_consent(:accepted)
        |> put_session(:visitor_id, existing_id)
        |> VisitorPlug.call([])

      assert get_session(conn, :visitor_id) == existing_id
    end
  end

  describe "call/2 with consent :pending" do
    test "does not assign a visitor_id" do
      conn = conn_with_consent(:pending) |> VisitorPlug.call([])
      assert get_session(conn, :visitor_id) == nil
    end
  end

  describe "call/2 with consent :declined" do
    test "does not assign a visitor_id" do
      conn = conn_with_consent(:declined) |> VisitorPlug.call([])
      assert get_session(conn, :visitor_id) == nil
    end
  end
end
