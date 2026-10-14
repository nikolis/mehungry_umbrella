defmodule Mehungry.Social.PinterestHttpStub do
  @moduledoc """
  Test stand-in for the Pinterest HTTP client (wired via the
  `:pinterest_http_client` config key in `config/test.exs`) so tests never hit
  the network. Implements the `HTTPoison.get/2` and `HTTPoison.post/3` surface
  that `Mehungry.Social.Pinterest` uses, returning `HTTPoison`-shaped results.

  Tests control responses through app config, keyed by `:get` / `:post`:

      Application.put_env(:mehungry, :pinterest_http_stub,
        post: fn url, _body, _headers ->
          {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"access_token" => "new"})}}
        end
      )
      on_exit(fn -> Application.delete_env(:mehungry, :pinterest_http_stub) end)
  """

  def get(url, headers \\ []) do
    call(:get, [url, headers], {:ok, %HTTPoison.Response{status_code: 200, body: ~s({"items":[]})}})
  end

  def post(url, body, headers \\ []) do
    call(:post, [url, body, headers], {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}})
  end

  defp call(fun_name, args, default) do
    case Application.get_env(:mehungry, :pinterest_http_stub, [])[fun_name] do
      nil -> default
      fun -> apply(fun, args)
    end
  end
end
