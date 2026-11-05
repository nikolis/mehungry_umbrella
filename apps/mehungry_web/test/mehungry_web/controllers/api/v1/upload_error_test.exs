defmodule MehungryWeb.Api.V1.UploadErrorTest do
  use MehungryWeb.ConnCase, async: false

  setup :register_and_log_in_api_user

  defmodule ErroringStorage do
    # Mirrors Mehungry.Storage.Supabase's error shape on an upstream failure.
    def signed_upload(_key, _opts), do: {:error, {:http_error, 400, "boom"}}
    def put(_key, _binary, _opts), do: {:error, {:transport_error, :timeout}}
  end

  setup do
    prev_storage = Application.get_env(:mehungry, :storage)
    prev_impl = Application.get_env(:mehungry, :storage_impl)

    Application.put_env(:mehungry, :storage,
      backend: :supabase,
      supabase_url: "https://fake.supabase.co",
      service_role_key: "svc",
      bucket: "bucket"
    )

    Application.put_env(:mehungry, :storage_impl, ErroringStorage)

    on_exit(fn ->
      if prev_storage,
        do: Application.put_env(:mehungry, :storage, prev_storage),
        else: Application.delete_env(:mehungry, :storage)

      if prev_impl,
        do: Application.put_env(:mehungry, :storage_impl, prev_impl),
        else: Application.delete_env(:mehungry, :storage_impl)
    end)

    :ok
  end

  test "presign returns a clean error (not a 500) when storage fails", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/uploads/presign", %{
        "kind" => "recipe_image",
        "content_type" => "image/jpeg"
      })

    assert conn.status in 400..503
    assert conn.status != 500
    assert %{"errors" => _} = json_response(conn, conn.status)
  end
end
