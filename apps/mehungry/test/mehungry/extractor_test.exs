defmodule Mehungry.ExtractorTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Extractor
  alias Mehungry.Extractor.Settings

  test "connection falls back to the configured base URL and no token when unset" do
    assert {"http://127.0.0.1:8000", nil} = Extractor.connection()
  end

  test "saved settings override the connection; trailing slash is trimmed" do
    assert {:ok, _} =
             Extractor.update_settings(%{
               "base_url" => "https://extractor.example.com/",
               "auth_token" => "secret"
             })

    assert {"https://extractor.example.com", "secret"} = Extractor.connection()
  end

  test "a blank token is stored as nil (no Authorization header)" do
    {:ok, _} =
      Extractor.update_settings(%{"base_url" => "https://x.example.com", "auth_token" => "   "})

    assert {"https://x.example.com", nil} = Extractor.connection()
  end

  test "rejects a non-http(s) URL" do
    assert {:error, changeset} = Extractor.update_settings(%{"base_url" => "ftp://nope"})
    assert "must be a valid http(s) URL" in errors_on(changeset).base_url
  end

  test "requires a base URL" do
    assert {:error, changeset} = Extractor.update_settings(%{"base_url" => "  "})
    assert errors_on(changeset).base_url != []
  end

  test "update is an upsert — a single singleton row is kept" do
    {:ok, _} = Extractor.update_settings(%{"base_url" => "https://a.example.com"})
    {:ok, _} = Extractor.update_settings(%{"base_url" => "https://b.example.com"})

    assert {"https://b.example.com", _} = Extractor.connection()
    assert Repo.aggregate(Settings, :count) == 1
  end
end
