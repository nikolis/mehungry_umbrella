defmodule Mehungry.StorageTest do
  use ExUnit.Case, async: false

  alias Mehungry.Storage

  # Minimal in-memory backend to assert the facade dispatches through
  # `:storage_impl` (the test/rollback seam) without any network.
  defmodule StubImpl do
    @behaviour Mehungry.Storage.Behaviour
    def put(key, _bin, _opts), do: {:ok, %{key: key, url: "stub://#{key}"}}
    def get(_key), do: {:ok, "bytes"}
    def delete(key), do: {:ok, {:deleted, key}}
    def list(_prefix), do: {:ok, []}
    def public_url(key), do: "stub://#{key}"

    def signed_upload(key, _opts),
      do:
        {:ok,
         %{method: "PUT", url: "stub://u", headers: %{}, key: key, public_url: "stub://#{key}"}}
  end

  setup do
    prev_impl = Application.get_env(:mehungry, :storage_impl)
    prev_cfg = Application.get_env(:mehungry, :storage)

    Application.put_env(:mehungry, :storage_impl, StubImpl)

    on_exit(fn ->
      restore(:storage_impl, prev_impl)
      restore(:storage, prev_cfg)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:mehungry, key)
  defp restore(key, val), do: Application.put_env(:mehungry, key, val)

  describe "facade dispatch" do
    test "put/delete/signed_upload route through the configured impl" do
      assert {:ok, %{key: "k", url: "stub://k"}} = Storage.put("k", "x", [])
      assert {:ok, {:deleted, "k"}} = Storage.delete("k")
      assert {:ok, %{method: "PUT"}} = Storage.signed_upload("k")
    end
  end

  describe "key_from_url/1" do
    test "extracts key from AWS virtual-hosted-style URLs (with and without region)" do
      assert Storage.key_from_url("https://bkt.s3.eu-central-1.amazonaws.com/recipe_images/a.jpg") ==
               "recipe_images/a.jpg"

      assert Storage.key_from_url("https://bkt.s3.amazonaws.com/avatars/tmp/b.png") ==
               "avatars/tmp/b.png"
    end

    test "extracts key from a Supabase public URL (dropping the bucket segment)" do
      url = "https://proj.supabase.co/storage/v1/object/public/media/recipe_images/a.jpg"
      assert Storage.key_from_url(url) == "recipe_images/a.jpg"
    end

    test "strips query strings and passes through bare keys / nil" do
      assert Storage.key_from_url("https://bkt.s3.amazonaws.com/x.jpg?token=abc") == "x.jpg"
      assert Storage.key_from_url("recipe_images/a.jpg") == "recipe_images/a.jpg"
      assert Storage.key_from_url(nil) == nil
    end
  end

  describe "owned_url?/1 and delete_by_url/1" do
    test "owned_url? recognises our hosts only" do
      assert Storage.owned_url?("https://b.s3.amazonaws.com/x.jpg")
      assert Storage.owned_url?("https://p.supabase.co/storage/v1/object/public/media/x.jpg")
      refute Storage.owned_url?("https://images.spoonacular.com/x.jpg")
      refute Storage.owned_url?(nil)
    end

    test "delete_by_url skips third-party URLs and deletes owned ones" do
      assert {:ok, :skipped} = Storage.delete_by_url("https://images.spoonacular.com/x.jpg")

      assert {:ok, {:deleted, "recipe_images/a.jpg"}} =
               Storage.delete_by_url("https://b.s3.amazonaws.com/recipe_images/a.jpg")
    end
  end

  describe "Supabase.public_url/1" do
    test "builds the public object path from config" do
      Application.put_env(:mehungry, :storage,
        backend: :supabase,
        supabase_url: "https://proj.supabase.co",
        service_role_key: "srk",
        bucket: "media"
      )

      assert Mehungry.Storage.Supabase.public_url("recipe_images/a.jpg") ==
               "https://proj.supabase.co/storage/v1/object/public/media/recipe_images/a.jpg"
    end
  end
end
